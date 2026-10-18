param(
    [string]$OBSInstallDir = '',
    [string]$CMakePath = 'C:\Program Files\CMake\bin\cmake.exe'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$version = '29.1.0'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$instances = @((& $vswhere -all -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json) | ConvertFrom-Json)
if (!$instances.Count) { throw 'Install Visual Studio C++ Build Tools (2019 16.11 or newer).' }
$vs = $instances | Sort-Object { [version]$_.installationVersion } -Descending | Select-Object -First 1
$major = ([version]$vs.installationVersion).Major
$generators = @{16 = 'Visual Studio 16 2019'; 17 = 'Visual Studio 17 2022'; 18 = 'Visual Studio 18 2026'}
if (!$generators.ContainsKey($major)) { throw "Unsupported Visual Studio version: $major" }
$toolVersion = (Get-Content (Join-Path $vs.installationPath 'VC\Auxiliary\Build\Microsoft.VCToolsVersion.default.txt')).Trim()
$toolsDir = Join-Path $vs.installationPath "VC\Tools\MSVC\$toolVersion\bin\Hostx64\x64"
$deps = Join-Path $root '.deps'
$sdk = Join-Path $deps "sdk-$version-x64"
$vendor = Join-Path $root 'vendor'
New-Item -ItemType Directory -Force $deps,$sdk,$vendor | Out-Null

function Get-PinnedFile([string]$Url, [string]$Path, [string]$Hash) {
    if (!(Test-Path -LiteralPath $Path)) { Invoke-WebRequest $Url -OutFile $Path }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Hash) {
        throw "Checksum mismatch: $Path"
    }
}
$archive = Join-Path $deps "obs-studio-$version.zip"
Get-PinnedFile "https://github.com/obsproject/obs-studio/archive/refs/tags/$version.zip" $archive '274CF5689238F4BA90B036A5B943C10019F27CEEB77699F361B52B992DC18F79'
$source = Join-Path $deps "obs-studio-$version"
if (!(Test-Path (Join-Path $source 'libobs\obs.h'))) {
    Expand-Archive -LiteralPath $archive -DestinationPath $deps
}
Get-PinnedFile 'https://raw.githubusercontent.com/obsproject/obs-websocket/6ef055a369249f6d7b008914fe2bc360c96f23dc/lib/obs-websocket-api.h' (Join-Path $vendor 'obs-websocket-api.h') '1A0FC704A8B92BE0BCA16B06A9CE1BB497366839DDC59A26EC66943E6DF638BB'

# Use the baseline runtime as the link provider, regardless of the user's OBS.
# The portable package stays in .deps and is never installed or launched.
if (!$OBSInstallDir) {
    $runtimeArchive = Join-Path $deps 'OBS-Studio-29.1-Full.zip'
    Get-PinnedFile 'https://github.com/obsproject/obs-studio/releases/download/29.1.0/OBS-Studio-29.1-Full.zip' $runtimeArchive 'BB6C18F9A9BF0CA847E7D20B8AFEE76C39B2BBEC0F7612C6FB899F773EE12F27'
    $OBSInstallDir = Join-Path $deps "obs-runtime-$version"
    if (!(Test-Path (Join-Path $OBSInstallDir 'bin\64bit\obs64.exe'))) {
        Expand-Archive -LiteralPath $runtimeArchive -DestinationPath $OBSInstallDir -Force
    }
}
$OBSInstallDir = (Resolve-Path -LiteralPath $OBSInstallDir).Path
$obsDll = Join-Path $OBSInstallDir 'bin\64bit\obs.dll'
$obsExe = Join-Path $OBSInstallDir 'bin\64bit\obs64.exe'
if ((Get-Item $obsExe).VersionInfo.ProductVersion -ne $version) {
    throw "The link provider must be OBS $version x64. Omit -OBSInstallDir to download the portable baseline."
}

# Create an import library from the baseline DLL's real exports. OBS itself
# remains the runtime provider; this does not build or redistribute obs.dll.
$exportDump = & (Join-Path $toolsDir 'dumpbin.exe') /nologo /exports $obsDll
if ($LASTEXITCODE) { throw 'Unable to read obs.dll exports.' }
$exports = @($exportDump | ForEach-Object {
    if ($_ -match '^\s+\d+\s+[0-9A-Fa-f]+\s+[0-9A-Fa-f]+\s+(\S+)') { $Matches[1] }
})
if ($exports -notcontains 'obs_get_version' -or $exports -notcontains 'obs_get_source_by_name') {
    throw 'Required libobs exports were not found.'
}
$def = Join-Path $sdk 'obs.def'
@('LIBRARY obs.dll', 'EXPORTS') + $exports | Set-Content -LiteralPath $def -Encoding ascii
$importLib = Join-Path $sdk 'obs.lib'
& (Join-Path $toolsDir 'lib.exe') /nologo /machine:x64 "/def:$def" "/out:$importLib"
if ($LASTEXITCODE) { throw 'Import library generation failed.' }

$sourceCmake = $source.Replace('\', '/')
$sdkCmake = $sdk.Replace('\', '/')
$dllCmake = $obsDll.Replace('\', '/')
@"
set(OBS_VERSION "$version")
set(OBS_VERSION_CANONICAL "$version")
set(OBS_RELEASE_CANDIDATE_MAJOR 0)
set(OBS_RELEASE_CANDIDATE_MINOR 0)
set(OBS_RELEASE_CANDIDATE_PATCH 0)
set(OBS_RELEASE_CANDIDATE 0)
set(OBS_BETA_MAJOR 0)
set(OBS_BETA_MINOR 0)
set(OBS_BETA_PATCH 0)
set(OBS_BETA 0)
configure_file("$sourceCmake/libobs/obsconfig.h.in" "$sdkCmake/obsconfig.h")
include(CMakePackageConfigHelpers)
write_basic_package_version_file("$sdkCmake/libobsConfigVersion.cmake" VERSION "$version" COMPATIBILITY ExactVersion)
"@ | Set-Content (Join-Path $sdk 'configure-header.cmake') -Encoding ascii
& $CMakePath -P (Join-Path $sdk 'configure-header.cmake')
if ($LASTEXITCODE) { throw 'OBS header configuration failed.' }
@"
add_library(OBS::libobs SHARED IMPORTED)
set_target_properties(OBS::libobs PROPERTIES
  IMPORTED_IMPLIB "$sdkCmake/obs.lib"
  IMPORTED_LOCATION "$dllCmake"
  INTERFACE_INCLUDE_DIRECTORIES "$sourceCmake/libobs;$sdkCmake")
"@ | Set-Content (Join-Path $sdk 'libobsConfig.cmake') -Encoding ascii

$build = Join-Path $root "build-obs$version-vs$major-x64"
& $CMakePath -S $root -B $build -G $generators[$major] -A x64 "-DCMAKE_GENERATOR_INSTANCE=$($vs.installationPath)" "-Dlibobs_DIR=$sdk" "-DOBS_WEBSOCKET_INCLUDE_DIR=$vendor"
if ($LASTEXITCODE) { throw 'CMake configuration failed.' }
& $CMakePath --build $build --config Release
if ($LASTEXITCODE) { throw 'Compilation failed.' }
& $CMakePath --install $build --config Release --prefix (Join-Path $root 'package')
if ($LASTEXITCODE) { throw 'Packaging failed.' }
Write-Host "DLL ready: $root\package\obs-plugins\64bit\obs-targeted-events.dll"
