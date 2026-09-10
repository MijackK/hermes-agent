# ============================================================================
# Hermes Agent + Local LLM Installer GUI (Windows)
# ============================================================================
# A small WPF front-end that runs scripts/install-with-local-llm.ps1 in a child
# process and streams its output into a log pane. Packaged into a standalone
# .exe with ps2exe (see .github/workflows/build-installer-exe.yml).
#
# The installer script is downloaded at runtime from the repository (or taken
# from -ScriptPath), so the compiled exe never goes stale when the installer
# changes -- it only needs rebuilding when THIS wrapper changes.
# ============================================================================

[CmdletBinding()]
param(
    # Local path to scripts/install-with-local-llm.ps1. When empty (default),
    # it is downloaded from -ScriptUrl.
    [string]$ScriptPath = "",

    # URL of the installer script to run. Defaults to the canonical raw URL in
    # the shani-agent repository.
    [string]$ScriptUrl = "https://raw.githubusercontent.com/MijackK/shani-agent/main/scripts/install-with-local-llm.ps1"
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Hermes + Local LLM Installer"
        Width="920" Height="660"
        WindowStartupLocation="CenterScreen"
        FontFamily="Segoe UI" FontSize="12">
  <DockPanel Margin="12">
    <StackPanel DockPanel.Dock="Bottom" Margin="0,8,0,0">
      <TextBlock x:Name="StatusText" Text="Ready" Foreground="#FF6B6B6B"/>
    </StackPanel>

    <StackPanel DockPanel.Dock="Top" Margin="0,0,0,8">
      <TextBlock Text="Options" FontWeight="Bold" Margin="0,0,0,6"/>
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <TextBlock Text="Model:" Grid.Row="0" Grid.Column="0" VerticalAlignment="Center" Margin="0,0,8,4"/>
        <TextBox x:Name="ModelBox" Grid.Row="0" Grid.Column="1" Margin="0,0,0,4"/>
        <TextBlock Text="Base URL:" Grid.Row="1" Grid.Column="0" VerticalAlignment="Center" Margin="0,0,8,0"/>
        <TextBox x:Name="BaseUrlBox" Grid.Row="1" Grid.Column="1"/>
      </Grid>
      <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
        <CheckBox x:Name="SkipInstallBox" Content="Skip Hermes install" Margin="0,0,16,0"/>
        <CheckBox x:Name="SkipOllamaBox" Content="Skip Ollama" Margin="0,0,16,0"/>
        <CheckBox x:Name="IncludeDesktopBox" Content="Build desktop app" IsChecked="True" Margin="0,0,16,0"/>
        <CheckBox x:Name="OpenDesktopBox" Content="Open desktop when done" Margin="0,0,16,0"/>
      </StackPanel>
      <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
        <Button x:Name="RunButton" Content="Run Install" Width="110" Height="30" Margin="0,0,8,0" IsDefault="True"/>
        <Button x:Name="CancelButton" Content="Cancel" Width="80" Height="30" IsEnabled="False"/>
      </StackPanel>
    </StackPanel>

    <TextBox x:Name="LogBox"
             IsReadOnly="True"
             AcceptsReturn="True"
             TextWrapping="NoWrap"
             VerticalScrollBarVisibility="Auto"
             HorizontalScrollBarVisibility="Auto"
             FontFamily="Consolas"
             FontSize="12"
             Background="#FF1E1E1E"
             Foreground="#FFD4D4D4"/>
  </DockPanel>
</Window>
'@

$window = [System.Windows.Markup.XamlReader]::Parse($xaml)

$script:modelBox          = $window.FindName("ModelBox")
$script:baseUrlBox        = $window.FindName("BaseUrlBox")
$script:skipInstallBox    = $window.FindName("SkipInstallBox")
$script:skipOllamaBox     = $window.FindName("SkipOllamaBox")
$script:includeDesktopBox = $window.FindName("IncludeDesktopBox")
$script:openDesktopBox    = $window.FindName("OpenDesktopBox")
$script:runButton         = $window.FindName("RunButton")
$script:cancelButton      = $window.FindName("CancelButton")
$script:logBox            = $window.FindName("LogBox")
$script:statusText        = $window.FindName("StatusText")

$script:modelBox.Text   = "llama3.2:3b"
$script:baseUrlBox.Text = "http://localhost:11434/v1"

$script:process = $null

function Append-Log([string]$Text) {
    $action = [Action]{ $script:logBox.AppendText($Text); $script:logBox.ScrollToEnd() }
    if ($script:logBox.Dispatcher.CheckAccess()) { $action.Invoke() }
    else { $script:logBox.Dispatcher.Invoke($action) }
}

function Set-Status([string]$Text) {
    $action = [Action]{ $script:statusText.Text = $Text }
    if ($script:statusText.Dispatcher.CheckAccess()) { $action.Invoke() }
    else { $script:statusText.Dispatcher.Invoke($action) }
}

function Stop-RunningProcess {
    if ($script:process -and -not $script:process.HasExited) {
        try { & taskkill /PID $script:process.Id /T /F 2>$null | Out-Null } catch {}
    }
}

function Resolve-InstallerScript {
    if ($ScriptPath -and (Test-Path -LiteralPath $ScriptPath)) {
        Append-Log "Using local installer: $ScriptPath`r`n"
        return $ScriptPath
    }
    $ProgressPreference = "SilentlyContinue"
    try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}
    $tmp = Join-Path $env:TEMP ("hermes-install-llm-" + [Guid]::NewGuid().ToString("N") + ".ps1")
    Append-Log "Downloading installer from $ScriptUrl ...`r`n"
    Invoke-WebRequest -Uri $ScriptUrl -OutFile $tmp -UseBasicParsing
    if (-not (Test-Path -LiteralPath $tmp)) { throw "Failed to download $ScriptUrl" }
    return $tmp
}

