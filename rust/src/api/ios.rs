pub struct IosDeviceSummary {
    pub udid: String,
    pub name: String,
    pub product_type: String,    // "iPhone14,2"
    pub product_version: String, // "17.5.1"
    pub is_network: bool,
}

pub async fn list_ios_devices() -> Result<Vec<IosDeviceSummary>, IosError> {}

pub enum IosError {
    UsbmuxdUnavailable,
    DeviceNotFound(String),
    NotPaired(String),
    PairingDialogPending(String),
    Locked(String),
    Other(String),
}
