# Fails unless the Windows packages carry the Visual C++ runtime app-local, next
# to eagly.exe, and at least as new as the STL we compile against needs.
#
# Why: the release is built on GitHub's newest Windows image (VS 2026). Since
# VS 2022 17.10 the STL's std::mutex is constexpr-constructed and requires
# msvcp140.dll 14.40+; when the app picked up an older copy from System32 (an
# un-updated Windows 10 21H2) it crashed in msvcp140!mtx_do_lock — Sentry
# FLUTTER-M2 / FLUTTER-M7, https://github.com/microsoft/STL/issues/4730.
# windows/CMakeLists.txt installs the runtime next to the exe (that is what the
# Inno Setup installer ships) and the msix tool packs its own copy into the
# .msix; this guard keeps a toolchain, fastforge or msix change from silently
# dropping either.
#
# The installer is checked by really installing it (silently, into a temp dir)
# rather than trusting the build directory: fastforge packages the exe from a
# copy of build/, and the msix step deletes the runtime DLLs from build/ again.
#
# Usage:
#   scripts/check_windows_vc_runtime.ps1 -Installer <setup.exe> -Msix <app.msix>
# Either argument may be omitted to check only the other package.
param(
  [string]$Installer,
  [string]$Msix,
  # The constexpr-mutex floor (MSVC STL 17.10 = msvcp140.dll 14.40).
  [version]$MinVersion = '14.40.0.0'
)

$ErrorActionPreference = 'Stop'

# The DLLs anything in the app can import from the VC++ runtime; the rest of a
# Microsoft.VC<nnn>.CRT folder (concrt140, vcruntime140_threads, ...) is shipped
# too but not required here.
$Required = @(
  'msvcp140.dll', 'msvcp140_1.dll', 'msvcp140_2.dll',
  'vcruntime140.dll', 'vcruntime140_1.dll'
)
$Versioned = @('msvcp140.dll', 'vcruntime140.dll')

$failures = [System.Collections.Generic.List[string]]::new()

function Test-RuntimeDir([string]$Label, [string]$Dir) {
  Write-Host "== $Label ($Dir)"
  Get-ChildItem -LiteralPath $Dir -Filter '*.dll' |
    Where-Object { $_.Name -match '^(msvcp|vcruntime|concrt|vccorlib)140' } |
    ForEach-Object { Write-Host ("   {0,-32} {1}" -f $_.Name, $_.VersionInfo.FileVersionRaw) }
  foreach ($name in $Required) {
    $path = Join-Path $Dir $name
    if (-not (Test-Path -LiteralPath $path)) {
      $failures.Add("${Label}: $name is missing next to eagly.exe")
      continue
    }
    if ($Versioned -contains $name) {
      $v = (Get-Item -LiteralPath $path).VersionInfo.FileVersionRaw
      if ($v -lt $MinVersion) {
        $failures.Add("${Label}: $name is $v, older than $MinVersion")
      }
    }
  }
  if (-not (Test-Path -LiteralPath (Join-Path $Dir 'eagly.exe'))) {
    $failures.Add("${Label}: eagly.exe not found at the package root")
  }
}

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("eagly-vcrt-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $work | Out-Null

try {
  if ($Installer) {
    $dir = Join-Path $work 'installed'
    # [Run]'s launch entry is skipifsilent, so this does not start the app.
    $p = Start-Process -FilePath $Installer -Wait -PassThru -ArgumentList @(
      '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOICONS',
      "/DIR=`"$dir`"", "/LOG=`"$work\install.log`""
    )
    if ($p.ExitCode -ne 0) {
      Get-Content -LiteralPath "$work\install.log" -ErrorAction SilentlyContinue
      $failures.Add("installer: exited with $($p.ExitCode)")
    } else {
      Test-RuntimeDir 'installer' $dir
      $uninstaller = Join-Path $dir 'unins000.exe'
      if (Test-Path -LiteralPath $uninstaller) {
        Start-Process -FilePath $uninstaller -Wait -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART'
      }
    }
  }

  if ($Msix) {
    # An .msix is a zip; the package root is the app directory.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $dir = Join-Path $work 'msix'
    [System.IO.Compression.ZipFile]::ExtractToDirectory($Msix, $dir)
    Test-RuntimeDir 'msix' $dir
  }
} finally {
  Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
  foreach ($f in $failures) { Write-Host "::error::VC++ runtime check: $f" }
  Write-Host 'The app would load the system msvcp140.dll and can crash on PCs with an old VC++ Redistributable (see windows/CMakeLists.txt).'
  exit 1
}
Write-Host 'VC++ runtime is bundled app-local in every checked package.'
