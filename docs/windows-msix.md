# Windows packaging with Fastforge

This project now uses [Fastforge](https://fastforge.dev/) for Windows packaging.

Current Windows outputs:

- `.exe` installer via Inno Setup
- `.msix` package via Fastforge's MSIX maker

## Current configuration

Windows packaging metadata lives in:

- `windows/packaging/exe/make_config.yaml`
- `windows/packaging/msix/make_config.yaml`

The current MSIX identity is:

- `display_name`: `Eagly`
- `publisher_display_name`: `Gyanoba`
- `identity_name`: `com.gyanoba.eagly`
- `publisher`: `CN=Gyanoba`

## Default behavior in this repository

The checked-in Fastforge MSIX config keeps signing disabled:

- `sign_msix: "false"`
- `install_certificate: "false"`

Note: with `fastforge 0.6.6`, these MSIX options should be written as strings in YAML. Unquoted booleans can fail during config parsing.

That keeps local builds and GitHub Actions simple, but Windows will show the usual unsigned publisher warning when installing the `.msix`.

## Local packaging

Run the packaging step on **Windows**.

1. Install [Inno Setup 6](https://jrsoftware.org/isinfo.php).
2. Install Fastforge.
3. Build both Windows artifacts.

### PowerShell example

```powershell
dart pub global activate fastforge
flutter pub get

fastforge package --platform=windows --targets=exe,msix --artifact-name='eagly-{{build_name}}-{{platform}}{{#is_installer}}-setup{{/is_installer}}{{#ext}}.{{ext}}{{/ext}}'
```

Artifacts are written to:

```text
dist/<pubspec-version>/
```

## Optional MSIX signing

If you want a signed public MSIX release, provide a trusted code-signing certificate and update `windows/packaging/msix/make_config.yaml` before packaging.

Typical fields to add or change:

- `certificate_path`
- `certificate_password`
- `sign_msix: "true"`

The signing certificate subject must match `publisher` exactly.

Recommended:

- keep `.pfx` files out of source control
- store signing material under `windows/certificates/`
- pass secrets through CI or local environment-specific workflow steps instead of committing them

## Developer checklist before shipping

- Confirm `windows/packaging/msix/make_config.yaml` matches the current app version and identity.
- If signing is enabled, confirm the certificate subject matches `publisher` exactly.
- Install both the generated `.exe` and `.msix` on a clean Windows machine or VM.
- Verify the app launches and bundled tools still work from the packaged install.


