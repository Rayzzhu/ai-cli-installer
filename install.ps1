#Requires -Version 5.1
$ErrorActionPreference = "Stop"

$Version = "1.0.0"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TemplateDir = Join-Path $ScriptDir "templates"

$QwenOssBat = if ($env:AI_CLI_QWEN_INSTALL_URL) { $env:AI_CLI_QWEN_INSTALL_URL } else {
    "https://qwen-code-assets.oss-cn-hangzhou.aliyuncs.com/installation/install-qwen.bat"
}
$NpmMirror = if ($env:AI_CLI_NPM_REGISTRY) { $env:AI_CLI_NPM_REGISTRY } else { "https://registry.npmmirror.com" }
$NpmOfficial = "https://registry.npmjs.org"
$OpencodeInstall = "https://opencode.ai/install"
$script:LastInstallSource = ""

function Write-Log([string]$Msg) {
    Write-Host ("[{0}] {1}" -f (Get-Date -Format "HH:mm:ss"), $Msg)
}

function Test-Command([string]$Name) {
    $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Backup-IfExists([string]$Path) {
    if (Test-Path $Path) {
        $bak = "$Path.bak." + (Get-Date -Format "yyyyMMddHHmmss")
        Copy-Item $Path $bak
        Write-Log "Backed up: $Path"
    }
}

function Invoke-WithRetry([scriptblock]$Block, [int]$Max = 2) {
    for ($i = 1; $i -le $Max; $i++) {
        try { & $Block; return } catch {
            Write-Log "Retry $i/$Max : $($_.Exception.Message)"
            Start-Sleep -Seconds 3
        }
    }
    throw "Operation failed after $Max attempts"
}

function Install-QwenOss {
    Write-Log "Installing Qwen Code via OSS bat..."
    $tmp = Join-Path $env:TEMP "install-qwen.bat"
    Invoke-WithRetry {
        Invoke-WebRequest -Uri $QwenOssBat -OutFile $tmp -UseBasicParsing -TimeoutSec 30
        & cmd /c $tmp
    }
    $script:LastInstallSource = "qwen-oss:$QwenOssBat"
}

function Install-NpmGlobal([string]$Package, [string]$Registry) {
    if (-not (Test-Command "npm")) { throw "npm not found" }
    Invoke-WithRetry {
        & npm install -g $Package --registry=$Registry
    }
}

function Install-Qwen([string]$Net) {
    switch ($Net) {
        "1" {
            try { Install-QwenOss; return } catch { Write-Log "OSS failed: $_" }
            Install-NpmGlobal "@qwen-code/qwen-code@latest" $NpmMirror
            $script:LastInstallSource = "qwen-npm:$NpmMirror"
        }
        "2" {
            try { Install-QwenOss; return } catch { Write-Log "OSS failed: $_" }
            Install-NpmGlobal "@qwen-code/qwen-code@latest" $NpmOfficial
            $script:LastInstallSource = "qwen-npm:$NpmOfficial"
        }
        "3" {
            if (-not $env:AI_CLI_QWEN_INSTALL_URL) { throw "Set AI_CLI_QWEN_INSTALL_URL" }
            Install-QwenOss
        }
        default { throw "Invalid network" }
    }
}

function Install-Opencode([string]$Net) {
    switch ($Net) {
        "1" {
            if (Test-Command "npm") {
                try {
                    Install-NpmGlobal "opencode-ai@latest" $NpmMirror
                    $script:LastInstallSource = "opencode-npm:$NpmMirror"
                    return
                } catch { Write-Log "npm mirror failed: $_" }
            }
            $tmp = Join-Path $env:TEMP "opencode-install.sh"
            Invoke-WebRequest -Uri $OpencodeInstall -OutFile $tmp -UseBasicParsing -TimeoutSec 30
            bash $tmp
            $script:LastInstallSource = "opencode-curl:$OpencodeInstall"
        }
        "2" {
            Install-NpmGlobal "opencode-ai@latest" $NpmOfficial
            $script:LastInstallSource = "opencode-npm:$NpmOfficial"
        }
        "3" {
            $reg = if ($env:AI_CLI_NPM_REGISTRY) { $env:AI_CLI_NPM_REGISTRY } else { $NpmMirror }
            Install-NpmGlobal "opencode-ai@latest" $reg
            $script:LastInstallSource = "opencode-npm:$reg"
        }
    }
}

function Setup-QwenConfig([string]$Key) {
    $cfgDir = Join-Path $env:USERPROFILE ".qwen"
    New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
    $settings = Join-Path $cfgDir "settings.json"
    $envFile = Join-Path $cfgDir ".env"
    Backup-IfExists $settings
    Backup-IfExists $envFile
    Copy-Item (Join-Path $TemplateDir "qwen-settings.json") $settings -Force
    Set-Content -Path $envFile -Value "DASHSCOPE_API_KEY=$Key" -NoNewline
    Write-Log "Qwen config: $settings $envFile"
}

function Setup-OpencodeConfig([string]$Key, [string]$Provider = "openai") {
    $cfgDir = Join-Path $env:USERPROFILE ".config\opencode"
    New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null
    $cfg = Join-Path $cfgDir "opencode.json"
    $envFile = Join-Path $cfgDir ".env"
    Backup-IfExists $cfg
    Backup-IfExists $envFile
    Copy-Item (Join-Path $TemplateDir "opencode.json") $cfg -Force
    $envKey = switch ($Provider) {
        "anthropic" { "ANTHROPIC_API_KEY" }
        "dashscope" { "DASHSCOPE_API_KEY" }
        default     { "OPENAI_API_KEY" }
    }
    Set-Content -Path $envFile -Value "${envKey}=$Key" -NoNewline
    [Environment]::SetEnvironmentVariable($envKey, $Key, "User")
    Write-Log "OpenCode config: $cfg ($envKey set in user env)"
}

function Read-Secret([string]$Prompt) {
    $sec = Read-Host $Prompt -AsSecureString
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

Write-Host ""
Write-Host "AI CLI Installer v$Version"
Write-Host ""
Write-Host "Network:"
Write-Host "  1) Domestic mirror (default)"
Write-Host "  2) Official source"
Write-Host "  3) Corporate"
$net = Read-Host "Select [1]"
if (-not $net) { $net = "1" }

Write-Host ""
Write-Host "Tool:"
Write-Host "  1) OpenCode"
Write-Host "  2) Qwen Code"
$tool = Read-Host "Select [1]"
if (-not $tool) { $tool = "1" }

$cli = if ($tool -eq "2") { "qwen" } else { "opencode" }

if (Test-Command $cli) {
    Write-Host "$cli already installed."
    Write-Host "  1) Reinstall  2) Config only  3) Exit"
    $act = Read-Host "Select [2]"
    if (-not $act) { $act = "2" }
    if ($act -eq "3") { exit 0 }
    $skipInstall = ($act -eq "2")
} else { $skipInstall = $false }

if (-not $skipInstall) {
    if ($tool -eq "2") { Install-Qwen $net } else { Install-Opencode $net }
    if (-not (Test-Command $cli)) { throw "$cli not in PATH" }
} else {
    $script:LastInstallSource = "skipped"
}

$key = Read-Secret "Enter API Key"
if (-not $key) { throw "API Key empty" }

if ($tool -eq "2") {
    Setup-QwenConfig $key
    Write-Host "Verify: qwen --version"
} else {
    Write-Host "Provider: 1) openai 2) anthropic 3) dashscope"
    $p = Read-Host "Select [1]"
    $prov = switch ($p) { "2" { "anthropic" } "3" { "dashscope" } default { "openai" } }
    Setup-OpencodeConfig $key $prov
    Write-Host "Verify: opencode --version"
}

Write-Host ""
Write-Host "Source: $script:LastInstallSource"
Write-Host "Done."
