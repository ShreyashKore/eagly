//! Wireless iOS devices: finds iPhones that paired with us through the
//! pairable-host flow (`api::ios::start_ios_wireless_pairing`) when they show
//! up on the network, and keeps an encrypted tunnel open to each.
//!
//! The path is the one the rppairing spec walks through for
//! `_remotepairing._tcp`, and the crate's `pair_rsd_ios` tool follows:
//!
//! 1. Browse `_remotepairing._tcp`. A device's advertisement carries an
//!    `identifier` and an `authTag` derived from its altIRK, which pair-setup
//!    stored in that device's record — so the tag says which record (if any)
//!    the advertisement belongs to, without connecting.
//! 2. Pair-verify over an `RpPairingSocket` with the record's keys.
//! 3. Ask the device to `createListener`, connect to it, and run the TLS-PSK
//!    and CDTunnel handshakes with the pair-verify key.
//! 4. Run a userspace TCP stack over the tunnel and do the RSD handshake; the
//!    services eagly uses all have RSD (`*.shim.remote`) endpoints.
//!
//! Nothing here is exposed to Dart directly. `api::ios` lists the tunnels as
//! network devices and routes a service through one when usbmuxd does not
//! know the UDID.

use std::collections::{HashMap, HashSet};
use std::net::{IpAddr, SocketAddr, SocketAddrV6};
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::sync::{LazyLock, Mutex};
use std::task::{Context, Poll};
use std::time::{Duration, Instant};

use idevice::remote_pairing::{
    connect_tls_psk_tunnel_native, PeerDevice, RemotePairingClient, RpPairingFile, RpPairingSocket,
};
use idevice::rsd::RsdHandshake;
use idevice::tcp::adapter::Adapter;
use idevice::tcp::handle::AdapterHandle;
use mdns_sd::{ScopedIp, ServiceDaemon, ServiceEvent};
use plist::{Dictionary, Value};
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio::net::TcpStream;
use tokio_util::sync::{CancellationToken, DropGuard};

/// The service a paired device advertises on the network.
const REMOTE_PAIRING_SERVICE_TYPE: &str = "_remotepairing._tcp.local.";
/// Directory under the storage dir holding one pairing record per device.
pub(crate) const DEVICE_RECORDS_DIR: &str = "remote_pairing_devices";
/// Name sent with pair-verify. Only pair-setup shows it, which never runs here.
const SENDING_HOST: &str = "eagly";

/// How often advertisements are matched against records and dead tunnels
/// pruned. Connecting itself is not on this clock — a resolved advertisement
/// triggers an attempt immediately.
const TICK: Duration = Duration::from_secs(3);
/// Upper bound on one connection attempt, handshakes included.
const CONNECT_TIMEOUT: Duration = Duration::from_secs(20);
/// Per-address TCP connect timeout; an advertisement can list stale addresses.
const DIAL_TIMEOUT: Duration = Duration::from_secs(4);
/// Retry delay after a failed attempt, doubling up to [`MAX_BACKOFF`].
const MIN_BACKOFF: Duration = Duration::from_secs(5);
const MAX_BACKOFF: Duration = Duration::from_secs(60);

/// What a service needs to connect through a tunnel. Cheap to clone: the
/// adapter handle is a channel sender into the TCP stack's task.
#[derive(Clone)]
pub(crate) struct TunnelRoute {
    pub adapter: AdapterHandle,
    pub handshake: RsdHandshake,
}

struct Tunnel {
    route: TunnelRoute,
    /// UDID of the record the tunnel was opened with, which may differ from
    /// the device's own `UniqueDeviceID` the tunnel is keyed by.
    record_udid: String,
    /// Cancelled once the tunnel's transport is gone.
    dead: CancellationToken,
}

#[derive(Default)]
struct State {
    storage_dir: Option<PathBuf>,
    started: bool,
    /// Live tunnels, keyed by the device's `UniqueDeviceID`.
    tunnels: HashMap<String, Tunnel>,
    /// Record UDIDs with an attempt in flight.
    connecting: HashSet<String>,
    /// Record UDID → (earliest next attempt, current backoff).
    backoff: HashMap<String, (Instant, Duration)>,
}

