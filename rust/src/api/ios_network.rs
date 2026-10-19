//! TCP ports on an iOS device, reached through usbmuxd: how the Network pane
//! finds and talks to an app serving its traffic with Inspektor.
//!
//! Inspektor listens on a `127.0.0.1` port on the phone, the first free one
//! from 38470 (docs/NETWORK_INSPECTOR.md §4.2). iOS has no route from the
//! device to the host, so Eagly connects in over the USB mux, as `iproxy`
//! does.

use std::collections::HashMap;
use std::net::Ipv4Addr;
use std::sync::{LazyLock, Mutex};
use std::time::Duration;

use idevice::usbmuxd::errors::UsbmuxdError;
use idevice::usbmuxd::UsbmuxdAddr;
use idevice::{IdeviceError, ReadWrite};
use tokio::net::{TcpListener, TcpStream};
use tokio::task::JoinSet;
use tokio_util::sync::CancellationToken;

use super::ios::{connect_usbmuxd, IosError, CLIENT_LABEL};

/// How long one probe may take. A closed port is refused at once; this only
/// bounds a device that stops answering halfway.
const PROBE_TIMEOUT: Duration = Duration::from_secs(3);

/// Which of `ports` accept a connection on the device right now, in
/// ascending order.
///
/// Every probe is a usbmuxd `Connect`, and `connect_to_device` consumes its
/// daemon connection, so each one opens its own; they run in parallel. A
/// probe that connects hangs up at once, so whatever listens there sees a
/// connection that closes without a word.
pub async fn probe_ios_ports(udid: String, ports: Vec<u16>) -> Result<Vec<u16>, IosError> {
    let device_id = connect_usbmuxd().await?.get_device(&udid).await?.device_id;

    let mut probes = JoinSet::new();
    for port in ports {
        probes.spawn(async move {
            let outcome = tokio::time::timeout(PROBE_TIMEOUT, connect(device_id, port)).await;
            (port, outcome)
        });
    }

    let mut open = Vec::new();
    while let Some(joined) = probes.join_next().await {
        let Ok((port, outcome)) = joined else {
            continue;
        };
        match outcome {
            Ok(Ok(_)) => open.push(port),
            Ok(Err(IdeviceError::Usbmuxd(UsbmuxdError::ConnectionRefused))) | Err(_) => {}
            Ok(Err(IdeviceError::Usbmuxd(UsbmuxdError::BadDevice))) => {
                return Err(IosError::DeviceNotFound(udid));
            }
            Ok(Err(error)) => return Err(error.into()),
        }
    }
    open.sort_unstable();
    Ok(open)
}

/// Running forwards by host port, each stopped through its token.
static PORT_FORWARDS: LazyLock<Mutex<HashMap<u16, CancellationToken>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

/// Listens on a free `127.0.0.1` port and pipes every connection made to it
/// through usbmuxd to `device_port` on the device. Returns that host port; the
/// forward runs until [`stop_ios_port_forward`] is called with it.
///
/// The device is looked up again for each connection, because usbmuxd gives a
/// phone a new id every time it is plugged in. A connection the device
/// refuses is closed at once, which the client sees as the app being gone.
pub async fn start_ios_port_forward(udid: String, device_port: u16) -> Result<u16, IosError> {
    let listener = TcpListener::bind((Ipv4Addr::LOCALHOST, 0))
        .await
        .map_err(|error| IosError::Other(error.to_string()))?;
    let host_port = listener
        .local_addr()
        .map_err(|error| IosError::Other(error.to_string()))?
        .port();

    let token = CancellationToken::new();
    PORT_FORWARDS
        .lock()
        .expect("port forward registry poisoned")
        .insert(host_port, token.clone());

    tokio::spawn(async move {
        loop {
            let accepted = tokio::select! {
                _ = token.cancelled() => break,
                accepted = listener.accept() => accepted,
            };
            match accepted {
                Ok((client, _)) => {
                    tokio::spawn(pipe(client, udid.clone(), device_port, token.child_token()));
                }
                // Per-connection failures, or the process out of descriptors:
                // wait a moment rather than spin.
                Err(_) => tokio::time::sleep(Duration::from_millis(100)).await,
            }
        }
    });
    Ok(host_port)
}

/// Stops the forward on `host_port` and closes every connection through it.
pub async fn stop_ios_port_forward(host_port: u16) {
    let token = PORT_FORWARDS
        .lock()
        .expect("port forward registry poisoned")
        .remove(&host_port);
    if let Some(token) = token {
        token.cancel();
    }
}

/// Pipes one accepted client to `device_port` until either side closes or
/// the forward stops.
async fn pipe(mut client: TcpStream, udid: String, device_port: u16, token: CancellationToken) {
    let connected = async {
        let device_id = connect_usbmuxd().await?.get_device(&udid).await?.device_id;
        Ok::<_, IosError>(connect(device_id, device_port).await?)
    };
    let mut device = tokio::select! {
        _ = token.cancelled() => return,
        connected = connected => match connected {
            Ok(device) => device,
            Err(_) => return,
        },
    };
    let _ = client.set_nodelay(true);
    tokio::select! {
        _ = token.cancelled() => {}
        _ = tokio::io::copy_bidirectional(&mut client, &mut device) => {}
    }
}

/// A stream to `port` on the device usbmuxd knows as `device_id`.
async fn connect(device_id: u32, port: u16) -> Result<Box<dyn ReadWrite>, IdeviceError> {
    let usbmuxd = UsbmuxdAddr::from_env_var()
        .unwrap_or_default()
        .connect(0)
        .await?;
    usbmuxd
        .connect_to_device(device_id, port, CLIENT_LABEL)
        .await?
        .get_socket()
        .ok_or(IdeviceError::NoEstablishedConnection)
}
