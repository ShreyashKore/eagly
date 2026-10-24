//! The screen mirror's iOS half: screenshots, touch, keyboard, hardware
//! buttons, the pasteboard and rotation, through the CoreDevice services
//! Xcode 27's Device Hub uses. docs/IOS_SCREEN_MIRROR.md has the whole design
//! and what hardware showed.
//!
//! The services come from Xcode's developer disk image (`dtuhidd`,
//! `dtscreencaptured`, `dtpasteboardd`, …), so the phone needs Developer Mode
//! and that image mounted. They are reached the way Xcode reaches them: a
//! lockdown `CoreDeviceProxy` tunnel over usbmux, a userspace TCP stack on top
//! of it, and RemoteXPC services listed by Remote Service Discovery.
//!
//! The video itself is not here. On macOS it comes from QuickTime's capture
//! route (`IosScreenCapturePlugin.swift`); elsewhere from
//! [`start_ios_screenshot_stream`].

use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};
use std::time::Duration;

use idevice::core_device::{
    build_screen_audio_offer, build_screen_video_offer, build_start_audio_parameters,
    build_start_video_parameters, ButtonState, CallInfoBlob, CoreDeviceError, DisplayServiceClient,
    ImageFormat, IndigoHidClient, OrientationServiceClient, PasteboardServiceClient,
    RotationDirection, ScreenCaptureServiceClient, UniversalHidServiceClient,
    TOUCHSCREEN_STATE_CONTACT, TOUCHSCREEN_STATE_RELEASE,
};
use idevice::services::springboardservices::{InterfaceOrientation, SpringBoardServicesClient};
use idevice::{IdeviceError, IdeviceService};
use tokio::sync::{mpsc, oneshot};
use tokio::time::MissedTickBehavior;
use tokio_util::sync::CancellationToken;

use super::ios::{provider_for, IosError};
use crate::frb_generated::StreamSink;
use crate::tunnel::{connect, io_error, Rw, Tunnel};

/// What a phone offers the mirror, read from its Remote Service Discovery
/// listing. All false when the developer disk image is not mounted.
pub struct IosMirrorSupport {
    /// `screencaptureservice`: full-resolution PNG screenshots.
    pub screenshots: bool,
    /// The HID services: touch, keyboard and hardware buttons.
    pub input: bool,
    /// `pasteboardservice`: pasting the desktop's text.
    pub pasteboard: bool,
    /// `devicecontrol`: Device Hub's simulated rotation.
    pub rotation: bool,
    /// Whether `displayservice` can stream the screen, which takes iOS 27.
    /// When it can, input only lands while a stream is open (see
    /// [`start_ios_input`]).
    pub display_stream: bool,
}

/// Which way the user interface faces, from SpringBoard. The digitizer always
/// takes coordinates in the panel's own portrait frame, so a landscape
/// picture has to be mapped back through this.
pub enum IosInterfaceOrientation {
    Portrait,
    PortraitUpsideDown,
    /// Home indicator on the left.
    LandscapeLeft,
    /// Home indicator on the right.
    LandscapeRight,
    Unknown,
}

pub enum IosTouchPhase {
    Down,
    Move,
    Up,
}

/// Which way [`rotate_ios_device`] turns the phone, by 90°.
pub enum IosRotation {
    Left,
    Right,
}

/// What Device Hub sends as the controller's feature mask. The device's own,
/// larger mask makes its negotiator produce an invalid video config.
const CLIENT_SUPPORTED_FEATURES: u64 = 140;

/// How long backboardd takes to re-match the HID surfaces once the input gate
/// opens, before events dispatch (from the crate's own `hid` tool).
const GATE_SETTLE: Duration = Duration::from_millis(300);

/// How long the phone takes to open the virtual HID devices of a new
/// session. `dtuhidd` creates a touchscreen, a keyboard and buttons for every
/// session that connects, and the event system opened the touchscreen about
/// 150 ms later on an iPhone 16e (iOS 26.6). Events sent before then wait in
/// a queue and arrive in one burst ("dispatched 6 pending events"), or are
/// dropped when the device is not active yet ("No active service, dropping
/// event"), which turned a drag into a tap. So a session is only handed out
/// once they are open.
const DEVICES_SETTLE: Duration = Duration::from_millis(300);

