//! iOS device discovery, backed by the `idevice` crate talking to usbmuxd
//! directly. Replaces shelling out to `idevice_id -l` + `ideviceinfo -u <udid>`.

use idevice::provider::IdeviceProvider;
use idevice::services::installation_proxy::InstallationProxyClient;
use idevice::services::lockdown::LockdownClient;
use idevice::services::syslog_relay::SyslogRelayClient;
use idevice::usbmuxd::{Connection, UsbmuxdAddr, UsbmuxdConnection, UsbmuxdDevice};
use idevice::{IdeviceError, IdeviceService};
use plist::Value;
use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};
use tokio_util::sync::CancellationToken;

use crate::frb_generated::StreamSink;

/// Label lockdownd records against our session. Shows up in the device's
/// pairing records, so it should name the app rather than the library.
const CLIENT_LABEL: &str = "eagly";

/// A device usbmuxd knows about, before anything has asked lockdownd about it.
///
/// Listing is deliberately separate from describing: enumerating costs one
/// usbmuxd round trip, while describing opens a lockdown session and a TLS
/// handshake per device. The device list is polled, so only the cheap half
/// runs on every tick.
pub struct IosDeviceHandle {
    pub udid: String,
    pub is_network: bool,
}

/// What lockdownd says about one device.
///
/// Every field but `udid`/`status`/`is_network` is optional: a locked or
/// unpaired device answers usbmuxd (so we know it exists) while refusing
/// lockdownd (so we know nothing else about it). Those devices still belong in
/// the list — the UI renders guidance for them off `status`.
pub struct IosDeviceSummary {
    pub udid: String,
    /// `"device"` when lockdownd answered; otherwise `"unpaired"`, `"locked"`
    /// or `"unavailable"`. Matches the strings `IosGuidance` switches on.
    pub status: String,
    /// The user-chosen device name, e.g. `"QA iPhone"`.
    pub name: Option<String>,
    /// Marketing name lockdownd reports, e.g. `"iPhone"`. Used as a fallback
    /// when the device has no user-chosen name.
    pub product_name: Option<String>,
    /// Apple's internal model identifier, e.g. `"iPhone14,2"`.
    pub product_type: Option<String>,
    /// Board-level model, e.g. `"D73AP"`. Last-resort fallback when
    /// `product_type` is missing and so cannot be mapped to a marketing name.
    pub hardware_model: Option<String>,
    /// iOS version, e.g. `"17.5.1"`.
    pub product_version: Option<String>,
    pub is_network: bool,
}

/// Errors crossing into Dart. Deliberately a small, closed set keyed to what
/// the UI can act on, rather than a mirror of [`IdeviceError`]'s ~50 variants.
pub enum IosError {
    /// usbmuxd itself is unreachable — on Windows it ships with Apple Mobile
    /// Device Support, so this is the state that drives the install hint.
    UsbmuxdUnavailable,
    DeviceNotFound(String),
    NotPaired(String),
    /// The "Trust This Computer?" prompt is on screen right now.
    PairingDialogPending(String),
    Locked(String),
    Other(String),
}

impl IosError {
    /// Maps onto the legacy status strings the device UI already understands.
    ///
    /// `PairingDialogPending` collapses into `"unpaired"` because that is the
    /// closest existing guidance panel; giving it a panel of its own is a UI
    /// change that belongs with the rest of the device-info work.
    fn status(&self) -> &'static str {
        match self {
            IosError::NotPaired(_) | IosError::PairingDialogPending(_) => "unpaired",
            IosError::Locked(_) => "locked",
            _ => "unavailable",
        }
    }
}

impl From<IdeviceError> for IosError {
    fn from(error: IdeviceError) -> Self {
        let detail = error.to_string();
        match error {
            IdeviceError::Usbmuxd(_) => IosError::UsbmuxdUnavailable,
            IdeviceError::DeviceNotFound => IosError::DeviceNotFound(detail),
            IdeviceError::DeviceLocked | IdeviceError::PasswordProtected => {
                IosError::Locked(detail)
            }
            IdeviceError::InvalidHostID
            | IdeviceError::SessionInactive
            | IdeviceError::UserDeniedPairing => IosError::NotPaired(detail),
            IdeviceError::PairingDialogResponsePending => IosError::PairingDialogPending(detail),
            _ => IosError::Other(detail),
        }
    }
}