static STATE: LazyLock<Mutex<State>> = LazyLock::new(|| Mutex::new(State::default()));

fn state() -> std::sync::MutexGuard<'static, State> {
    STATE.lock().expect("wireless state poisoned")
}

/// Starts watching for paired devices, reading records from `storage_dir`.
/// Idempotent; a later call only updates the directory.
pub(crate) fn start(storage_dir: String) -> Result<(), String> {
    let mut state = state();
    state.storage_dir = Some(PathBuf::from(storage_dir));
    if state.started {
        return Ok(());
    }

    let mdns = ServiceDaemon::new().map_err(|error| format!("mDNS daemon: {error}"))?;
    let events = mdns
        .browse(REMOTE_PAIRING_SERVICE_TYPE)
        .map_err(|error| format!("mDNS browse: {error}"))?;

    // mdns-sd's receiver is a sync channel here (its async API is not
    // compiled in), so a plain thread forwards events into the tokio world.
    let (sender, receiver) = tokio::sync::mpsc::unbounded_channel();
    std::thread::Builder::new()
        .name("eagly-ios-wireless-mdns".into())
        .spawn(move || {
            // Owns the daemon handle for the life of the process.
            let _mdns = mdns;
            while let Ok(event) = events.recv() {
                if sender.send(event).is_err() {
                    break;
                }
            }
        })
        .map_err(|error| format!("mDNS thread: {error}"))?;

    tokio::spawn(run(receiver));
    state.started = true;
    Ok(())
}

/// UDIDs of the devices with a live tunnel.
pub(crate) fn devices() -> Vec<String> {
    let mut state = state();
    prune(&mut state);
    state.tunnels.keys().cloned().collect()
}

/// The tunnel to `udid`, if one is up.
pub(crate) fn route(udid: &str) -> Option<TunnelRoute> {
    let mut state = state();
    prune(&mut state);
    state.tunnels.get(udid).map(|tunnel| tunnel.route.clone())
}

fn prune(state: &mut State) {
    state.tunnels.retain(|udid, tunnel| {
        let alive = !tunnel.dead.is_cancelled();
        if !alive {
            trace(format!("tunnel to {udid} closed"));
        }
        alive
    });
}

/// One line on stderr per connection event. `flutter run` shows the app's
/// stderr, which is where wireless problems are diagnosed — none of this
/// reaches the UI, where a phone simply does or does not appear.
fn trace(message: String) {
    eprintln!("[ios_wireless] {message}");
}

/// One resolved `_remotepairing._tcp` advertisement.
#[derive(Clone)]
struct Advertisement {
    identifier: String,
    auth_tag: String,
    addresses: Vec<SocketAddr>,
}

async fn run(mut events: tokio::sync::mpsc::UnboundedReceiver<ServiceEvent>) {
    let mut adverts: HashMap<String, Advertisement> = HashMap::new();
    // Devices drop out of mDNS and come back all the time; trace each once.
    let mut traced: HashSet<String> = HashSet::new();
    let mut tick = tokio::time::interval(TICK);

    loop {
        tokio::select! {
            event = events.recv() => match event {
                Some(ServiceEvent::ServiceResolved(service)) => {
                    let advert = Advertisement {
                        identifier: service
                            .get_property_val_str("identifier")
                            .unwrap_or_default()
                            .to_string(),
                        auth_tag: service
                            .get_property_val_str("authTag")
                            .unwrap_or_default()
                            .to_string(),
                        addresses: dial_order(service.addresses.iter(), service.port),
                    };
                    if traced.insert(service.fullname.clone()) {
                        trace(format!(
                            "found {} at {:?}",
                            service.fullname, advert.addresses
                        ));
                    }
                    adverts.insert(service.fullname.clone(), advert);
                }
                Some(ServiceEvent::ServiceRemoved(_, fullname)) => {
                    // Only stops new attempts; a live tunnel is judged by its
                    // own transport, since a device may stop advertising while
                    // the tunnel is still fine.
                    adverts.remove(&fullname);
                }
                Some(_) => continue,
                None => return,
            },
            _ = tick.tick() => {}
        }

        connect_matching(&adverts);
    }
}