/// How long the last events of a session take to reach the phone's event
/// system: a release sent just before the connection closes was dropped.
const CLOSE_DRAIN: Duration = Duration::from_millis(100);

/// How often a finger held still is reported again.
const STILL_INTERVAL: Duration = Duration::from_millis(16);

/// How far a still finger wobbles: about a pixel on a phone (65535 / 1170).
///
/// Without it a drag that stops and then lets go still flings, as if the
/// finger had lifted mid-swipe: on an iOS 26.6 iPhone every release after a
/// pause flicked the home screen a page, whether the still reports repeated
/// one position or moved by one unit. A wobble of a pixel, like a real
/// finger's, settles it (docs/IOS_SCREEN_MIRROR.md).
const STILL_WOBBLE: u16 = 64;

/// The pasteboard ⌘V reads.
const GENERAL_PASTEBOARD: &str = "general";

// ── Connecting ──────────────────────────────────────────────────────────

// The tunnel itself is shared with app control (`tunnel.rs`); only the
// mirror asks whether it can stream the screen.
impl Tunnel {
    /// Whether `displayservice` exists and says it can stream. On iOS 26 it
    /// exists but reports `supportedFeatures: 0`, and starting a stream fails
    /// with "Remote control requires iOS 27.0 or later on this device."
    async fn streams_display(&mut self) -> bool {
        if !self.offers::<DisplayServiceClient<Rw>>() {
            return false;
        }
        let Ok(mut client) = connect!(self, DisplayServiceClient<Rw>) else {
            return false;
        };
        let Ok(info) = client.get_media_support_info().await else {
            return false;
        };
        info.as_dictionary()
            .and_then(|info| info.get("supportedFeatures"))
            .and_then(|features| {
                features
                    .as_signed_integer()
                    .or_else(|| features.as_unsigned_integer().map(|f| f as i64))
            })
            .is_some_and(|features| features != 0)
    }
}

/// Reads which mirror services `udid` offers.
pub async fn probe_ios_mirror(udid: String) -> Result<IosMirrorSupport, IosError> {
    let mut tunnel = Tunnel::open(&udid).await?;
    let support = IosMirrorSupport {
        screenshots: tunnel.offers::<ScreenCaptureServiceClient<Rw>>(),
        input: tunnel.offers::<UniversalHidServiceClient<Rw>>()
            && tunnel.offers::<IndigoHidClient<Rw>>(),
        pasteboard: tunnel.offers::<PasteboardServiceClient<Rw>>(),
        rotation: tunnel.offers::<OrientationServiceClient<Rw>>(),
        display_stream: tunnel.streams_display().await,
    };
    tunnel.close().await;
    Ok(support)
}

/// Which way the phone's user interface faces right now.
pub async fn read_ios_interface_orientation(
    udid: String,
) -> Result<IosInterfaceOrientation, IosError> {
    let provider = provider_for(&udid).await?;
    let mut springboard = SpringBoardServicesClient::connect(&provider).await?;
    Ok(match springboard.get_interface_orientation().await? {
        InterfaceOrientation::Portrait => IosInterfaceOrientation::Portrait,
        InterfaceOrientation::PortraitUpsideDown => IosInterfaceOrientation::PortraitUpsideDown,
        InterfaceOrientation::LandscapeLeft => IosInterfaceOrientation::LandscapeLeft,
        InterfaceOrientation::LandscapeRight => IosInterfaceOrientation::LandscapeRight,
        InterfaceOrientation::Unknown => IosInterfaceOrientation::Unknown,
    })
}

// ── Screenshots ─────────────────────────────────────────────────────────

/// Screenshots asked for at once, each on its own connection. The phone takes
/// one at a time but sends one while it takes the next: on an iPhone 16e
/// (iOS 26.6) two in flight gave 2.5–2.8 frames a second against 1.7, each
/// frame about 200 ms older; three gave 2.9–3.3, and four once left a request
/// hanging for a minute (`tests::screenshot_throughput`).
const SCREENSHOTS_IN_FLIGHT: usize = 2;

