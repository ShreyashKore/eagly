//! What the Apps pane does to an iOS app beyond installing it.
//!
//! Opening and force-stopping go through CoreDevice's app service
//! (`com.apple.coredevice.appservice`): the tunnel the screen mirror uses
//! (`tunnel.rs`), so the phone needs Developer Mode and Xcode's developer disk
//! image mounted, and iOS 17 or later. Without them there is no app service,
//! and [`probe_ios_app_control`] says so.
//!
//! Clearing data goes through house_arrest, a plain lockdown service, which
//! opens only a debug build's container (one signed `get-task-allow`).

use idevice::core_device::AppServiceClient;
use idevice::services::afc::errors::AfcError;
use idevice::services::afc::AfcClient;
use idevice::services::house_arrest::HouseArrestClient;
use idevice::{IdeviceError, IdeviceService};

use super::ios::{ios_app_bundle_path, provider_for, IosError};
use crate::tunnel::{connect, Rw, Tunnel};

/// SIGKILL: what Android's force-stop sends too.
const KILL: u32 = 9;

/// Whether `udid` offers the app service, so the Apps pane can offer Open and
/// Force Stop.
pub async fn probe_ios_app_control(udid: String) -> Result<bool, IosError> {
    let tunnel = Tunnel::open(&udid).await?;
    let offered = tunnel.offers::<AppServiceClient<Rw>>();
    tunnel.close().await;
    Ok(offered)
}

/// Opens the app.
pub async fn launch_ios_app(udid: String, bundle_id: String) -> Result<(), IosError> {
    let mut tunnel = Tunnel::open(&udid).await?;
    let launched = async {
        let mut apps = connect!(&mut tunnel, AppServiceClient<Rw>)?;
        apps.launch_application(bundle_id, &[], false, false, None, None, None)
            .await?;
        Ok::<_, IosError>(())
    }
    .await;
    tunnel.close().await;
    launched
}

/// Kills every process running from the app's bundle, its extensions too, as
/// Android's force-stop ends all of a package's processes. Returns how many it
/// killed: none when the app wasn't running.
///
/// The bundle's path comes from installation_proxy: the app service's own
/// `listapps` is refused on iOS 27 by idevice 0.1.65, which leaves out its
/// `requireContainerAccess` key.
pub async fn stop_ios_app(udid: String, bundle_id: String) -> Result<u32, IosError> {
    let bundle = format!(
        "{}/",
        ios_app_bundle_path(&udid, &bundle_id)
            .await?
            .trim_end_matches('/')
    );
    let mut tunnel = Tunnel::open(&udid).await?;
    let stopped = async {
        let mut apps = connect!(&mut tunnel, AppServiceClient<Rw>)?;
        let mut killed = 0;
        for process in apps.list_processes().await? {
            let Some(executable) = process.executable_url else {
                continue;
            };
            if is_inside(&executable.relative, &bundle) {
                apps.send_signal(process.pid, KILL).await?;
                killed += 1;
            }
        }
        Ok::<_, IosError>(killed)
    }
    .await;
    tunnel.close().await;
    stopped
}

/// The directories of an app's data container that hold its data. Clearing
/// empties them and keeps them, as an app expects to find them.
const DATA_DIRECTORIES: [&str; 3] = ["/Documents", "/Library", "/tmp"];

/// Directories iOS creates inside `Library` at install. Clearing empties them
/// rather than removing them, for the same reason.
const INSTALLED_DIRECTORIES: [&str; 2] = ["/Library/Caches", "/Library/Preferences"];

/// Deletes the app's data, as Android's Clear Data does: everything in its
/// `Documents`, `Library` and `tmp`. Its keychain items stay, as they do when
/// an iOS app is deleted. Only a debug build lets Eagly in; any other app is
/// refused.
///
/// Once the container is open, stops the app when the phone offers the app
/// service, so it can't write its state back; without it, clearing goes
/// ahead regardless. A refused app is left running.
pub async fn clear_ios_app_data(udid: String, bundle_id: String) -> Result<(), IosError> {
    let provider = provider_for(&udid).await?;
    let house_arrest = HouseArrestClient::connect(&provider).await?;
    let mut container = house_arrest.vend_container(bundle_id.clone()).await?;
    let _ = stop_ios_app(udid, bundle_id).await;
    for directory in DATA_DIRECTORIES {
        for path in entries(&mut container, directory).await? {
            if INSTALLED_DIRECTORIES.contains(&path.as_str()) {
                empty(&mut container, &path).await?;
            } else {
                container.remove_all(path).await?;
            }
        }
    }
    Ok(())
}