/// Starts an attempt for every advertisement that belongs to a record and has
/// no tunnel, attempt or backoff in the way.
fn connect_matching(adverts: &HashMap<String, Advertisement>) {
    let mut state = state();
    prune(&mut state);
    let Some(storage_dir) = state.storage_dir.clone() else {
        return;
    };
    let records = load_records(&storage_dir);
    let now = Instant::now();

    for advert in adverts.values() {
        let Some(record) = record_for(&records, advert) else {
            continue;
        };

        let tunnelled = state
            .tunnels
            .values()
            .any(|tunnel| tunnel.record_udid == record.udid);
        let waiting = state
            .backoff
            .get(&record.udid)
            .is_some_and(|(next, _)| now < *next);
        if tunnelled || waiting || state.connecting.contains(&record.udid) {
            continue;
        }

        state.connecting.insert(record.udid.clone());
        trace(format!(
            "connecting to {} ({})",
            record.udid, advert.identifier
        ));
        tokio::spawn(attempt(record.clone(), advert.clone()));
    }
}

/// The record whose device sent `advert`: its `authTag` is keyed by that
/// device's altIRK, so only the right record reproduces it.
fn record_for<'a>(records: &'a [DeviceRecord], advert: &Advertisement) -> Option<&'a DeviceRecord> {
    records.iter().find(|record| {
        PeerDevice::validate_auth_tag(&record.alt_irk, &advert.identifier, &advert.auth_tag)
    })
}

async fn attempt(record: DeviceRecord, advert: Advertisement) {
    let result = tokio::time::timeout(CONNECT_TIMEOUT, open_tunnel(&record, &advert))
        .await
        .unwrap_or_else(|_| Err("timed out".to_string()));

    let mut state = state();
    state.connecting.remove(&record.udid);
    match result {
        Ok((udid, tunnel)) => {
            trace(format!("tunnel up to {udid}"));
            state.backoff.remove(&record.udid);
            state.tunnels.insert(udid, tunnel);
        }
        Err(error) => {
            let delay = state
                .backoff
                .get(&record.udid)
                .map_or(MIN_BACKOFF, |(_, previous)| {
                    (*previous * 2).min(MAX_BACKOFF)
                });
            trace(format!(
                "connecting to {} failed, retrying in {}s: {error}",
                record.udid,
                delay.as_secs()
            ));
            state
                .backoff
                .insert(record.udid.clone(), (Instant::now() + delay, delay));
        }
    }
}

/// Pair-verify, tunnel, TCP stack, RSD — see the module docs.
async fn open_tunnel(
    record: &DeviceRecord,
    advert: &Advertisement,
) -> Result<(String, Tunnel), String> {
    let (control, address) = dial(&advert.addresses).await?;

    let mut pairing_file = record.pairing_file.clone();
    let mut client = RemotePairingClient::new(RpPairingSocket::new(control), SENDING_HOST);
    client
        .attempt_pair_verify()
        .await
        .map_err(|error| format!("handshake: {error}"))?;
    client
        .validate_pairing(&mut pairing_file)
        .await
        .map_err(|error| format!("pair-verify: {error}"))?;
    let tunnel_port = client
        .create_tcp_listener()
        .await
        .map_err(|error| format!("createListener: {error}"))?;

    let mut tunnel_address = address;
    tunnel_address.set_port(tunnel_port);
    let (tunnel_stream, _) = dial(&[tunnel_address]).await?;
    let tunnel = connect_tls_psk_tunnel_native(tunnel_stream, client.encryption_key())
        .await
        .map_err(|error| format!("tunnel: {error}"))?;

    let client_ip: IpAddr = tunnel
        .info
        .client_address
        .parse()
        .map_err(|error| format!("tunnel client address: {error}"))?;
    let server_ip: IpAddr = tunnel
        .info
        .server_address
        .parse()
        .map_err(|error| format!("tunnel server address: {error}"))?;
    let rsd_port = tunnel.info.server_rsd_port;
    let mtu = tunnel.info.mtu as usize;

    // The guard rides inside the stream the TCP stack owns. The stack's task
    // drops the stream when the transport fails, which cancels `dead`.
    let dead = CancellationToken::new();
    let watched = Watched {
        inner: tunnel.into_inner(),
        _guard: dead.clone().drop_guard(),
    };
    let mut adapter = Adapter::new(Box::new(watched), client_ip, server_ip);
    // Room for the IPv6 + TCP headers inside the tunnel MTU, as
    // `CoreDeviceProxy::create_software_tunnel` does.
    adapter.set_mss(mtu.saturating_sub(60));
    let mut handle = adapter.to_async_handle();

    let rsd_stream = handle
        .connect(rsd_port)
        .await
        .map_err(|error| format!("RSD connect: {error}"))?;
    let handshake = RsdHandshake::new(rsd_stream)
        .await
        .map_err(|error| format!("RSD handshake: {error}"))?;

    // Key by the device's own UDID so a device that is also on USB matches
    // its usbmuxd entry; the record's is what pair-setup was told.
    let udid = handshake
        .properties
        .get("UniqueDeviceID")
        .and_then(Value::as_string)
        .map(str::to_string)
        .unwrap_or_else(|| record.udid.clone());

    // The control connection is held for the tunnel's lifetime — the device
    // owns the listener it created on our behalf through it.
    let watch = dead.clone();
    let mut keep_handle = handle.clone();
    tokio::spawn(async move {
        watch.cancelled().await;
        drop(client);
        let _ = keep_handle.close().await;
    });

    Ok((
        udid,
        Tunnel {
            route: TunnelRoute {
                adapter: handle,
                handshake,
            },
            record_udid: record.udid.clone(),
            dead,
        },
    ))
}