$script:runButton.Add_Click({
    if ($script:process -and -not $script:process.HasExited) { return }

    $script:logBox.Clear()
    Set-Status "Starting..."
    $script:runButton.IsEnabled = $false
    $script:cancelButton.IsEnabled = $true

    $installer = $null
    try {
        $installer = Resolve-InstallerScript
    } catch {
        Append-Log "ERROR: $($_.Exception.Message)`r`n"
        Set-Status "Failed"
        $script:runButton.IsEnabled = $true
        $script:cancelButton.IsEnabled = $false
        return
    }

    $argList = [System.Collections.Generic.List[string]]::new()
    $argList.Add("-Model");     $argList.Add($script:modelBox.Text)
    $argList.Add("-BaseUrl");   $argList.Add($script:baseUrlBox.Text)
    if ($script:skipInstallBox.IsChecked)    { $argList.Add("-SkipInstall") }
    if ($script:skipOllamaBox.IsChecked)     { $argList.Add("-SkipOllama") }
    if ($script:openDesktopBox.IsChecked)    { $argList.Add("-OpenDesktop") }
    if (-not $script:includeDesktopBox.IsChecked) { $argList.Add("-IncludeDesktop:`$false") }

    $quoted = $argList | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }
    $escapedPath = $installer -replace "'", "''"
    $prelude = "`$ProgressPreference='SilentlyContinue'; [Console]::OutputEncoding=[System.Text.UTF8Encoding]::new(); "
    $inner   = "& '$escapedPath' $($quoted -join ' ') *>&1"
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($prelude + $inner))

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName               = "powershell.exe"
    $psi.Arguments              = "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"
    $psi.UseShellExecute        = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow         = $true
    $psi.StandardOutputEncoding = New-Object System.Text.UTF8Encoding $false
    $psi.StandardErrorEncoding  = New-Object System.Text.UTF8Encoding $false

    $script:process = New-Object System.Diagnostics.Process
    $script:process.StartInfo = $psi
    $script:process.EnableRaisingEvents = $true

    $script:process.add_OutputDataReceived({
        param($s, $e)
        if ($e.Data) { Append-Log ($e.Data + "`r`n") }
    })
    $script:process.add_ErrorDataReceived({
        param($s, $e)
        if ($e.Data) { Append-Log ($e.Data + "`r`n") }
    })
    $script:process.add_Exited({
        param($s, $e)
        $code = $script:process.ExitCode
        $script:runButton.Dispatcher.Invoke([Action]{
            Append-Log ("`r`n=== Process exited (code $code) ===`r`n")
            if ($code -eq 0) { Set-Status "Finished successfully" } else { Set-Status "Finished with exit code $code" }
            $script:runButton.IsEnabled = $true
            $script:cancelButton.IsEnabled = $false
            $script:process.Dispose()
            $script:process = $null
        })
    })

    try {
        $script:process.Start() | Out-Null
        $script:process.BeginOutputReadLine()
        $script:process.BeginErrorReadLine()
    } catch {
        Append-Log "ERROR: could not start installer: $($_.Exception.Message)`r`n"
        Set-Status "Failed to start"
        $script:runButton.IsEnabled = $true
        $script:cancelButton.IsEnabled = $false
        $script:process = $null
    }
})

$script:cancelButton.Add_Click({
    if ($script:process -and -not $script:process.HasExited) {
        Set-Status "Cancelling..."
        Stop-RunningProcess
        Append-Log "`r`n=== Cancelled by user ===`r`n"
    }
})

$window.Add_Closing({
    Stop-RunningProcess
})

$window.ShowDialog() | Out-Null
