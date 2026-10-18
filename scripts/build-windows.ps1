param(
    [string]$OBSInstallDir = 'C:\Program Files\obs-studio',
    [string]$CMakePath = 'C:\Program Files\CMake\bin\cmake.exe'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$version = '32.2.2'
$obsDll = Join-Path $OBSInstallDir 'bin\64bit\obs.dll'
$obsExe = Join-Path $OBSInstallDir 'bin\64bit\obs64.exe'
if ((Get-Item $obsExe).VersionInfo.ProductVersion -ne $version) {
    throw "This build uses OBS $version headers. Select an OBS $version installation."
}
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
$sdk = Join-Path $deps 'sdk-32.2.2-x64'
$vendor = Join-Path $root 'vendor'
New-Item -ItemType Directory -Force $deps,$sdk,$vendor | Out-Null

function Get-PinnedFile([string]$Url, [string]$Path, [string]$Hash) {
    if (!(Test-Path -LiteralPath $Path)) { Invoke-WebRequest $Url -OutFile $Path }
    if ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $Hash) {
        throw "Checksum mismatch: $Path"
    }
}
$archive = Join-Path $deps "obs-studio-$version.zip"
Get-PinnedFile "https://github.com/obsproject/obs-studio/archive/refs/tags/$version.zip" $archive 'F15F001F1FA526405318835F44F9910046502F496EBC3A30D5296A5018B831AA'
$source = Join-Path $deps "obs-studio-$version"
if (!(Test-Path (Join-Path $source 'libobs\obs.h'))) {
    Expand-Archive -LiteralPath $archive -DestinationPath $deps
}
Get-PinnedFile 'https://raw.githubusercontent.com/obsproject/obs-websocket/1ef34bf48110c2a18184e50e41cd0b1a855e2147/lib/obs-websocket-api.h' (Join-Path $vendor 'obs-websocket-api.h') 'C29E8E38EE66C36DB79CAE86217AB0F270AAD39F97E82090809D087C281B7948'

# Create an import library from the installed DLL's real exports. OBS itself
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
set(OBS_RELEASE_CANDIDATE 0)
set(OBS_BETA 0)
configure_file("$sourceCmake/libobs/obsconfig.h.in" "$sdkCmake/obsconfig.h")
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

$build = Join-Path $root "build-vs$major-x64"
& $CMakePath -S $root -B $build -G $generators[$major] -A x64 "-DCMAKE_GENERATOR_INSTANCE=$($vs.installationPath)" "-Dlibobs_DIR=$sdk" "-DOBS_WEBSOCKET_INCLUDE_DIR=$vendor"
if ($LASTEXITCODE) { throw 'CMake configuration failed.' }
& $CMakePath --build $build --config Release
if ($LASTEXITCODE) { throw 'Compilation failed.' }
& $CMakePath --install $build --config Release --prefix (Join-Path $root 'package')
if ($LASTEXITCODE) { throw 'Packaging failed.' }
Write-Host "DLL ready: $root\package\obs-plugins\64bit\obs-targeted-events.dll"
