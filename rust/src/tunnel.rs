//! The CoreDevice tunnel Xcode reaches a phone's developer services through:
//! a lockdown `CoreDeviceProxy` tunnel over usbmux, a userspace TCP stack on
//! top of it, and RemoteXPC services listed by Remote Service Discovery. The
//! screen mirror (`api/ios_mirror.rs`) and app control
//! (`api/ios_app_control.rs`) share it. The services come from Xcode's
//! developer disk image, so the phone needs Developer Mode and that image
//! mounted.

use idevice::core_device_proxy::CoreDeviceProxy;
use idevice::rsd::RsdHandshake;
use idevice::tcp::handle::AdapterHandle;
use idevice::{IdeviceService, ReadWrite, RsdService};

use crate::api::ios::{provider_for, IosError};

pub(crate) type Rw = Box<dyn ReadWrite>;

/// Connects the RSD service `$client` over `$tunnel`.
///
/// A macro rather than a generic method: through a type parameter rustc cannot
/// see that the connect future is `Send`, and a spawned caller then fails with
/// "implementation of `RsdService` is not general enough" (the `'static` on the
/// client's `Box<dyn ReadWrite>` is lost). Boxing the future as
/// `dyn Future + Send` at the concrete type settles it there.
macro_rules! connect {
    ($tunnel:expr, $client:ty) => {{
        let tunnel: &mut $crate::tunnel::Tunnel = $tunnel;
        let connecting: std::pin::Pin<
            Box<
                dyn std::future::Future<Output = Result<$client, idevice::IdeviceError>>
                    + Send
                    + '_,
            >,
        > = Box::pin(<$client as idevice::RsdService>::connect_rsd(
            &mut tunnel.adapter,
            &mut tunnel.handshake,
        ));
        connecting.await
    }};
}
pub(crate) use connect;

/// A CoreDevice tunnel to one phone, with its service listing.
pub(crate) struct Tunnel {
    pub(crate) adapter: AdapterHandle,
    pub(crate) handshake: RsdHandshake,
}

impl Tunnel {
    /// usbmux → lockdown `CoreDeviceProxy` → userspace TCP → RSD handshake.
    /// About 75 ms over USB.
    pub(crate) async fn open(udid: &str) -> Result<Tunnel, IosError> {
        let provider = provider_for(udid).await?;
        let proxy = CoreDeviceProxy::connect(&provider).await?;
        let rsd_port = proxy.tunnel_info().server_rsd_port;
        let mut adapter = proxy.create_software_tunnel()?.to_async_handle();
        let stream = adapter.connect(rsd_port).await.map_err(io_error)?;
        let handshake = RsdHandshake::new(stream).await?;
        Ok(Tunnel { adapter, handshake })
    }

    pub(crate) fn offers<T: RsdService>(&self) -> bool {
        self.handshake
            .services
            .contains_key(T::rsd_service_name().as_ref())
    }

    pub(crate) async fn close(mut self) {
        let _ = self.adapter.close().await;
    }
}

pub(crate) fn io_error(error: std::io::Error) -> IosError {
    IosError::Other(error.to_string())
}