/// Connects to the first address that answers, with keepalive on so a device
/// that drops off Wi-Fi without a FIN is noticed in seconds, not hours.
async fn dial(addresses: &[SocketAddr]) -> Result<(TcpStream, SocketAddr), String> {
    let mut last_error = "no addresses advertised".to_string();
    for address in addresses {
        match tokio::time::timeout(DIAL_TIMEOUT, TcpStream::connect(address)).await {
            Ok(Ok(stream)) => {
                set_keepalive(&stream);
                return Ok((stream, *address));
            }
            Ok(Err(error)) => last_error = format!("{address}: {error}"),
            Err(_) => last_error = format!("{address}: timed out"),
        }
    }
    Err(last_error)
}

fn set_keepalive(stream: &TcpStream) {
    let keepalive = socket2::TcpKeepalive::new().with_time(Duration::from_secs(10));
    #[cfg(any(target_os = "macos", target_os = "linux", target_os = "windows"))]
    let keepalive = keepalive.with_interval(Duration::from_secs(3));
    #[cfg(any(target_os = "macos", target_os = "linux"))]
    let keepalive = keepalive.with_retries(3);
    let _ = socket2::SockRef::from(stream).set_tcp_keepalive(&keepalive);
}

/// IPv4 first, then routable IPv6, then link-local IPv6 with its interface —
/// the order least likely to need a scope id to work.
fn dial_order<'a>(addresses: impl Iterator<Item = &'a ScopedIp>, port: u16) -> Vec<SocketAddr> {
    let mut ordered: Vec<(u8, SocketAddr)> = addresses
        .filter_map(|address| match address {
            ScopedIp::V4(v4) => Some((0, SocketAddr::new(IpAddr::V4(*v4.addr()), port))),
            ScopedIp::V6(v6) if v6.addr().is_unicast_link_local() => Some((
                2,
                SocketAddr::V6(SocketAddrV6::new(*v6.addr(), port, 0, v6.scope_id().index)),
            )),
            ScopedIp::V6(v6) => Some((1, SocketAddr::new(IpAddr::V6(*v6.addr()), port))),
            _ => None,
        })
        .collect();
    ordered.sort_by_key(|(rank, _)| *rank);
    ordered.into_iter().map(|(_, address)| address).collect()
}

/// A stream that cancels a token when dropped — how the tunnel reports that
/// the TCP stack gave up on it.
#[derive(Debug)]
struct Watched<S> {
    inner: S,
    _guard: DropGuard,
}

