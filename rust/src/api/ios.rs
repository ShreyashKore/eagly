//! iOS device discovery, backed by the `idevice` crate talking to usbmuxd
//! directly. Replaces shelling out to `idevice_id -l` + `ideviceinfo -u <udid>`.

use chrono::{Local, TimeZone};
use idevice::provider::IdeviceProvider;
use idevice::provider::UsbmuxdProvider;
use idevice::services::afc::opcode::AfcFopenMode;
use idevice::services::afc::AfcClient;
use idevice::services::crashreportcopymobile::CrashReportCopyMobileClient;
use idevice::services::installation_proxy::InstallationProxyClient;
use idevice::services::lockdown::LockdownClient;
use idevice::services::os_trace_relay::{LogLevel, OsTraceLog, OsTraceRelayClient};
use idevice::usbmuxd::{Connection, UsbmuxdAddr, UsbmuxdConnection, UsbmuxdDevice};
use idevice::{IdeviceError, IdeviceService};
use plist::Value;
use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio_util::sync::CancellationToken;

use crate::frb_generated::StreamSink;

/// Label lockdownd records against our session. Shows up in the device's
/// pairing records, so it should name the app rather than the library.
pub(crate) const CLIENT_LABEL: &str = "eagly";

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
pub(crate) async fn connect_usbmuxd() -> Result<UsbmuxdConnection, IosError> {
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

/// Streams the device's logs until [`stop_ios_syslog`] is called with the
/// same `session_id`, the device goes away, or Dart drops the stream.
///
/// Backed by `os_trace_relay` (`OsTraceRelayClient`), the same service
/// `idevicesyslog` reads: unlike the legacy `syslog_relay` it carries Info and
/// Debug messages, sub-second timestamps, and a clean process name instead of
/// the device hostname. Each record is formatted into the text line the shared
/// [`IosSyslogParser`] expects (see [`format_os_trace_log`]) and emitted as one
/// string; a whole message may span lines, and Dart splits records with
/// `parseLogRecords` rather than the CLI's line-by-line `parseLogLines`.
///
/// Connecting happens before the stream starts, so a device that refuses the
/// service raises an error the caller can show — the CLI path could only infer
/// that from stderr after an empty stream.
pub async fn start_ios_syslog(
    sink: StreamSink<String>,
    udid: String,
    session_id: String,
) -> Result<(), IosError> {
    // Claimed before connecting, which takes a while: a stop that lands in the
    // meantime has to find a token to cancel rather than a missing entry.
    let token = claim_syslog_session(&session_id);
    let connected = async {
        let provider = provider_for(&udid).await?;
        Ok::<_, IosError>(
            OsTraceRelayClient::connect(&provider)
                .await?
                .start_trace(None)
                .await?,
        )
    }
    .await;
    let mut receiver = match connected {
        Ok(receiver) => receiver,
        Err(error) => {
            forget_syslog_session(&session_id);
            return Err(error);
        }
    };
    if token.is_cancelled() {
        forget_syslog_session(&session_id);
        return Ok(());
    }

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
                log = receiver.next() => {
                    match log {
                        // `add` fails once Dart has dropped the stream, which is
                        // the other way this task legitimately ends.
                        Ok(log) => if sink.add(format_os_trace_log(&log)).is_err() { break },
                        // One record the crate can't decode (an unmapped level
                        // byte, say) is reported only after its whole packet is
                        // read, so the next one is still in frame: skip it
                        // rather than end the user's stream over it.
                        Err(error) if is_skippable_record_error(&error) => continue,
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

/// Renders one `os_trace_relay` record into the text line [`IosSyslogParser`]
/// parses, byte-for-byte what `idevicesyslog` prints:
///
/// ```text
/// <Mon> <DD> <HH:MM:SS>.<microseconds> <process>(<image>)[<pid>] <Level>: <message>
/// ```
///
/// `<process>` is the basename of the emitting process's main executable and
/// `<image>` the basename of the image that held the call site; the image is
/// dropped when it equals the process, exactly as `idevicesyslog` does. The
/// message may contain newlines — `parseLogRecords` on the Dart side splits
/// them into the same entry's continuation lines.
fn format_os_trace_log(log: &OsTraceLog) -> String {
    // The crate builds `timestamp` with `DateTime::from_timestamp(seconds,
    // microseconds).naive_local()`. That is a `DateTime<Utc>`, so the naive
    // value is the UTC wall clock; `idevicesyslog` prints host-local time, and
    // so must we — the Dart parser reads the text as local.
    let local = Local.from_utc_datetime(&log.timestamp);
    // It also passes microseconds where nanoseconds belong, so the sub-second
    // field holds the raw microsecond count: read it back as microseconds.
    // Pinned to idevice =0.1.65; recheck both quirks when bumping it.
    let micros = log.timestamp.and_utc().timestamp_subsec_nanos();

    let process = basename(&log.filename);
    let image = basename(&log.image_name);
    let label = if image.is_empty() || image == process {
        process.to_string()
    } else {
        format!("{process}({image})")
    };

    let level = match log.level {
        LogLevel::Notice => "Notice",
        LogLevel::Info => "Info",
        LogLevel::Debug => "Debug",
        LogLevel::Error => "Error",
        LogLevel::Fault => "Fault",
    };

    format!(
        "{}.{micros:06} {label}[{}] <{level}>: {}",
        local.format("%b %e %H:%M:%S"),
        log.pid,
        log.message,
    )
}

/// Whether `OsTraceRelayReceiver::next` failed on one record's contents rather
/// than on the connection. In idevice 0.1.65 every decode failure is an
/// `UnexpectedResponse` raised after the packet has been read in full — except
/// a missing `0x02` lead byte, which means the stream is out of frame and
/// every later read would be garbage. I/O errors, EOF included, are never
/// skippable.
fn is_skippable_record_error(error: &IdeviceError) -> bool {
    matches!(
        error,
        IdeviceError::UnexpectedResponse(detail) if !detail.contains("leading byte")
    )
}

/// The final path component, for the `/usr/libexec/cloudd`-style paths the
/// relay reports. A name without a slash is returned unchanged.
fn basename(path: &str) -> &str {
    path.rsplit('/').next().unwrap_or(path)
}

/// Stops the stream started under `session_id`. Idempotent.
///
/// Bridge calls run concurrently, so this can overtake the
/// [`start_ios_syslog`] it follows. With nothing registered yet it leaves a
/// cancelled token behind for that start to claim and give up on — which is
/// also why Dart only calls this for a stream that has not already ended: a
/// stop with no start to follow would leave that token behind for good.
pub async fn stop_ios_syslog(session_id: String) {
    SYSLOG_SESSIONS
        .lock()
        .expect("syslog session registry poisoned")
        .entry(session_id)
        .or_default()
        .cancel();
}

/// The token for `session_id`: a fresh one, or the cancelled one a stop that
/// arrived first left behind.
fn claim_syslog_session(session_id: &str) -> CancellationToken {
    SYSLOG_SESSIONS
        .lock()
        .expect("syslog session registry poisoned")
        .entry(session_id.to_string())
        .or_default()
        .clone()
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
///
/// Uses `Browse`, as `ideviceinstaller` does, rather than the client's
/// `get_apps` (`Lookup`): that returns a `HashMap`, whose iteration order is
/// randomized per process, and the device-home card takes the first few.
pub async fn list_ios_apps(udid: String) -> Result<Vec<IosAppInfo>, IosError> {
    let mut client = installation_proxy(&udid).await?;

    const ATTRIBUTES: [&str; 4] = [
        "CFBundleIdentifier",
        "CFBundleDisplayName",
        "CFBundleName",
        "CFBundleShortVersionString",
    ];
    let mut options = plist::Dictionary::new();
    // "User" is the filter `ideviceinstaller` applies by default.
    options.insert("ApplicationType".into(), "User".into());
    options.insert(
        "ReturnAttributes".into(),
        Value::Array(ATTRIBUTES.iter().map(|&key| key.into()).collect()),
    );
    let apps = client.browse(Some(Value::Dictionary(options))).await?;

    Ok(apps
        .iter()
        .filter_map(|value| {
            Some(IosAppInfo {
                bundle_id: string_value(value, "CFBundleIdentifier")?,
                name: string_value(value, "CFBundleDisplayName")
                    .or_else(|| string_value(value, "CFBundleName")),
                version: string_value(value, "CFBundleShortVersionString"),
            })
        })
        .collect())
}

/// Installs a `.ipa` from a **host** path.
///
/// InstallationProxy's `Install` takes a path inside the device's own AFC jail,
/// not a host path — handing it one fails with `MissingPackagePath`. So the
/// package has to be uploaded to `PublicStaging` over AFC first and the staged
/// path passed instead, which is what `ideviceinstaller` does too and what
/// `utils::installation` wraps.
///
/// It also exposes a progress callback the CLI has no equivalent for; wiring it
/// to a Dart stream is a UI change and is deliberately not part of this port.
pub async fn install_ios_app(udid: String, package_path: String) -> Result<(), IosError> {
    let provider = provider_for(&udid).await?;
    idevice::utils::installation::install_package(&provider, &package_path, None).await?;
    Ok(())
}

/// Takes a bundle identifier, so unlike install it needs no staging.
pub async fn uninstall_ios_app(udid: String, bundle_id: String) -> Result<(), IosError> {
    let provider = provider_for(&udid).await?;
    let mut client = InstallationProxyClient::connect(&provider).await?;
    client.uninstall(bundle_id, None).await?;
    Ok(())
}

async fn installation_proxy(udid: &str) -> Result<InstallationProxyClient, IosError> {
    let provider = provider_for(udid).await?;
    Ok(InstallationProxyClient::connect(&provider).await?)
}

/// Copies crash reports off the device into `output_dir`, returning the paths
/// written.
///
/// Mirrors `idevicecrashreport -k -e <dir>`: reports are left on the device and
/// written out as files, because the crash-report viewer re-reads them from
/// disk. Walks subdirectories (devices keep a `Retired/` folder) and takes only
/// `.ips`/`.crash`, matching what the CLI backend collects.
pub async fn pull_ios_crash_reports(
    udid: String,
    output_dir: String,
) -> Result<Vec<String>, IosError> {
    let provider = provider_for(&udid).await?;

    // The service is an AFC endpoint rooted at the crash report directory.
    let mut afc = CrashReportCopyMobileClient::connect(&provider)
        .await?
        .to_afc_client();

    let mut written = Vec::new();
    let mut pending = vec![".".to_string()];

    while let Some(directory) = pending.pop() {
        // A directory we cannot read (permissions, a race with the device
        // reaping reports) should not fail the whole pull.
        let Ok(entries) = afc.list_dir(directory.clone()).await else {
            continue;
        };

        for entry in entries {
            if entry == "." || entry == ".." {
                continue;
            }
            let path = if directory == "." {
                entry.clone()
            } else {
                format!("{directory}/{entry}")
            };

            let Ok(info) = afc.get_file_info(path.clone()).await else {
                continue;
            };

            if info.st_ifmt == "S_IFDIR" {
                pending.push(path);
                continue;
            }
            if !is_crash_report(&entry) {
                continue;
            }

            let Ok(bytes) = read_afc_file(&mut afc, &path).await else {
                continue;
            };

            // Flatten into output_dir: the viewer keys reports by file name, and
            // the CLI backend's recursive collect ignored directory structure too.
            let destination = format!("{output_dir}/{entry}");
            if tokio::fs::write(&destination, bytes).await.is_ok() {
                written.push(destination);
            }
        }
    }

    Ok(written)
}

fn is_crash_report(name: &str) -> bool {
    let lower = name.to_lowercase();
    lower.ends_with(".ips") || lower.ends_with(".crash")
}

async fn read_afc_file(afc: &mut AfcClient, path: &str) -> Result<Vec<u8>, IdeviceError> {
    let mut descriptor = afc.open(path, AfcFopenMode::RdOnly).await?;
    let bytes = descriptor.read_entire().await?;
    descriptor.close().await?;
    Ok(bytes)
}

/// One entry in an AFC directory listing.
pub struct IosFileEntry {
    pub name: String,
    /// `"S_IFDIR"`, `"S_IFREG"`, `"S_IFLNK"`, … straight from AFC, mapped to
    /// the shared entry type in Dart.
    pub kind: String,
    pub size_bytes: u64,
    /// Milliseconds since the epoch, or `None` when AFC reports no timestamp.
    pub modified_ms: Option<i64>,
    pub link_target: Option<String>,
}

/// Lists an AFC directory, with attributes.
///
/// One `get_file_info` per entry, as AFC has no batched stat — but over a
/// single connection, where the CLI backend had to drive an interactive REPL
/// and re-associate output with commands by splitting on the prompt.
pub async fn list_ios_files(udid: String, path: String) -> Result<Vec<IosFileEntry>, IosError> {
    let mut afc = afc_client(&udid).await?;
    let names = afc.list_dir(path.clone()).await?;

    let mut entries = Vec::new();
    for name in names {
        if name == "." || name == ".." {
            continue;
        }

        let full = join_afc_path(&path, &name);
        // An entry that vanishes between listing and stat is skipped rather
        // than failing the whole listing.
        let Ok(info) = afc.get_file_info(full).await else {
            continue;
        };

        entries.push(IosFileEntry {
            name,
            kind: info.st_ifmt.clone(),
            size_bytes: info.size as u64,
            modified_ms: Some(info.modified.and_utc().timestamp_millis()),
            link_target: info.st_link_target.clone(),
        });
    }

    Ok(entries)
}

pub async fn create_ios_directory(udid: String, path: String) -> Result<(), IosError> {
    let mut afc = afc_client(&udid).await?;
    afc.mk_dir(path).await?;
    Ok(())
}

pub async fn rename_ios_path(udid: String, from: String, to: String) -> Result<(), IosError> {
    let mut afc = afc_client(&udid).await?;
    afc.rename(from, to).await?;
    Ok(())
}

/// Deletes a file or directory. Recursive, matching the CLI backend's `rm`
/// (which prompts for confirmation on a non-empty path; AFC has no prompt).
pub async fn delete_ios_path(udid: String, path: String) -> Result<(), IosError> {
    let mut afc = afc_client(&udid).await?;
    afc.remove_all(path).await?;
    Ok(())
}

/// Copies a device file or directory tree to `local_path`.
pub async fn download_ios_path(
    udid: String,
    device_path: String,
    local_path: String,
) -> Result<(), IosError> {
    let mut afc = afc_client(&udid).await?;
    download_recursive(&mut afc, &device_path, &local_path).await
}

/// Copies a local file or directory tree to `device_path`.
pub async fn upload_ios_path(
    udid: String,
    local_path: String,
    device_path: String,
) -> Result<(), IosError> {
    let mut afc = afc_client(&udid).await?;
    upload_recursive(&mut afc, &local_path, &device_path).await
}

async fn download_recursive(
    afc: &mut AfcClient,
    device_path: &str,
    local_path: &str,
) -> Result<(), IosError> {
    let info = afc.get_file_info(device_path.to_string()).await?;

    if info.st_ifmt != "S_IFDIR" {
        // Streamed a chunk at a time: an app container or a video can be
        // gigabytes, and nothing here needs the whole file in memory.
        let mut descriptor = afc.open(device_path, AfcFopenMode::RdOnly).await?;
        let mut file = tokio::fs::File::create(local_path)
            .await
            .map_err(|error| IosError::Other(error.to_string()))?;
        loop {
            let chunk = descriptor.read_n(AFC_TRANSFER_CHUNK).await?;
            if chunk.is_empty() {
                break;
            }
            file.write_all(&chunk)
                .await
                .map_err(|error| IosError::Other(error.to_string()))?;
        }
        file.flush()
            .await
            .map_err(|error| IosError::Other(error.to_string()))?;
        descriptor.close().await?;
        return Ok(());
    }

    tokio::fs::create_dir_all(local_path)
        .await
        .map_err(|error| IosError::Other(error.to_string()))?;

    for name in afc.list_dir(device_path.to_string()).await? {
        if name == "." || name == ".." {
            continue;
        }
        Box::pin(download_recursive(
            afc,
            &join_afc_path(device_path, &name),
            &format!("{local_path}/{name}"),
        ))
        .await?;
    }
    Ok(())
}

async fn upload_recursive(
    afc: &mut AfcClient,
    local_path: &str,
    device_path: &str,
) -> Result<(), IosError> {
    let metadata = tokio::fs::metadata(local_path)
        .await
        .map_err(|error| IosError::Other(error.to_string()))?;

    if !metadata.is_dir() {
        let mut file = tokio::fs::File::open(local_path)
            .await
            .map_err(|error| IosError::Other(error.to_string()))?;
        let mut descriptor = afc.open(device_path, AfcFopenMode::WrOnly).await?;
        let mut buffer = vec![0u8; AFC_TRANSFER_CHUNK];
        loop {
            let read = file
                .read(&mut buffer)
                .await
                .map_err(|error| IosError::Other(error.to_string()))?;
            if read == 0 {
                break;
            }
            descriptor.write_entire(&buffer[..read]).await?;
        }
        descriptor.close().await?;
        return Ok(());
    }

    // Already existing is fine — this mirrors `put -rf`.
    let _ = afc.mk_dir(device_path.to_string()).await;

    let mut children = tokio::fs::read_dir(local_path)
        .await
        .map_err(|error| IosError::Other(error.to_string()))?;

    while let Ok(Some(child)) = children.next_entry().await {
        let name = child.file_name().to_string_lossy().to_string();
        Box::pin(upload_recursive(
            afc,
            &child.path().to_string_lossy(),
            &join_afc_path(device_path, &name),
        ))
        .await?;
    }
    Ok(())
}

/// Bytes per AFC read or write while transferring files — the most the crate
/// (and libimobiledevice's afcclient) sends in one packet.
const AFC_TRANSFER_CHUNK: usize = 1024 * 1024;

fn join_afc_path(parent: &str, name: &str) -> String {
    if parent.ends_with('/') {
        format!("{parent}{name}")
    } else {
        format!("{parent}/{name}")
    }
}

async fn afc_client(udid: &str) -> Result<AfcClient, IosError> {
    Ok(AfcClient::connect(&provider_for(udid).await?).await?)
}

/// Resolves a UDID to a connection provider — every service starts here.
async fn provider_for(udid: &str) -> Result<UsbmuxdProvider, IosError> {
    let mut usbmuxd = connect_usbmuxd().await?;
    let device = usbmuxd.get_device(udid).await?;
    let address = UsbmuxdAddr::from_env_var().unwrap_or_default();
    Ok(device.to_provider(address, CLIENT_LABEL))
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::DateTime;

    /// A record as idevice 0.1.65 builds it: `from_timestamp(seconds,
    /// microseconds).naive_local()` — UTC, with micros in the nanos field.
    fn record(seconds: i64, microseconds: u32, message: &str) -> OsTraceLog {
        OsTraceLog {
            pid: 42,
            timestamp: DateTime::from_timestamp(seconds, microseconds)
                .unwrap()
                .naive_local(),
            level: LogLevel::Error,
            image_name: "/System/Library/Frameworks/QuartzCore.framework/QuartzCore".into(),
            filename: "/usr/libexec/backboardd".into(),
            message: message.into(),
            label: None,
        }
    }

    #[test]
    fn formats_in_host_local_time_with_microseconds() {
        let seconds = 1_792_000_000;
        let expected_clock = Local
            .timestamp_opt(seconds, 0)
            .unwrap()
            .format("%b %e %H:%M:%S");

        assert_eq!(
            format_os_trace_log(&record(seconds, 1_234, "boom")),
            format!("{expected_clock}.001234 backboardd(QuartzCore)[42] <Error>: boom"),
        );
    }

    #[test]
    fn skips_only_record_decode_errors() {
        let unexpected = |detail: &str| IdeviceError::UnexpectedResponse(detail.into());

        assert!(is_skippable_record_error(&unexpected(
            "unknown log level byte value"
        )));
        assert!(is_skippable_record_error(&unexpected(
            "invalid timestamp in log packet"
        )));
        assert!(!is_skippable_record_error(&unexpected(
            "expected leading byte 0x02 at start of log packet"
        )));
        assert!(!is_skippable_record_error(
            &IdeviceError::NoEstablishedConnection
        ));
    }
}
