# publish_android.ps1 - build the Android app and put it on domailit.com
#
# Run from the mobile folder:
#     powershell -ExecutionPolicy Bypass -File .\publish_android.ps1
#
# What it does:
#   1. First time only: makes DoMailit's signing key (asks for a password).
#   2. Builds the APKs with the version from pubspec.yaml.
#   3. Uploads them to the server (asks for the server password twice).
# After that, "Download for Android" on domailit.com gives this version, and
# apps already on phones show "Update available".
#
# New version later? Raise "version:" in pubspec.yaml (1.0.0+1 -> 1.0.1+2),
# then run this script again.

param(
    [string]$Server = "root@13.140.75.136",
    [string]$Notes = ""
)
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Plain([Security.SecureString]$s) {
    [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
}

# ---------- 1. signing key (first time only) ----------
$keyProps = Join-Path $PSScriptRoot "android\key.properties"
if (-not (Test-Path $keyProps)) {
    $jks = Join-Path $env:USERPROFILE "domailit-release.jks"
    $keytool = "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe"
    if (-not (Test-Path $keytool)) { $keytool = "keytool" }

    if (Test-Path $jks) {
        Write-Host "Found your key: $jks" -ForegroundColor Cyan
        $pw = Plain (Read-Host "Type the key password" -AsSecureString)
    } else {
        Write-Host ""
        Write-Host "First time: creating DoMailit's signing key." -ForegroundColor Cyan
        $pw = Plain (Read-Host "Choose a password for the key (at least 6 characters)" -AsSecureString)
        $pw2 = Plain (Read-Host "Type it again" -AsSecureString)
        if ($pw -ne $pw2) { throw "The two passwords are different. Run the script again." }
        if ($pw.Length -lt 6) { throw "The password needs at least 6 characters." }
        & $keytool -genkeypair -keystore $jks -keyalg RSA -keysize 2048 -validity 10000 `
            -alias domailit -storepass $pw -keypass $pw `
            -dname "CN=DoMailit, O=DoMailit, L=Faisalabad, C=PK"
        if ($LASTEXITCODE -ne 0) { throw "Could not create the key (keytool failed)." }
    }
    $jksPath = $jks -replace '\\', '/'
    Set-Content -Path $keyProps -Encoding ascii -Value @(
        "storePassword=$pw", "keyPassword=$pw", "keyAlias=domailit", "storeFile=$jksPath")
    Write-Host ""
    Write-Host "Key ready: $jks" -ForegroundColor Green
    Write-Host "IMPORTANT: back up this file AND its password (e.g. Google Drive)." -ForegroundColor Yellow
    Write-Host "Without them you can never update the app on people's phones." -ForegroundColor Yellow
    Write-Host ""
}

# ---------- 2. version + build ----------
$match = Select-String -Path "pubspec.yaml" -Pattern '^version:\s*([0-9.]+)\+([0-9]+)'
if (-not $match) { throw "pubspec.yaml needs a line like: version: 1.0.0+1" }
$versionName = $match.Matches[0].Groups[1].Value
$build = [int]$match.Matches[0].Groups[2].Value
Write-Host "Building DoMailit $versionName (build $build)..." -ForegroundColor Cyan

flutter build apk --release --split-per-abi --dart-define=APP_BUILD=$build
if ($LASTEXITCODE -ne 0) { throw "Build failed (split APKs)." }
flutter build apk --release --dart-define=APP_BUILD=$build
if ($LASTEXITCODE -ne 0) { throw "Build failed (universal APK)." }

# ---------- 3. upload ----------
$out = "build\app\outputs\flutter-apk"
$stage = Join-Path $env:TEMP "domailit-publish"
if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
New-Item -ItemType Directory $stage | Out-Null
Copy-Item "$out\app-arm64-v8a-release.apk" "$stage\DoMailit-arm64.apk"
Copy-Item "$out\app-release.apk" "$stage\DoMailit-universal.apk"
@{ version_name = $versionName; build = $build; notes = $Notes;
   released = (Get-Date -Format "yyyy-MM-dd") } | ConvertTo-Json | Set-Content "$stage\android.json" -Encoding utf8

Write-Host ""
Write-Host "Uploading to $Server (it will ask for the server password)..." -ForegroundColor Cyan
ssh $Server "mkdir -p /opt/domailit-downloads"
if ($LASTEXITCODE -ne 0) { throw "Could not reach the server." }
scp "$stage\DoMailit-arm64.apk" "$stage\DoMailit-universal.apk" "$stage\android.json" "${Server}:/opt/domailit-downloads/"
if ($LASTEXITCODE -ne 0) { throw "Upload failed." }

Write-Host ""
Write-Host "Done! DoMailit $versionName is on https://domailit.com/download/android" -ForegroundColor Green