/// Lists every device usbmuxd knows about.
///
/// Cheap by design — this is what the discovery poll calls. Only a failure to
/// reach usbmuxd is an error; an empty list just means nothing is plugged in.
pub async fn list_ios_devices() -> Result<Vec<IosDeviceHandle>, IosError> {
    let mut usbmuxd = connect_usbmuxd().await?;
    let devices = usbmuxd.get_devices().await?;

    Ok(devices
        .iter()
        .map(|device| IosDeviceHandle {
            udid: device.udid.clone(),
            is_network: is_network(device),
        })
        .collect())
}

/// Describes one device, opening a lockdown session to do it.
///
/// A device that refuses lockdownd is not an error: it comes back with the
/// status explaining why and no other fields. Callers list first and describe
/// only what they do not already know — one locked iPhone must never empty
/// the device list.
pub async fn describe_ios_device(udid: String) -> Result<IosDeviceSummary, IosError> {
    let mut usbmuxd = connect_usbmuxd().await?;
    let device = usbmuxd.get_device(&udid).await?;

    Ok(describe(&device)
        .await
        .unwrap_or_else(|error| IosDeviceSummary {
            udid,
            status: error.status().to_string(),
            name: None,
            product_name: None,
            product_type: None,
            hardware_model: None,
            product_version: None,
            is_network: is_network(&device),
        }))
}

/// Opens the muxer socket.
///
/// Any failure here means usbmuxd is not running, which arrives as
/// `IdeviceError::Socket` rather than `IdeviceError::Usbmuxd` — the latter is
/// reserved for protocol errors on an established connection.
async fn connect_usbmuxd() -> Result<UsbmuxdConnection, IosError> {
    UsbmuxdConnection::default()
        .await
        .map_err(|_| IosError::UsbmuxdUnavailable)
}

/// The lockdownd domains the device-home screen reads.
///
/// Values are flattened to strings the way `ideviceinfo` prints them, because
/// the Dart side already parses that shape (`int.tryParse`, `== 'true'`) and
/// that parsing is shared with the libimobiledevice backend.
pub struct IosDeviceDomains {
    /// The root domain: DeviceName, ProductVersion, BuildVersion, SerialNumber,
    /// CPUArchitecture, SIMStatus, TimeZone.
    pub root: HashMap<String, String>,
    /// `com.apple.mobile.battery`.
    pub battery: HashMap<String, String>,
    /// `com.apple.disk_usage`.
    pub disk_usage: HashMap<String, String>,
    /// `com.apple.international`.
    pub international: HashMap<String, String>,
}

/// Reads every domain the device-home screen needs, over **one** lockdown
/// session. The CLI path had to spawn `ideviceinfo` four times, each paying its
/// own process start, connect and TLS handshake.
pub async fn read_ios_device_domains(udid: String) -> Result<IosDeviceDomains, IosError> {
    let mut usbmuxd = connect_usbmuxd().await?;
    let device = usbmuxd.get_device(&udid).await?;
    let mut lockdown = open_session(&device).await?;

    Ok(IosDeviceDomains {
        root: domain(&mut lockdown, None).await?,
        battery: domain(&mut lockdown, Some("com.apple.mobile.battery")).await?,
        disk_usage: domain(&mut lockdown, Some("com.apple.disk_usage")).await?,
        international: domain(&mut lockdown, Some("com.apple.international")).await?,
    })
}

/// Reads one domain, flattened. A domain the device refuses is returned empty
/// rather than failing the read: which domains exist varies by iOS version, and
/// a missing battery reading should not blank out the identity card.
async fn domain(
    lockdown: &mut LockdownClient,
    domain: Option<&str>,
) -> Result<HashMap<String, String>, IosError> {
    match lockdown.get_value(None, domain).await {
        Ok(values) => Ok(flatten(&values)),
        Err(IdeviceError::GetProhibited) | Err(IdeviceError::UnknownErrorType(_)) => {
            Ok(HashMap::new())
        }
        Err(error) => Err(error.into()),
    }
}

