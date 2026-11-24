//! Switching off the settings that make a device reachable over Wi-Fi.
//!
//! The change can cut the very connection it is made over, so "the phone went
//! away" is an outcome here rather than an error, and nothing counts as done
//! until the phone has said so.

use std::future::Future;

use idevice::services::lockdown::LockdownClient;
use idevice::IdeviceError;
use plist::{Dictionary, Value};

/// lockdownd domain holding a device's Wi-Fi connection switches.
const DOMAIN: &str = "com.apple.mobile.wireless_lockdown";

/// The switches that make a device offer itself to its paired computers over
/// Wi-Fi: Xcode's "Connect via network" sets the first, Finder's "Show this
/// iPhone when on Wi-Fi" the second. Either one is enough for usbmuxd to
/// reach the device on the network with the pairing record from a past USB
/// "Trust".
const KEYS: [&str; 2] = ["EnableWifiDebugging", "EnableWifiConnections"];

/// How [`switch_off`] ended.
#[derive(Debug, PartialEq)]
pub(crate) enum SwitchOff {
    /// The device reports every switch off.
    Confirmed,
    /// The change was sent, but the device could not be asked whether it took.
    Unconfirmed,
    /// The device still reports this switch on.
    Refused(&'static str),
}

/// A device's Wi-Fi switches: lockdownd, or a stand-in in tests.
pub(crate) trait WifiSwitches: Send {
    fn read(&mut self) -> impl Future<Output = Result<Dictionary, IdeviceError>> + Send;
    fn turn_off(
        &mut self,
        key: &'static str,
    ) -> impl Future<Output = Result<(), IdeviceError>> + Send;
}

impl WifiSwitches for LockdownClient {
    async fn read(&mut self) -> Result<Dictionary, IdeviceError> {
        match self.get_value(None, Some(DOMAIN)).await? {
            Value::Dictionary(values) => Ok(values),
            _ => Err(IdeviceError::UnexpectedResponse(format!(
                "{DOMAIN} is not a dictionary"
            ))),
        }
    }

    async fn turn_off(&mut self, key: &'static str) -> Result<(), IdeviceError> {
        self.set_value(key, Value::Boolean(false), Some(DOMAIN))
            .await
    }
}

/// Turns off whichever switches are on, then asks whether they are off.
///
/// An error means the device could not be read to begin with, or answered
/// that it would not change a switch. Only switches that are on are written:
/// with one on, as is usual, there is no second write to lose to the first
/// one closing the connection.
pub(crate) async fn switch_off<S: WifiSwitches>(
    switches: &mut S,
) -> Result<SwitchOff, IdeviceError> {
    let before = switches.read().await?;
    let on: Vec<&'static str> = KEYS.into_iter().filter(|key| is_on(&before, key)).collect();
    if on.is_empty() {
        return Ok(SwitchOff::Confirmed);
    }
    for key in on {
        match switches.turn_off(key).await {
            Ok(()) => {}
            Err(error) if lost_connection(&error) => return Ok(SwitchOff::Unconfirmed),
            Err(error) => return Err(error),
        }
    }
    Ok(match switches.read().await {
        Ok(after) => match KEYS.into_iter().find(|key| is_on(&after, key)) {
            Some(key) => SwitchOff::Refused(key),
            None => SwitchOff::Confirmed,
        },
        Err(_) => SwitchOff::Unconfirmed,
    })
}

/// A switch the device does not list is one nobody ever turned on.
fn is_on(values: &Dictionary, key: &str) -> bool {
    values
        .get(key)
        .and_then(Value::as_boolean)
        .unwrap_or_default()
}

fn lost_connection(error: &IdeviceError) -> bool {
    matches!(
        error,
        IdeviceError::Socket(_) | IdeviceError::Timeout | IdeviceError::NoEstablishedConnection
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A phone that can drop off before its nth request or refuse writes.
    struct Phone {
        values: Dictionary,
        writes: Vec<&'static str>,
        requests: usize,
        gone_after: usize,
        ignores_writes: bool,
        refuses_writes: bool,
    }

    impl Phone {
        fn new(debugging: bool, connections: bool) -> Self {
            let mut values = Dictionary::new();
            values.insert("EnableWifiDebugging".into(), debugging.into());
            values.insert("EnableWifiConnections".into(), connections.into());
            Phone {
                values,
                writes: Vec::new(),
                requests: 0,
                gone_after: usize::MAX,
                ignores_writes: false,
                refuses_writes: false,
            }
        }

        fn request(&mut self) -> Result<(), IdeviceError> {
            self.requests += 1;
            if self.requests > self.gone_after {
                return Err(IdeviceError::Socket(
                    std::io::ErrorKind::ConnectionReset.into(),
                ));
            }
            Ok(())
        }
    }

    impl WifiSwitches for Phone {
        async fn read(&mut self) -> Result<Dictionary, IdeviceError> {
            self.request()?;
            Ok(self.values.clone())
        }

        async fn turn_off(&mut self, key: &'static str) -> Result<(), IdeviceError> {
            self.request()?;
            if self.refuses_writes {
                return Err(IdeviceError::UnknownErrorType("SetProhibited".into()));
            }
            self.writes.push(key);
            if !self.ignores_writes {
                self.values.insert(key.into(), false.into());
            }
            Ok(())
        }
    }

    #[tokio::test]
    async fn writes_only_the_switches_that_are_on() {
        let mut phone = Phone::new(true, false);
        assert_eq!(switch_off(&mut phone).await.unwrap(), SwitchOff::Confirmed);
        assert_eq!(phone.writes, ["EnableWifiDebugging"]);
    }

    #[tokio::test]
    async fn turns_both_off() {
        let mut phone = Phone::new(true, true);
        assert_eq!(switch_off(&mut phone).await.unwrap(), SwitchOff::Confirmed);
        assert_eq!(phone.writes, KEYS);
    }

    #[tokio::test]
    async fn unlisted_or_off_switches_need_no_write() {
        let mut phone = Phone::new(false, false);
        phone.values.remove("EnableWifiConnections");
        assert_eq!(switch_off(&mut phone).await.unwrap(), SwitchOff::Confirmed);
        assert!(phone.writes.is_empty());
    }

    #[tokio::test]
    async fn a_phone_lost_on_the_way_is_unconfirmed() {
        // Request 1 reads, 2 and 3 write, 4 reads back.
        for gone_after in 1..=3 {
            let mut phone = Phone::new(true, true);
            phone.gone_after = gone_after;
            assert_eq!(
                switch_off(&mut phone).await.unwrap(),
                SwitchOff::Unconfirmed,
                "gone after request {gone_after}"
            );
        }
    }

    #[tokio::test]
    async fn a_phone_that_cannot_be_read_first_is_an_error() {
        let mut phone = Phone::new(true, true);
        phone.gone_after = 0;
        assert!(switch_off(&mut phone).await.is_err());
        assert!(phone.writes.is_empty());
    }

    #[tokio::test]
    async fn a_refused_write_is_an_error() {
        let mut phone = Phone::new(true, true);
        phone.refuses_writes = true;
        assert!(switch_off(&mut phone).await.is_err());
    }

    #[tokio::test]
    async fn a_switch_that_stays_on_is_reported() {
        let mut phone = Phone::new(true, false);
        phone.ignores_writes = true;
        assert_eq!(
            switch_off(&mut phone).await.unwrap(),
            SwitchOff::Refused("EnableWifiDebugging")
        );
    }
}