/// How long to wait before asking again when the phone is busy taking another
/// screenshot ([`is_capture_busy`]).
const CAPTURE_BUSY_RETRY: Duration = Duration::from_millis(10);

/// Whether the phone refused a screenshot because it is taking another:
/// "A screenshot capture is already in progress", CoreDevice error 25003.
/// The crate hands the device's error over only as its debug text.
fn is_capture_busy(error: &IdeviceError) -> bool {
    matches!(
        error,
        IdeviceError::CoreDevice(CoreDeviceError::DeviceError(detail))
            if detail.contains("\"code\": Integer(25003)")
    )
}

/// One screenshot from `capture`, asked for again while the phone is busy
/// with another, a mirror's stream say.
async fn take_screenshot(
    capture: &mut ScreenCaptureServiceClient<Rw>,
) -> Result<Vec<u8>, IdeviceError> {
    loop {
        match capture.take_screenshot(None, ImageFormat::Png).await {
            Err(error) if is_capture_busy(&error) => tokio::time::sleep(CAPTURE_BUSY_RETRY).await,
            shot => return shot,
        }
    }
}

/// One full-resolution PNG of the screen, with the real status bar.
pub async fn capture_ios_screenshot(udid: String) -> Result<Vec<u8>, IosError> {
    let mut tunnel = Tunnel::open(&udid).await?;
    let mut capture = connect!(&mut tunnel, ScreenCaptureServiceClient<Rw>)?;
    let png = take_screenshot(&mut capture).await;
    tunnel.close().await;
    Ok(png?)
}

/// Screenshot streams, keyed by a caller-chosen id, for the same reasons as
/// the syslog registry in `ios.rs`.
static SCREENSHOT_STREAMS: LazyLock<Mutex<HashMap<String, CancellationToken>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Streams PNG screenshots until [`stop_ios_screenshot_stream`] is called
/// with the same `session_id`, the phone goes away, or Dart drops the stream:
/// the mirror's picture where QuickTime's capture route is not available. A
/// 1170×2532 PNG takes about 550 ms and `jpeg` is refused on iOS 26.6, so
/// [`SCREENSHOTS_IN_FLIGHT`] are asked for at once, for two or three frames a
/// second.
pub async fn start_ios_screenshot_stream(
    sink: StreamSink<Vec<u8>>,
    udid: String,
    session_id: String,
) -> Result<(), IosError> {
    // Claimed before connecting, as in `start_ios_syslog`: a stop that lands
    // in the meantime has to find a token to cancel.
    let token = claim_screenshot_stream(&session_id);
    let connected = async {
        let mut tunnel = Tunnel::open(&udid).await?;
        let mut captures = Vec::with_capacity(SCREENSHOTS_IN_FLIGHT);
        for _ in 0..SCREENSHOTS_IN_FLIGHT {
            captures.push(connect!(&mut tunnel, ScreenCaptureServiceClient<Rw>)?);
        }
        Ok::<_, IosError>((tunnel, captures))
    }
    .await;
    let (tunnel, captures) = match connected {
        Ok(connected) => connected,
        Err(error) => {
            forget_screenshot_stream(&session_id);
            return Err(error);
        }
    };
    if token.is_cancelled() {
        tunnel.close().await;
        forget_screenshot_stream(&session_id);
        return Ok(());
    }

    tokio::spawn(async move {
        // `add` fails once Dart has dropped the stream.
        stream_screenshots(captures, token, |png| sink.add(png).is_ok()).await;
        tunnel.close().await;
        forget_screenshot_stream(&session_id);
    });
    Ok(())
}