/// Flattens a lockdownd dictionary into the text form `ideviceinfo` prints.
///
/// Scalars only — nothing above consumes the nested arrays and dictionaries,
/// and inventing a text form for them would be guessing at a format no caller
/// has agreed to.
fn flatten(values: &Value) -> HashMap<String, String> {
    let Some(dictionary) = values.as_dictionary() else {
        return HashMap::new();
    };

    dictionary
        .iter()
        .filter_map(|(key, value)| {
            let text = match value {
                Value::String(text) => text.clone(),
                Value::Integer(number) => number.to_string(),
                Value::Boolean(flag) => flag.to_string(),
                Value::Real(number) => number.to_string(),
                // Arrays, dictionaries, dates and blobs: nothing above
                // consumes them, and inventing a text form would be guessing.
                _ => return None,
            };
            Some((key.to_string(), text))
        })
        .collect()
}

/// Connects to lockdownd and authenticates with the stored pairing record.
async fn open_session(device: &UsbmuxdDevice) -> Result<LockdownClient, IosError> {
    let address = UsbmuxdAddr::from_env_var().unwrap_or_default();
    let provider = device.to_provider(address, CLIENT_LABEL);

    let mut lockdown = LockdownClient::connect(&provider).await?;
    lockdown
        .start_session(&provider.get_pairing_file().await?)
        .await?;
    Ok(lockdown)
}

/// Reads the lockdownd values for one device. Private, so flutter_rust_bridge
/// leaves it alone and `?` stays usable for the fallible half of the listing.
async fn describe(device: &UsbmuxdDevice) -> Result<IosDeviceSummary, IosError> {
    let mut lockdown = open_session(device).await?;

    // `None` key means the whole root domain in one round trip, which is all
    // discovery needs. Per-domain queries (battery, storage) come later.
    let values = lockdown.get_value(None, None).await?;

    Ok(IosDeviceSummary {
        udid: device.udid.clone(),
        status: "device".to_string(),
        name: string_value(&values, "DeviceName"),
        product_name: string_value(&values, "ProductName"),
        product_type: string_value(&values, "ProductType"),
        hardware_model: string_value(&values, "HardwareModel"),
        product_version: string_value(&values, "ProductVersion"),
        is_network: is_network(device),
    })
}

fn is_network(device: &UsbmuxdDevice) -> bool {
    matches!(device.connection_type, Connection::Network(_))
}

/// Reads one string out of a lockdownd domain dictionary. A missing key is
/// normal — domains vary by iOS version and lock state — so this never errors.
fn string_value(values: &Value, key: &str) -> Option<String> {
    values
        .as_dictionary()
        .and_then(|dictionary| dictionary.get(key))
        .and_then(Value::as_string)
        .map(str::to_string)
}

/// Cancellation tokens for the live syslog streams, keyed by a **caller-supplied
/// stream id**.
///
/// Not keyed by UDID, deliberately. Eagly opens one log stream per tab and
/// several tabs may watch the same device, so a UDID-keyed registry would let
/// closing one tab tear down another's stream.
///
/// A handle returned to Dart would be tidier, but flutter_rust_bridge turns any
/// function taking a `StreamSink` into a Dart `Stream` and discards its return
/// value — `Result<(), E>` is the only shape it supports here.
static SYSLOG_SESSIONS: LazyLock<Mutex<HashMap<String, CancellationToken>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Streams the device's syslog until [`stop_ios_syslog`] is called with the
/// same `session_id`, the device goes away, or Dart drops the stream.
///
/// Lines are emitted raw, exactly as `idevicesyslog` prints them, because the
/// Dart parser that turns them into log entries is stateful (multi-line
/// continuations, `\M-` meta-escapes) and is shared with the CLI backend.
///
/// Connecting happens before the stream starts, so a device that refuses the
/// service raises an error the caller can show — the CLI path could only infer
/// that from stderr after an empty stream.
pub async fn start_ios_syslog(
    sink: StreamSink<String>,
    udid: String,
    session_id: String,
) -> Result<(), IosError> {
    let mut usbmuxd = connect_usbmuxd().await?;
    let device = usbmuxd.get_device(&udid).await?;
    let address = UsbmuxdAddr::from_env_var().unwrap_or_default();
    let provider = device.to_provider(address, CLIENT_LABEL);

    let mut client = SyslogRelayClient::connect(&provider).await?;

    let token = CancellationToken::new();
    register_syslog_session(&session_id, token.clone());

    tokio::spawn(async move {
        loop {
            tokio::select! {
                // Biased so a pending stop wins over a line that arrived in
                // the same poll: closing a tab should not emit one more line.
                //
                // Cancelling here drops an in-flight `next()`, which is only
                // safe because we never poll the client again — we break out
                // and drop it. Do not restructure this into a loop that keeps
                // reading after a cancelled branch.
                biased;
                _ = token.cancelled() => break,
                line = client.next() => {
                    match line {
                        // `add` fails once Dart has dropped the stream, which is
                        // the other way this task legitimately ends.
                        Ok(line) => if sink.add(line).is_err() { break },
                        // Includes the device going away mid-stream; Dart sees
                        // end-of-stream, same as the CLI backend's EOF.
                        Err(_) => break,
                    }
                }
            }
        }
        // However the loop ended, the entry is dead — drop it so the registry
        // does not grow for the life of the process.
        forget_syslog_session(&session_id);
    });

    Ok(())
}

