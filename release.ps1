<#
  One command for a new release:  .\release.ps1
  - bumps the version in pubspec.yaml (1.1.1+2 -> 1.1.2+3: patch and build number)
  - builds the release APK
  - leaves softifex-booking-v<version>-<build>.apk in build\app\outputs\flutter-apk

  .\release.ps1 -Part minor    1.1.1+2 -> 1.2.0+3
  .\release.ps1 -Part major    1.1.1+2 -> 2.0.0+3
  .\release.ps1 -Part build    1.1.1+2 -> 1.1.1+3   (rebuild, same version name)
  .\release.ps1 -DryRun        show the new version, change nothing
#>
param(
  [ValidateSet('patch', 'minor', 'major', 'build')][string]$Part = 'patch',
  [switch]$DryRun
)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

$pub = Get-Content pubspec.yaml -Raw
if ($pub -notmatch '(?m)^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$') {
  throw 'pubspec.yaml needs a line like "version: 1.0.0+1"'
}
$maj = [int]$Matches[1]; $min = [int]$Matches[2]; $pat = [int]$Matches[3]; $bld = [int]$Matches[4] + 1
switch ($Part) {
  'major' { $maj++; $min = 0; $pat = 0 }
  'minor' { $min++; $pat = 0 }
  'patch' { $pat++ }
}
$new = "$maj.$min.$pat+$bld"
$apk = "softifex-booking-v$maj-$min-$pat-$bld.apk"
Write-Host "New version: $new  ->  $apk"
if ($DryRun) { return }

$original = $pub
$pub = $pub -replace '(?m)^version:\s*.*$', "version: $new"
[System.IO.File]::WriteAllText("$PWD\pubspec.yaml", $pub, (New-Object System.Text.UTF8Encoding($false)))

flutter pub get
if ($LASTEXITCODE -ne 0) { throw "pub get failed" }

# `flutter pub get` writes the plugin list WITH dev-only plugins (integration_test),
# which a release build does not contain, so it fails to compile. Dropping the
# generated file makes the build recreate it for release.
$registrant = 'android\app\src\main\java\io\flutter\plugins\GeneratedPluginRegistrant.java'
if (Test-Path $registrant) { Remove-Item $registrant -Force }

flutter build apk --release
if ($LASTEXITCODE -ne 0) {
  # Failed builds don't use up a version number.
  [System.IO.File]::WriteAllText("$PWD\pubspec.yaml", $original, (New-Object System.Text.UTF8Encoding($false)))
  throw 'Build failed; pubspec.yaml version restored. Check the error above.'
}

# app-release.apk must stay (Flutter itself looks for it); the named copy goes
# to the Installer folder so it is the only one you hand out.
$installer = 'D:\My-work\inventory soft\Installer'
$built = "build\app\outputs\flutter-apk\$apk"
if (-not (Test-Path $installer)) { New-Item -ItemType Directory -Path $installer | Out-Null }
Move-Item $built "$installer\$apk" -Force
Write-Host "Done: $installer\$apk"