/// Takes screenshots with every one of `captures` at once, handing each to
/// `deliver` newest last, until `token` is cancelled, `deliver` returns false
/// or every capture has failed (the phone has gone). Cancels `token` on the
/// way out, so the captures stop however it ends.
async fn stream_screenshots(
    captures: Vec<ScreenCaptureServiceClient<Rw>>,
    token: CancellationToken,
    mut deliver: impl FnMut(Vec<u8>) -> bool,
) {
    let (sent, mut arriving) = mpsc::channel(captures.len().max(1));
    for mut capture in captures {
        let sent = sent.clone();
        let token = token.clone();
        tokio::spawn(async move {
            loop {
                let asked = tokio::time::Instant::now();
                tokio::select! {
                    // A cancelled branch drops the in-flight capture; safe
                    // only because the client is never used again after the
                    // break.
                    biased;
                    _ = token.cancelled() => break,
                    shot = take_screenshot(&mut capture) => match shot {
                        Ok(png) => if sent.send((asked, png)).await.is_err() { break },
                        Err(_) => break,
                    },
                }
            }
        });
    }
    drop(sent);
    // Screenshots can arrive out of order; one asked for before the one last
    // delivered is older than it, and dropped.
    let mut delivered = None;
    loop {
        tokio::select! {
            biased;
            _ = token.cancelled() => break,
            shot = arriving.recv() => match shot {
                Some((asked, _)) if delivered.is_some_and(|last| asked < last) => {}
                Some((asked, png)) => {
                    delivered = Some(asked);
                    if !deliver(png) { break }
                }
                None => break,
            },
        }
    }
    token.cancel();
}

/// Stops the stream started under `session_id`. Idempotent; like
/// `stop_ios_syslog` it can overtake the start it follows, so Dart only calls
/// it for a stream that has not already ended.
pub async fn stop_ios_screenshot_stream(session_id: String) {
    SCREENSHOT_STREAMS
        .lock()
        .expect("screenshot stream registry poisoned")
        .entry(session_id)
        .or_default()
        .cancel();
}

fn claim_screenshot_stream(session_id: &str) -> CancellationToken {
    SCREENSHOT_STREAMS
        .lock()
        .expect("screenshot stream registry poisoned")
        .entry(session_id.to_string())
        .or_default()
        .clone()
}

fn forget_screenshot_stream(session_id: &str) {
    SCREENSHOT_STREAMS
        .lock()
        .expect("screenshot stream registry poisoned")
        .remove(session_id);
}

// ── Input ───────────────────────────────────────────────────────────────

enum InputCommand {
    Touch {
        phase: IosTouchPhase,
        x: u16,
        y: u16,
    },
    Key {
        usage: u16,
        down: bool,
    },
    Button {
        page: u16,
        usage: u16,
        down: bool,
    },
    Pasteboard {
        text: String,
        reply: oneshot::Sender<Result<(), IosError>>,
    },
    Rotate {
        rotation: IosRotation,
        reply: oneshot::Sender<Result<(), IosError>>,
    },
}

/// Input sessions by caller-chosen id. Dart picks a fresh id for every
/// session, so a worker can always remove its own entry when it ends.
///
/// Commands go through one channel to one worker per session because touch
/// order matters and bridge calls have none of their own: the send functions
/// are synchronous, so they enqueue in the order Dart made them.
static INPUT_SESSIONS: LazyLock<Mutex<HashMap<String, mpsc::UnboundedSender<InputCommand>>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Connects touch, keyboard and buttons for `udid` and keeps them open under
/// `session_id` until [`stop_ios_input`].
///
/// On iOS 27 the phone drops synthetic HID events unless a `displayservice`
/// media stream is open, so where the phone can stream, one is started and
/// its RTP thrown away: Device Hub's screen-sharing indicator shows on the
/// phone for as long as the session lasts. iOS 26.6 takes the events without
/// one. The iOS 27 path follows the crate's own tool and is unverified on
/// hardware.
pub async fn start_ios_input(udid: String, session_id: String) -> Result<(), IosError> {
    let clients = InputClients::connect(&udid).await?;
    let (sender, receiver) = mpsc::unbounded_channel();
    INPUT_SESSIONS
        .lock()
        .expect("input session registry poisoned")
        .insert(session_id.clone(), sender);
    tokio::spawn(run_input(udid, session_id, clients, receiver));
    Ok(())
}

/// Ends the session: a finger still down is lifted. Idempotent.
pub async fn stop_ios_input(session_id: String) {
    // Dropping the sender closes the channel, which ends the worker.
    INPUT_SESSIONS
        .lock()
        .expect("input session registry poisoned")
        .remove(&session_id);
}

