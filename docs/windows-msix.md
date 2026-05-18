# Windows MSIX packaging

This project is configured to build a Windows installer with the [`msix`](https://pub.dev/packages/msix) package.

## Goal: no install warnings for end users

To avoid the **"Unknown publisher"** warning, the released `.msix` must be signed with a **trusted code-signing certificate**.

Important:

- The default self-signed test certificate that `msix` can generate is fine for local testing only.
- It is **not** suitable for public distribution.
- If you want to avoid Microsoft Store distribution warnings as well, use either:
  - a Microsoft Store submission, or
  - an EV/OV code-signing certificate from a trusted CA.

## Current package identity

`pubspec.yaml` currently uses:

- `display_name`: `Eagly`
- `publisher_display_name`: `Gyanoba`
- `identity_name`: `com.gyanoba.eagly`
- `publisher`: `CN=Gyanoba`

The signing certificate subject must match the configured `publisher` value exactly.

If your certificate subject is different, update `msix_config.publisher` in `pubspec.yaml` before creating the release package.

## Files the developer must provide

Place your release signing certificate at:

```text
windows/certificates/eagly-release.pfx
```

That folder is intentionally gitignored for `.pfx`, `.p12`, `.cer`, and `.crt` files.

Recommended:

- keep the certificate outside source control
- export it as a password-protected `.pfx`
- store the password in a local environment variable instead of hardcoding it

## Release packaging process

Run the packaging step on **Windows**.

1. Ensure Flutter Windows desktop support is enabled.
2. Make sure your signing certificate is available locally.
3. Set a local environment variable for the certificate password.
4. Create the signed MSIX package.

### PowerShell example

```powershell
$env:MSIX_CERT_PASSWORD = "<your-password>"
flutter pub get
flutter build windows --release

dart run msix:create \
  --certificate-path windows/certificates/eagly-release.pfx \
  --certificate-password $env:MSIX_CERT_PASSWORD
```

### Command Prompt example

```bat
set MSIX_CERT_PASSWORD=<your-password>
flutter pub get
flutter build windows --release

dart run msix:create --certificate-path windows/certificates/eagly-release.pfx --certificate-password %MSIX_CERT_PASSWORD%
```

## Developer checklist before shipping

- Confirm the certificate subject matches `msix_config.publisher` exactly.
- Confirm `msix_version` is bumped for every public release.
- Build on Windows using the release certificate.
- Install the generated `.msix` on a clean Windows machine or VM.
- Verify the installer shows your real publisher name instead of `Unknown publisher`.
- Verify the app launches and bundled tools still work from the packaged install.

## Notes

- `msix_config.install_certificate` is set to `false` so the build tool does not try to install certificates automatically on the developer machine.
- If you later publish through the Microsoft Store, keep the store publisher identity aligned with the same metadata fields in `pubspec.yaml`.

