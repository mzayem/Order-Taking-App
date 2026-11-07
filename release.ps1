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

$pub = $pub -replace '(?m)^version:\s*.*$', "version: $new"
[System.IO.File]::WriteAllText("$PWD\pubspec.yaml", $pub, (New-Object System.Text.UTF8Encoding($false)))

flutter build apk --release
if ($LASTEXITCODE -ne 0) { throw 'Build failed (pubspec.yaml already has the new version)' }
Write-Host "Done: build\app\outputs\flutter-apk\$apk"
