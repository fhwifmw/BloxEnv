$ErrorActionPreference = "Stop"

$RepoUrl = if ($env:BLOXENV_REPO_URL) { $env:BLOXENV_REPO_URL } else { "https://github.com/fhwifmw/BloxEnv.git" }
$Ref = if ($env:BLOXENV_REF) { $env:BLOXENV_REF } else { "main" }
$InstallDir = if ($env:BLOXENV_INSTALL_DIR) { $env:BLOXENV_INSTALL_DIR } else { Join-Path $env:LOCALAPPDATA "BloxEnv\bin" }

foreach ($Command in @("git", "cmake")) {
    if (-not (Get-Command $Command -ErrorAction SilentlyContinue)) {
        throw "BloxEnv installer: $Command is required and was not found on PATH."
    }
}

$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("BloxEnv-" + [guid]::NewGuid().ToString("N"))
$SourceDir = Join-Path $TempDir "BloxEnv"
$BuildDir = Join-Path $SourceDir "build"

try {
    Write-Host "Downloading BloxEnv..."
    git clone --quiet --depth 1 --branch $Ref $RepoUrl $SourceDir
    if ($LASTEXITCODE -ne 0) { throw "git clone failed" }

    Write-Host "Building BloxEnv..."
    cmake -S $SourceDir -B $BuildDir
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }

    cmake --build $BuildDir --config Release --target bloxenv --parallel
    if ($LASTEXITCODE -ne 0) { throw "BloxEnv build failed" }

    $Candidates = @(
        (Join-Path $BuildDir "Release\bloxenv.exe"),
        (Join-Path $BuildDir "bloxenv.exe")
    )
    $Binary = $Candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $Binary) { throw "Build completed but bloxenv.exe was not found" }

    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    $InstalledBinary = Join-Path $InstallDir "bloxenv.exe"
    Copy-Item -Force $Binary $InstalledBinary

    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $PathEntries = @($UserPath -split ";" | Where-Object { $_ })
    if ($PathEntries -notcontains $InstallDir) {
        $NewUserPath = (($PathEntries + $InstallDir) -join ";")
        [Environment]::SetEnvironmentVariable("Path", $NewUserPath, "User")
    }
    $env:Path = "$InstallDir;$env:Path"

    & $InstalledBinary --version
    Write-Host ""
    Write-Host "Installed to $InstalledBinary"
    Write-Host "Open a new PowerShell window, then run: bloxenv path\to\script.luau"
}
finally {
    if (Test-Path $TempDir) {
        Remove-Item -Recurse -Force $TempDir
    }
}