impl<S: AsyncRead + Unpin> AsyncRead for Watched<S> {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.inner).poll_read(cx, buf)
    }
}

impl<S: AsyncWrite + Unpin> AsyncWrite for Watched<S> {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<std::io::Result<usize>> {
        Pin::new(&mut self.inner).poll_write(cx, buf)
    }

    fn poll_flush(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.inner).poll_flush(cx)
    }

    fn poll_shutdown(mut self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<std::io::Result<()>> {
        Pin::new(&mut self.inner).poll_shutdown(cx)
    }
}

// ── Device records ───────────────────────────────────────────────────────

/// One paired device, as pair-setup left it.
#[derive(Clone)]
struct DeviceRecord {
    udid: String,
    alt_irk: Vec<u8>,
    /// Our keys and identifier, plus the device's altIRK.
    pairing_file: RpPairingFile,
}

/// Writes the pairing record for one device to
/// `remote_pairing_devices/<udid>.plist`: the crate's pairing-file plist —
/// this host's keys plus that device's altIRK, which pair-setup leaves in
/// `pairing_file` — with the device's UDID, name and model added so the file
/// says which device it is.
///
/// One file per device because the host identity is shared across devices
/// while the altIRK is not: a single record would be overwritten by the next
/// pairing, losing the previous device's.
pub(crate) fn persist_device_record(
    storage_dir: &str,
    peer: &PeerDevice,
    pairing_file: &RpPairingFile,
) {
    // The UDID comes off the wire; keep it from naming a path elsewhere.
    let file_stem = file_stem(&peer.remotepairing_udid);
    if file_stem.is_empty() {
        return;
    }
    let Ok(mut record) = plist::from_bytes::<Dictionary>(&pairing_file.to_bytes()) else {
        return;
    };
    record.insert(
        "udid".into(),
        Value::String(peer.remotepairing_udid.clone()),
    );
    record.insert("name".into(), Value::String(peer.name.clone()));
    record.insert("model".into(), Value::String(peer.model.clone()));

    let dir = Path::new(storage_dir).join(DEVICE_RECORDS_DIR);
    let _ = std::fs::create_dir_all(&dir);
    let _ = Value::Dictionary(record).to_file_xml(dir.join(format!("{file_stem}.plist")));
}

fn file_stem(udid: &str) -> String {
    udid.chars()
        .filter(|c| c.is_ascii_alphanumeric() || *c == '-' || *c == '_')
        .collect()
}