/// One touch sample at (`x`, `y`), fractions of the panel's portrait width
/// and height. False once the session has ended.
#[flutter_rust_bridge::frb(sync)]
pub fn send_ios_touch(session_id: String, phase: IosTouchPhase, x: f64, y: f64) -> bool {
    send(
        &session_id,
        InputCommand::Touch {
            phase,
            x: to_digitizer(x),
            y: to_digitizer(y),
        },
    )
}

/// A key on the HID Keyboard/Keypad page (0x07) going down or up, modifiers
/// included. The phone types through its own hardware-keyboard layout.
#[flutter_rust_bridge::frb(sync)]
pub fn send_ios_key(session_id: String, usage: u16, down: bool) -> bool {
    send(&session_id, InputCommand::Key { usage, down })
}

/// A hardware button going down or up: Consumer page (0x0C) usages such as
/// Menu (0x40, Home), Power (0x30), Volume Increment (0xE9) or Mute (0xE2).
#[flutter_rust_bridge::frb(sync)]
pub fn send_ios_button(session_id: String, usage_page: u16, usage: u16, down: bool) -> bool {
    send(
        &session_id,
        InputCommand::Button {
            page: usage_page,
            usage,
            down,
        },
    )
}

/// Replaces the phone's general pasteboard with `text`.
pub async fn set_ios_pasteboard_text(session_id: String, text: String) -> Result<(), IosError> {
    let (reply, answer) = oneshot::channel();
    request(
        &session_id,
        InputCommand::Pasteboard { text, reply },
        answer,
    )
    .await
}

/// Turns the phone 90° the way Device Hub's rotate buttons do. Apps that
/// support the new orientation follow it; the iPhone home screen does not.
pub async fn rotate_ios_device(session_id: String, rotation: IosRotation) -> Result<(), IosError> {
    let (reply, answer) = oneshot::channel();
    request(
        &session_id,
        InputCommand::Rotate { rotation, reply },
        answer,
    )
    .await
}

fn send(session_id: &str, command: InputCommand) -> bool {
    INPUT_SESSIONS
        .lock()
        .expect("input session registry poisoned")
        .get(session_id)
        .is_some_and(|sender| sender.send(command).is_ok())
}

async fn request(
    session_id: &str,
    command: InputCommand,
    answer: oneshot::Receiver<Result<(), IosError>>,
) -> Result<(), IosError> {
    let ended = || IosError::Other("The mirror's input session has ended.".into());
    if !send(session_id, command) {
        return Err(ended());
    }
    answer.await.unwrap_or_else(|_| Err(ended()))
}

fn to_digitizer(fraction: f64) -> u16 {
    (fraction.clamp(0.0, 1.0) * 65535.0).round() as u16
}

/// The connections one input session holds.
struct InputClients {
    tunnel: Tunnel,
    touch: UniversalHidServiceClient<Rw>,
    indigo: IndigoHidClient<Rw>,
    gate: Option<InputGate>,
}

impl InputClients {
    async fn connect(udid: &str) -> Result<InputClients, IosError> {
        let mut tunnel = Tunnel::open(udid).await?;
        let gate = if tunnel.streams_display().await {
            let gate = InputGate::open(&mut tunnel).await?;
            tokio::time::sleep(GATE_SETTLE).await;
            Some(gate)
        } else {
            None
        };
        let touch = connect!(&mut tunnel, UniversalHidServiceClient<Rw>)?;
        let indigo = connect!(&mut tunnel, IndigoHidClient<Rw>)?;
        tokio::time::sleep(DEVICES_SETTLE).await;
        Ok(InputClients {
            tunnel,
            touch,
            indigo,
            gate,
        })
    }

    async fn close(mut self) {
        if let Some(gate) = self.gate.take() {
            gate.close().await;
        }
        self.tunnel.close().await;
    }
}

/// The iOS 27 media stream that lets HID events through: the same
/// audio-then-video start Device Hub makes, with the RTP read and dropped so
/// the userspace stack's queues stay empty.
struct InputGate {
    display: DisplayServiceClient<Rw>,
    drain: CancellationToken,
}

