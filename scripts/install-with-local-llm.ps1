# ============================================================================
# Hermes Agent + Local LLM bootstrap (Windows)
# ============================================================================
# Runs the stock Hermes installer, then points Hermes at a local OpenAI-
# compatible endpoint (Ollama, LM Studio, vLLM, llama.cpp server, ...).
#
# Hermes never downloads or serves the model itself -- this script optionally
# installs/pulls via Ollama, but the ONLY thing Hermes needs is a reachable
# base_url. If you use LM Studio / vLLM / anything else, just pass -BaseUrl
# and -Model and skip the Ollama bits with -SkipOllama.
#
# Examples:
#   # Ollama, default model, default endpoint:
#   .\install-with-local-llm.ps1
#
#   # Ollama, specific model:
#   .\install-with-local-llm.ps1 -Model qwen2.5:14b
#
#   # LM Studio (server already running on :1234), no Ollama install:
#   .\install-with-local-llm.ps1 -SkipOllama -BaseUrl http://localhost:1234/v1 -Model my-loaded-model
#
#   # Skip the Hermes install (already installed), just (re)configure:
#   .\install-with-local-llm.ps1 -SkipInstall -Model qwen2.5:14b
#
#   # Install + configure, then open the Hermes Desktop app:
#   .\install-with-local-llm.ps1 -OpenDesktop
# ============================================================================

[CmdletBinding()]
param(
    # Model id exactly as your backend serves it (Ollama tag, LM Studio id, ...).
    [string]$Model = "llama3.2:3b",

    # OpenAI-compatible base URL of the local server.
    [string]$BaseUrl = "http://localhost:11434/v1",

    # Skip installing Hermes (use when it is already installed).
    [switch]$SkipInstall,

    # Skip installing Ollama AND pulling the model (non-Ollama backends).
    [switch]$SkipOllama,

    # Path to the stock installer. Defaults to the copy beside this script.
    [string]$InstallScript = (Join-Path $PSScriptRoot "install.ps1"),

    # Extra args forwarded verbatim to install.ps1 (e.g. -Branch dev -NoVenv).
    [string[]]$InstallArgs = @(),

    # Launch the Hermes Desktop (Electron) app when done.
    [switch]$OpenDesktop
)

$ErrorActionPreference = "Stop"

function Write-Step([string]$Msg)  { Write-Host "`n==> $Msg" -ForegroundColor Cyan }
function Write-Ok([string]$Msg)    { Write-Host "[OK] $Msg" -ForegroundColor Green }
function Write-Warn2([string]$Msg) { Write-Host "[!]  $Msg" -ForegroundColor Yellow }

# ---------------------------------------------------------------------------
# Step 1: Install Hermes (skip its interactive setup wizard; we configure below)
# ---------------------------------------------------------------------------
if (-not $SkipInstall) {
    if (-not (Test-Path -LiteralPath $InstallScript)) {
        throw "install.ps1 not found at '$InstallScript'. Pass -InstallScript or run from the scripts folder."
    }
    Write-Step "Installing Hermes Agent"
    # -SkipSetup: install.ps1 would otherwise launch the interactive wizard, which
    # cannot be driven non-interactively. We do the model config ourselves below.
    & $InstallScript -SkipSetup @InstallArgs
    if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "install.ps1 exited with code $LASTEXITCODE" }
    Write-Ok "Hermes installed"
} else {
    Write-Step "Skipping Hermes install (-SkipInstall)"
}

# ---------------------------------------------------------------------------
# Step 2: Resolve the `hermes` command
# ---------------------------------------------------------------------------
# install.ps1 puts hermes.exe on the User PATH, but THIS process still has the
# pre-install PATH. Refresh from the registry, then fall back to the well-known
# venv location if the shim still isn't resolvable.
$env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" +
            [Environment]::GetEnvironmentVariable("Path", "Machine")

