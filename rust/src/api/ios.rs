//! iOS device discovery, backed by the `idevice` crate talking to usbmuxd
//! directly. Replaces shelling out to `idevice_id -l` + `ideviceinfo -u <udid>`.

use idevice::provider::IdeviceProvider;
use idevice::services::lockdown::LockdownClient;
use idevice::usbmuxd::{Connection, UsbmuxdAddr, UsbmuxdConnection, UsbmuxdDevice};
use idevice::{IdeviceError, IdeviceService};
use plist::Value;

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

/// Reads the lockdownd values for one device. Private, so flutter_rust_bridge
/// leaves it alone and `?` stays usable for the fallible half of the listing.
async fn describe(device: &UsbmuxdDevice) -> Result<IosDeviceSummary, IosError> {
    let address = UsbmuxdAddr::from_env_var().unwrap_or_default();
    let provider = device.to_provider(address, CLIENT_LABEL);

    let mut lockdown = LockdownClient::connect(&provider).await?;
    lockdown
        .start_session(&provider.get_pairing_file().await?)
        .await?;

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