impl InputGate {
    async fn open(tunnel: &mut Tunnel) -> Result<InputGate, IosError> {
        let mut display = connect!(tunnel, DisplayServiceClient<Rw>)?;
        let adapter = &tunnel.adapter;
        let audio = adapter.bind_udp(0).await.map_err(io_error)?;
        let video = adapter.bind_udp(0).await.map_err(io_error)?;
        let receiver_ip = adapter.host_ip().to_string();
        let sender_ip = adapter.peer_ip().to_string();
        // The host endpoint as a captured Device Hub offer the device accepted
        // describes it.
        let call_info = CallInfoBlob {
            call_id: 0,
            client_version: 1,
            device_type: "Mac17,7".into(),
            framework_version: "2205.3.1".into(),
            os_version: "25F71".into(),
            device_name: None,
            audio_device_uid: None,
        };
        let session = uuid::Uuid::new_v4();
        let call_id = || uuid::Uuid::new_v4().to_string().to_uppercase();

        let audio_offer = build_screen_audio_offer(&call_id(), &call_info)?;
        display
            .start_media_stream(build_start_audio_parameters(
                &receiver_ip,
                audio.local_port(),
                &sender_ip,
                50000,
                audio_offer,
                CLIENT_SUPPORTED_FEATURES,
                session,
            ))
            .await?;
        let video_offer = build_screen_video_offer(
            &call_id(),
            &call_info,
            uuid::Uuid::new_v4().as_u128() as u32,
        )?;
        display
            .start_media_stream(build_start_video_parameters(
                &receiver_ip,
                video.local_port(),
                &sender_ip,
                50001,
                video_offer,
                CLIENT_SUPPORTED_FEATURES,
                1,
                session,
            ))
            .await?;

        let drain = CancellationToken::new();
        for socket in [audio, video] {
            let drain = drain.clone();
            tokio::spawn(async move {
                loop {
                    tokio::select! {
                        _ = drain.cancelled() => break,
                        received = socket.recv() => if received.is_err() { break },
                    }
                }
            });
        }
        Ok(InputGate { display, drain })
    }

    async fn close(mut self) {
        self.drain.cancel();
        let _ = self.display.stop_media_stream().await;
    }
}

/// Owns one session's connections and applies its commands in order. A
/// finger held still is re-sent with a wobble every [`STILL_INTERVAL`].
///
/// A failed send reconnects once and drops the command that failed: the
/// usual cause is the phone re-enumerating on USB, which it does when a
/// QuickTime capture starts. Touch reports carry absolute state, so the next
/// sample of a drag simply continues it.
async fn run_input(
    udid: String,
    session_id: String,
    mut clients: InputClients,
    mut commands: mpsc::UnboundedReceiver<InputCommand>,
) {
    let mut held: Option<(u16, u16)> = None;
    let mut wobbled = false;
    let mut still = tokio::time::interval(STILL_INTERVAL);
    still.set_missed_tick_behavior(MissedTickBehavior::Delay);

    loop {
        tokio::select! {
            biased;
            command = commands.recv() => {
                let Some(command) = command else { break };
                still.reset();
                if apply(&mut clients, command, &mut held).await.is_err() {
                    match InputClients::connect(&udid).await {
                        Ok(fresh) => std::mem::replace(&mut clients, fresh).close().await,
                        Err(_) => break,
                    }
                }
            }
            _ = still.tick(), if held.is_some() => {
                let Some((x, y)) = held else { continue };
                wobbled = !wobbled;
                let x = if wobbled { x.saturating_add(STILL_WOBBLE) } else { x };
                if clients.touch.send_touchscreen(TOUCHSCREEN_STATE_CONTACT, x, y, None).await.is_err() {
                    held = None;
                }
            }
        }
    }

    if let Some((x, y)) = held {
        let _ = clients
            .touch
            .send_touchscreen(TOUCHSCREEN_STATE_RELEASE, x, y, None)
            .await;
    }
    tokio::time::sleep(CLOSE_DRAIN).await;
    clients.close().await;
    INPUT_SESSIONS
        .lock()
        .expect("input session registry poisoned")
        .remove(&session_id);
}