$hermesCmd = Get-Command hermes -ErrorAction SilentlyContinue
$hermes = if ($hermesCmd) { $hermesCmd.Source } else { $null }
if (-not $hermes) {
    $hermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { "$env:LOCALAPPDATA\hermes" }
    $candidate = Join-Path $hermesHome "hermes-agent\venv\Scripts\hermes.exe"
    if (Test-Path -LiteralPath $candidate) { $hermes = $candidate }
}
if (-not $hermes) {
    throw "Could not locate the 'hermes' command. Open a NEW terminal (so PATH refreshes) and re-run with -SkipInstall."
}
Write-Ok "hermes: $hermes"

# ---------------------------------------------------------------------------
# Step 3: Install Ollama + pull the model (optional)
# ---------------------------------------------------------------------------
if (-not $SkipOllama) {
    Write-Step "Ensuring Ollama is installed"
    if (-not (Get-Command ollama -ErrorAction SilentlyContinue)) {
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            winget install --id Ollama.Ollama -e --accept-source-agreements --accept-package-agreements
            # winget shims land on User PATH; refresh so this process sees ollama.
            $env:Path = [Environment]::GetEnvironmentVariable("Path", "User") + ";" +
                        [Environment]::GetEnvironmentVariable("Path", "Machine")
        } else {
            Write-Warn2 "winget not available; install Ollama manually from https://ollama.com and re-run."
        }
    }
    if (Get-Command ollama -ErrorAction SilentlyContinue) {
        Write-Ok "ollama: $((Get-Command ollama).Source)"

        # Ensure the server is up before pulling / before Hermes hits base_url.
        $serverUp = $false
        try {
            $null = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 2
            $serverUp = $true
        } catch { $serverUp = $false }
        if (-not $serverUp) {
            Write-Step "Starting Ollama server"
            Start-Process -FilePath "ollama" -ArgumentList "serve" -WindowStyle Hidden
            # Give it a moment to bind.
            $deadline = (Get-Date).AddSeconds(15)
            while ((Get-Date) -lt $deadline) {
                try { $null = Invoke-RestMethod -Uri "http://localhost:11434/api/tags" -TimeoutSec 2; break }
                catch { Start-Sleep -Milliseconds 500 }
            }
        }

        Write-Step "Pulling model '$Model' (this can be large)"
        & ollama pull $Model
        if ($LASTEXITCODE -ne 0) { Write-Warn2 "ollama pull exited $LASTEXITCODE -- verify the tag with 'ollama search' / ollama.com" }
        else { Write-Ok "Model '$Model' ready" }
    }
} else {
    Write-Step "Skipping Ollama install/pull (-SkipOllama)"
}

# ---------------------------------------------------------------------------
# Step 4: Point Hermes at the local endpoint
# ---------------------------------------------------------------------------
# The model section is a dict: model.default (id), model.provider, model.base_url.
# `custom` = OpenAI-compatible endpoint (Ollama / LM Studio / vLLM / llama.cpp).
Write-Step "Configuring Hermes to use the local model"
& $hermes config set model.provider custom | Out-Null
& $hermes config set model.base_url $BaseUrl | Out-Null
& $hermes config set model.default $Model | Out-Null
if ($LASTEXITCODE -ne 0) { throw "hermes config set failed (exit $LASTEXITCODE)" }

Write-Host ""
Write-Ok "Done. Hermes is configured for a local LLM:"
Write-Host "    provider : custom"
Write-Host "    base_url : $BaseUrl"
Write-Host "    model    : $Model"
Write-Host ""

# ---------------------------------------------------------------------------
# Step 5: Optionally launch Hermes Desktop (Electron)
# ---------------------------------------------------------------------------
# `hermes desktop` builds (first run) and launches the native app. It needs
# Node.js/npm on PATH and will take longer on the first launch while it builds.
if ($OpenDesktop) {
    Write-Step "Launching Hermes Desktop"
    & $hermes desktop
    if ($LASTEXITCODE -ne 0) { Write-Warn2 "hermes desktop exited $LASTEXITCODE" }
}

Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  * Verify:  hermes config get model"
Write-Host "  * Chat:    hermes"
Write-Host "  * Desktop: hermes desktop"
Write-Host "  * Make sure your backend is serving at $BaseUrl before chatting."