/// Removes everything inside `directory`, keeping it.
async fn empty(afc: &mut AfcClient, directory: &str) -> Result<(), IdeviceError> {
    for path in entries(afc, directory).await? {
        afc.remove_all(path).await?;
    }
    Ok(())
}

/// The paths inside `directory`, without `.` and `..`. A directory the app
/// never made has nothing in it.
async fn entries(afc: &mut AfcClient, directory: &str) -> Result<Vec<String>, IdeviceError> {
    let names = match afc.list_dir(directory).await {
        Ok(names) => names,
        Err(IdeviceError::Afc(AfcError::ObjectNotFound)) => return Ok(Vec::new()),
        Err(error) => return Err(error),
    };
    Ok(names
        .into_iter()
        .filter(|name| name != "." && name != "..")
        .map(|name| format!("{directory}/{name}"))
        .collect())
}

/// Whether the executable at `url` (a `file://` URL) lies inside the bundle
/// directory `bundle` (a path ending in `/`). Either may carry the `/private`
/// that `/var` resolves to.
fn is_inside(url: &str, bundle: &str) -> bool {
    let unprivate = |path: &str| path.strip_prefix("/private").unwrap_or(path).to_string();
    let path = url.strip_prefix("file://").unwrap_or(url);
    unprivate(path).starts_with(&unprivate(bundle))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_executable_belongs_to_its_bundle() {
        let bundle = "/private/var/containers/Bundle/Application/A1/Notes.app/";

        assert!(is_inside(
            "file:///private/var/containers/Bundle/Application/A1/Notes.app/Notes",
            bundle
        ));
        // An extension runs out of the app's bundle too.
        assert!(is_inside(
            "file:///var/containers/Bundle/Application/A1/Notes.app/PlugIns/Widget.appex/Widget",
            bundle
        ));
        // Another app whose bundle name merely starts the same.
        assert!(!is_inside(
            "file:///private/var/containers/Bundle/Application/A1/NotesPro.app/NotesPro",
            "/private/var/containers/Bundle/Application/A1/Notes.app/"
        ));
        assert!(!is_inside(
            "file:///private/var/containers/Bundle/Application/B2/Mail.app/Mail",
            bundle
        ));
    }

    /// Opens a debug build's container without touching its data, empties a
    /// scratch directory it makes in the app's `tmp`, and checks a release
    /// build is refused. Needs a phone with a debug build installed:
    /// `EAGLY_TEST_IOS_UDID=<udid> cargo test --release debug_container -- --ignored --nocapture`
    #[tokio::test(flavor = "multi_thread")]
    #[ignore]
    async fn debug_container() {
        use idevice::services::afc::opcode::AfcFopenMode;

        let udid = std::env::var("EAGLY_TEST_IOS_UDID").expect("EAGLY_TEST_IOS_UDID");
        let Ok(apps) = super::super::ios::list_ios_apps(udid.clone(), false).await else {
            panic!("no app list")
        };
        let debug = apps
            .iter()
            .find(|app| app.is_debuggable)
            .expect("no debug build on the phone");
        let release = apps
            .iter()
            .find(|app| !app.is_debuggable)
            .expect("no release build on the phone");

        let provider = provider_for(&udid).await.ok().expect("no phone");
        let house_arrest = HouseArrestClient::connect(&provider).await.unwrap();
        let mut container = house_arrest
            .vend_container(debug.bundle_id.clone())
            .await
            .expect("a debug build's container was refused");
        let root = container.list_dir("/").await.unwrap();
        for directory in ["Documents", "Library", "tmp"] {
            assert!(root.iter().any(|name| name == directory), "no {directory}");
        }

        const SCRATCH: &str = "/tmp/eagly-clear-check";
        container.mk_dir(format!("{SCRATCH}/a/b")).await.unwrap();
        let mut file = container
            .open(format!("{SCRATCH}/a/note.txt"), AfcFopenMode::WrOnly)
            .await
            .unwrap();
        file.write_entire(b"eagly").await.unwrap();
        file.close().await.unwrap();
        container.mk_dir(format!("{SCRATCH}/c")).await.unwrap();
        assert_eq!(entries(&mut container, SCRATCH).await.unwrap().len(), 2);
        empty(&mut container, SCRATCH).await.unwrap();
        assert!(entries(&mut container, SCRATCH).await.unwrap().is_empty());
        container.remove_all(SCRATCH).await.unwrap();
        assert!(entries(&mut container, SCRATCH).await.unwrap().is_empty());
        println!(
            "{} files and folders at the container's root",
            root.len() - 2
        );

        let house_arrest = HouseArrestClient::connect(&provider).await.unwrap();
        assert!(
            house_arrest
                .vend_container(release.bundle_id.clone())
                .await
                .is_err(),
            "a release build's container was opened"
        );
    }

    /// **Deletes the data of the app named by `EAGLY_TEST_CLEAR_BUNDLE`**, a
    /// debug build, and checks nothing is left. Needs a phone:
    /// `EAGLY_TEST_IOS_UDID=<udid> EAGLY_TEST_CLEAR_BUNDLE=<bundle id> cargo test --release clear_data -- --ignored --nocapture`
    #[tokio::test(flavor = "multi_thread")]
    #[ignore]
    async fn clear_data() {
        let udid = std::env::var("EAGLY_TEST_IOS_UDID").expect("EAGLY_TEST_IOS_UDID");
        let bundle = std::env::var("EAGLY_TEST_CLEAR_BUNDLE").expect("EAGLY_TEST_CLEAR_BUNDLE");
        if let Err(IosError::Other(error)) = clear_ios_app_data(udid.clone(), bundle.clone()).await
        {
            panic!("clear: {error}");
        }

        let provider = provider_for(&udid).await.ok().expect("no phone");
        let house_arrest = HouseArrestClient::connect(&provider).await.unwrap();
        let mut container = house_arrest.vend_container(bundle).await.unwrap();
        for directory in DATA_DIRECTORIES {
            for path in entries(&mut container, directory).await.unwrap() {
                assert!(
                    INSTALLED_DIRECTORIES.contains(&path.as_str()),
                    "{path} survived"
                );
                let left = entries(&mut container, &path).await.unwrap();
                assert!(left.is_empty(), "{path} still holds {left:?}");
            }
        }
    }

    /// Opens Calculator, force-stops it, and checks it stopped. Needs a phone
    /// with Developer Mode and the developer disk image, unlocked:
    /// `EAGLY_TEST_IOS_UDID=<udid> cargo test --release open_and_stop -- --ignored --nocapture`
    #[tokio::test(flavor = "multi_thread")]
    #[ignore]
    async fn open_and_stop() {
        let udid = std::env::var("EAGLY_TEST_IOS_UDID").expect("EAGLY_TEST_IOS_UDID");
        const APP: &str = "com.apple.calculator";
        assert!(
            matches!(probe_ios_app_control(udid.clone()).await, Ok(true)),
            "no app service: is the developer disk image mounted?"
        );

        let started = std::time::Instant::now();
        if let Err(IosError::Other(error)) = launch_ios_app(udid.clone(), APP.into()).await {
            panic!("launch: {error}");
        }
        println!("opened in {} ms", started.elapsed().as_millis());
        tokio::time::sleep(std::time::Duration::from_secs(2)).await;

        let started = std::time::Instant::now();
        let killed = match stop_ios_app(udid.clone(), APP.into()).await {
            Ok(killed) => killed,
            Err(IosError::Other(error)) => panic!("stop: {error}"),
            Err(_) => panic!("stop: the phone went away"),
        };
        println!(
            "stopped {killed} process(es) in {} ms",
            started.elapsed().as_millis()
        );
        assert!(killed >= 1, "Calculator wasn't found running");

        tokio::time::sleep(std::time::Duration::from_secs(1)).await;
        let Ok(again) = stop_ios_app(udid, APP.into()).await else {
            panic!("second stop failed")
        };
        assert_eq!(again, 0, "Calculator still running after a force stop");
    }
}