async fn apply(
    clients: &mut InputClients,
    command: InputCommand,
    held: &mut Option<(u16, u16)>,
) -> Result<(), IdeviceError> {
    let state = |down: bool| {
        if down {
            ButtonState::Down
        } else {
            ButtonState::Up
        }
    };
    match command {
        InputCommand::Touch {
            phase: IosTouchPhase::Up,
            x,
            y,
        } => {
            *held = None;
            clients
                .touch
                .send_touchscreen(TOUCHSCREEN_STATE_RELEASE, x, y, None)
                .await
        }
        InputCommand::Touch { x, y, .. } => {
            *held = Some((x, y));
            clients
                .touch
                .send_touchscreen(TOUCHSCREEN_STATE_CONTACT, x, y, None)
                .await
        }
        InputCommand::Key { usage, down } => {
            clients
                .indigo
                .send_keyboard(usage.into(), state(down))
                .await
        }
        InputCommand::Button { page, usage, down } => {
            clients
                .indigo
                .send_button(page.into(), usage.into(), state(down))
                .await
        }
        // These answer through their reply rather than failing the session:
        // a pasteboard or rotation error says nothing about the HID link.
        InputCommand::Pasteboard { text, reply } => {
            let result = async {
                let mut pasteboard = connect!(&mut clients.tunnel, PasteboardServiceClient<Rw>)?;
                Ok::<_, IosError>(pasteboard.set_text(&text, GENERAL_PASTEBOARD).await?)
            }
            .await;
            let _ = reply.send(result);
            Ok(())
        }
        InputCommand::Rotate { rotation, reply } => {
            let result = async {
                let mut orientation = connect!(&mut clients.tunnel, OrientationServiceClient<Rw>)?;
                orientation
                    .rotate(match rotation {
                        IosRotation::Left => RotationDirection::Left,
                        IosRotation::Right => RotationDirection::Right,
                    })
                    .await?;
                Ok::<_, IosError>(())
            }
            .await;
            let _ = reply.send(result);
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fractions_map_onto_the_digitizer_range() {
        assert_eq!(to_digitizer(0.0), 0);
        assert_eq!(to_digitizer(0.5), 32768);
        assert_eq!(to_digitizer(1.0), 65535);
    }

    #[test]
    fn fractions_outside_the_screen_are_clamped() {
        assert_eq!(to_digitizer(-0.2), 0);
        assert_eq!(to_digitizer(1.7), 65535);
    }

    /// Frames a second from [`stream_screenshots`] with 1–3 screenshots in
    /// flight, each on its own connection over one tunnel. Needs a phone:
    /// `EAGLY_TEST_IOS_UDID=<udid> cargo test --release screenshot_stream -- --ignored --nocapture`
    #[tokio::test(flavor = "multi_thread")]
    #[ignore]
    async fn screenshot_stream_throughput() {
        let udid = std::env::var("EAGLY_TEST_IOS_UDID").expect("EAGLY_TEST_IOS_UDID");
        let Ok(mut tunnel) = Tunnel::open(&udid).await else {
            panic!("no tunnel")
        };
        for in_flight in [1, SCREENSHOTS_IN_FLIGHT, 3] {
            let mut captures = Vec::new();
            for _ in 0..in_flight {
                let Ok(capture) = connect!(&mut tunnel, ScreenCaptureServiceClient<Rw>) else {
                    panic!("no screencaptureservice")
                };
                captures.push(capture);
            }
            let token = CancellationToken::new();
            let stop = token.clone();
            tokio::spawn(async move {
                tokio::time::sleep(Duration::from_secs(15)).await;
                stop.cancel();
            });
            let started = std::time::Instant::now();
            let mut frames = 0;
            let mut widest_gap = Duration::ZERO;
            let mut last = started;
            stream_screenshots(captures, token, |png| {
                assert!(png.starts_with(b"\x89PNG"));
                frames += 1;
                widest_gap = widest_gap.max(last.elapsed());
                last = std::time::Instant::now();
                true
            })
            .await;
            let elapsed = started.elapsed().as_secs_f64();
            println!(
                "{in_flight} in flight: {frames} frames in {elapsed:.1} s = {:.2} fps, \
                 widest gap {} ms",
                frames as f64 / elapsed,
                widest_gap.as_millis(),
            );
            assert!(frames > 0);
        }
        tunnel.close().await;
    }
}