/// Stops the stream started under `session_id`. Idempotent, and a no-op for a
/// stream that already ended on its own.
pub async fn stop_ios_syslog(session_id: String) {
    let token = SYSLOG_SESSIONS
        .lock()
        .expect("syslog session registry poisoned")
        .remove(&session_id);

    if let Some(token) = token {
        token.cancel();
    }
}

fn register_syslog_session(session_id: &str, token: CancellationToken) {
    SYSLOG_SESSIONS
        .lock()
        .expect("syslog session registry poisoned")
        .insert(session_id.to_string(), token);
}

fn forget_syslog_session(session_id: &str) {
    SYSLOG_SESSIONS
        .lock()
        .expect("syslog session registry poisoned")
        .remove(session_id);
}

/// One user-installed app.
pub struct IosAppInfo {
    pub bundle_id: String,
    /// `CFBundleDisplayName`, falling back to `CFBundleName`.
    pub name: Option<String>,
    /// `CFBundleShortVersionString`.
    pub version: Option<String>,
}

/// Lists user-installed apps, in the order installation_proxy returns them.
///
/// Only user apps, matching what `ideviceinstaller` reports — so everything
/// returned is uninstallable. Ordering and capping are presentation concerns
/// and are applied above, identically for both backends.
pub async fn list_ios_apps(udid: String) -> Result<Vec<IosAppInfo>, IosError> {
    let mut client = installation_proxy(&udid).await?;

    // `Some("User")` is the filter `ideviceinstaller` applies by default.
    let apps = client.get_apps(Some("User"), None).await?;

    Ok(apps
        .into_iter()
        .map(|(bundle_id, value)| IosAppInfo {
            name: string_value(&value, "CFBundleDisplayName")
                .or_else(|| string_value(&value, "CFBundleName")),
            version: string_value(&value, "CFBundleShortVersionString"),
            bundle_id,
        })
        .collect())
}

/// Installs a `.ipa`.
///
/// `installation_proxy` also exposes a progress callback that the CLI has no
/// equivalent for; wiring it to a Dart stream is a UI change and is deliberately
/// not part of this port.
pub async fn install_ios_app(udid: String, package_path: String) -> Result<(), IosError> {
    let mut client = installation_proxy(&udid).await?;
    client.install(package_path, None).await?;
    Ok(())
}

pub async fn uninstall_ios_app(udid: String, bundle_id: String) -> Result<(), IosError> {
    let mut client = installation_proxy(&udid).await?;
    client.uninstall(bundle_id, None).await?;
    Ok(())
}

async fn installation_proxy(udid: &str) -> Result<InstallationProxyClient, IosError> {
    let mut usbmuxd = connect_usbmuxd().await?;
    let device = usbmuxd.get_device(udid).await?;
    let address = UsbmuxdAddr::from_env_var().unwrap_or_default();
    let provider = device.to_provider(address, CLIENT_LABEL);

    Ok(InstallationProxyClient::connect(&provider).await?)
}