/// Every readable record with an altIRK. Records are small and few, so they
/// are re-read on each tick rather than cached: a pairing that just finished
/// is picked up without anyone having to say so.
fn load_records(storage_dir: &Path) -> Vec<DeviceRecord> {
    let Ok(entries) = std::fs::read_dir(storage_dir.join(DEVICE_RECORDS_DIR)) else {
        return Vec::new();
    };

    entries
        .flatten()
        .filter(|entry| entry.path().extension().is_some_and(|ext| ext == "plist"))
        .filter_map(|entry| {
            let path = entry.path();
            let bytes = std::fs::read(&path).ok()?;
            let pairing_file = RpPairingFile::from_bytes(&bytes).ok()?;
            let alt_irk = pairing_file.alt_irk.clone()?;
            let extra = plist::from_bytes::<Dictionary>(&bytes).ok()?;
            let text = |key: &str| {
                extra
                    .get(key)
                    .and_then(Value::as_string)
                    .map(str::to_string)
            };
            Some(DeviceRecord {
                // Records written before the UDID was stored inside them are
                // named after it.
                udid: text("udid").or_else(|| {
                    path.file_stem()
                        .and_then(|stem| stem.to_str())
                        .map(str::to_string)
                })?,
                alt_irk,
                pairing_file,
            })
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use idevice::remote_pairing::PairableHostInfo;

    fn temp_storage(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("eagly-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn peer(udid: &str, alt_irk: [u8; 16]) -> PeerDevice {
        PeerDevice {
            account_id: "account".into(),
            alt_irk: alt_irk.to_vec(),
            model: "iPhone17,1".into(),
            name: "QA iPhone".into(),
            remotepairing_udid: udid.into(),
        }
    }

    /// What pair-setup leaves behind: our keys plus the device's altIRK.
    fn paired_file(device_irk: [u8; 16]) -> RpPairingFile {
        let mut file = RpPairingFile::generate("eagly-test-host");
        file.alt_irk = Some(device_irk.to_vec());
        file
    }

    /// An advertisement as a device keyed by `alt_irk` would publish it. The
    /// crate's pairable-host TXT builder derives `authTag` the same way.
    fn advert_from(alt_irk: [u8; 16], identifier: &str) -> Advertisement {
        let info = PairableHostInfo {
            alt_irk,
            ..Default::default()
        };
        let auth_tag = info
            .mdns_txt_records(identifier)
            .into_iter()
            .find(|(key, _)| key == "authTag")
            .map(|(_, value)| value)
            .unwrap();
        Advertisement {
            identifier: identifier.into(),
            auth_tag,
            addresses: Vec::new(),
        }
    }

    #[test]
    fn records_round_trip_with_keys_and_altirk() {
        let storage = temp_storage("records");
        let file = paired_file([7; 16]);
        persist_device_record(
            storage.to_str().unwrap(),
            &peer("00008110-001A2B3C00000000", [7; 16]),
            &file,
        );

        let records = load_records(&storage);
        assert_eq!(records.len(), 1);
        let record = &records[0];
        assert_eq!(record.udid, "00008110-001A2B3C00000000");
        assert_eq!(record.alt_irk, vec![7; 16]);
        assert_eq!(record.pairing_file.identifier, file.identifier);
        assert_eq!(
            record.pairing_file.private_key_bytes(),
            file.private_key_bytes()
        );

        let _ = std::fs::remove_dir_all(&storage);
    }

    #[test]
    fn each_device_keeps_its_own_record() {
        let storage = temp_storage("two-devices");
        let dir = storage.to_str().unwrap();
        persist_device_record(dir, &peer("first", [1; 16]), &paired_file([1; 16]));
        persist_device_record(dir, &peer("second", [2; 16]), &paired_file([2; 16]));

        let mut udids: Vec<String> = load_records(&storage)
            .into_iter()
            .map(|record| record.udid)
            .collect();
        udids.sort();
        assert_eq!(udids, ["first", "second"]);

        let _ = std::fs::remove_dir_all(&storage);
    }

    #[test]
    fn advertisement_matches_only_its_devices_record() {
        let storage = temp_storage("matching");
        let dir = storage.to_str().unwrap();
        persist_device_record(dir, &peer("first", [1; 16]), &paired_file([1; 16]));
        persist_device_record(dir, &peer("second", [2; 16]), &paired_file([2; 16]));
        let records = load_records(&storage);

        let advert = advert_from([2; 16], "2BE6E510-0325-4365-923E-B14C6F57DB3A");
        assert_eq!(
            record_for(&records, &advert).map(|record| record.udid.as_str()),
            Some("second")
        );

        let stranger = advert_from([9; 16], "2BE6E510-0325-4365-923E-B14C6F57DB3A");
        assert!(record_for(&records, &stranger).is_none());

        let _ = std::fs::remove_dir_all(&storage);
    }

    /// Starting discovery spawns the mDNS thread and the manager task; it has
    /// to work from inside the runtime flutter_rust_bridge calls us on, keep
    /// running, and list nothing while no paired device is around.
    #[tokio::test(flavor = "multi_thread")]
    async fn discovery_starts_once_and_lists_nothing_without_devices() {
        let storage = temp_storage("discovery");
        let dir = storage.to_str().unwrap().to_string();
        start(dir.clone()).unwrap();
        start(dir).unwrap();

        tokio::time::sleep(TICK + Duration::from_millis(500)).await;
        assert!(devices().is_empty());
        assert!(route("00008110-001A2B3C00000000").is_none());

        let _ = std::fs::remove_dir_all(&storage);
    }

    #[test]
    fn record_names_cannot_escape_the_records_dir() {
        assert_eq!(file_stem("../../etc/passwd"), "etcpasswd");
        assert_eq!(file_stem("00008110-001A2B3C_x"), "00008110-001A2B3C_x");
    }
}
