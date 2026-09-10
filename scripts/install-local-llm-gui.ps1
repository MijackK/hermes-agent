# ============================================================================
# Hermes Agent + Local LLM Installer GUI (Windows)
# ============================================================================
# A WPF front-end that runs scripts/install-with-local-llm.ps1 in a child
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
        Width="920" Height="700"
        MinWidth="720" MinHeight="540"
        WindowStartupLocation="CenterScreen"
        Background="#FFF3F4F6"
        FontFamily="Segoe UI" FontSize="13">
  <Window.Resources>

    <Style x:Key="PrimaryButton" TargetType="Button">
      <Setter Property="Background" Value="#FF6366F1"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="Padding" Value="20,9"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#FF818CF8"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="b" Property="Background" Value="#FF4F46E5"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="b" Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="SecondaryButton" TargetType="Button">
      <Setter Property="Background" Value="White"/>
      <Setter Property="Foreground" Value="#FF374151"/>
      <Setter Property="Padding" Value="16,9"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="BorderBrush" Value="#FFD1D5DB"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#FFF9FAFB"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="b" Property="Opacity" Value="0.45"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="GhostButton" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="#FF6B7280"/>
      <Setter Property="Padding" Value="12,9"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="b" Background="{TemplateBinding Background}" CornerRadius="8">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="#FFE5E7EB"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="FieldLabel" TargetType="TextBlock">
      <Setter Property="Foreground" Value="#FF374151"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
    </Style>

    <Style x:Key="Field" TargetType="TextBox">
      <Setter Property="Padding" Value="9,7"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="BorderBrush" Value="#FFD1D5DB"/>
      <Setter Property="BorderThickness" Value="1"/>
    </Style>

  </Window.Resources>

  <Grid Margin="26">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Header -->
    <StackPanel Grid.Row="0" Margin="0,0,0,18">
      <StackPanel Orientation="Horizontal">
        <Border Background="#FF6366F1" CornerRadius="6" Width="6" Height="26" Margin="0,0,10,0" VerticalAlignment="Center"/>
        <TextBlock Text="Hermes · Local LLM Installer" FontSize="22" FontWeight="SemiBold" Foreground="#FF111827" VerticalAlignment="Center"/>
      </StackPanel>
      <TextBlock Text="Install Hermes and point it at a local OpenAI-compatible endpoint (Ollama, LM Studio, vLLM, llama.cpp …)."
                 FontSize="12" Foreground="#FF6B7280" TextWrapping="Wrap" Margin="16,6,0,0"/>
    </StackPanel>

    <!-- Options card -->
    <Border Grid.Row="1" Background="White" CornerRadius="12" Padding="20" Margin="0,0,0,16">
      <Border.Effect>
        <DropShadowEffect BlurRadius="14" ShadowDepth="2" Opacity="0.06" Color="#000000"/>
      </Border.Effect>
      <StackPanel>
        <TextBlock Text="Options" FontSize="14" FontWeight="SemiBold" Foreground="#FF111827" Margin="0,0,0,12"/>
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="Auto"/>
            <ColumnDefinition Width="*"/>
          </Grid.ColumnDefinitions>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <TextBlock Text="Model" Grid.Row="0" Grid.Column="0" Style="{StaticResource FieldLabel}" Margin="0,0,14,10"/>
          <TextBox x:Name="ModelBox" Grid.Row="0" Grid.Column="1" Style="{StaticResource Field}" Margin="0,0,0,10"/>
          <TextBlock Text="Base URL" Grid.Row="1" Grid.Column="0" Style="{StaticResource FieldLabel}" Margin="0,0,14,0"/>
          <TextBox x:Name="BaseUrlBox" Grid.Row="1" Grid.Column="1" Style="{StaticResource Field}"/>
        </Grid>
        <StackPanel Orientation="Horizontal" Margin="0,16,0,0">
          <CheckBox x:Name="SkipInstallBox" Content="Skip Hermes install" Margin="0,0,22,0" Foreground="#FF374151"/>
          <CheckBox x:Name="SkipOllamaBox" Content="Skip Ollama" Margin="0,0,22,0" Foreground="#FF374151"/>
          <CheckBox x:Name="IncludeDesktopBox" Content="Build desktop app" IsChecked="True" Margin="0,0,22,0" Foreground="#FF374151"/>
          <CheckBox x:Name="OpenDesktopBox" Content="Open desktop when done" Foreground="#FF374151"/>
        </StackPanel>
      </StackPanel>
    </Border>

    <!-- Actions -->
    <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,0,0,14">
      <Button x:Name="RunButton" Content="Install" Style="{StaticResource PrimaryButton}" MinWidth="120" Height="38"/>
      <Button x:Name="CancelButton" Content="Cancel" Style="{StaticResource SecondaryButton}" MinWidth="90" Height="38" Margin="10,0,0,0" IsEnabled="False"/>
      <Button x:Name="ClearButton" Content="Clear log" Style="{StaticResource GhostButton}" MinWidth="90" Height="38" Margin="10,0,0,0"/>
    </StackPanel>

    <!-- Log pane -->
    <Border Grid.Row="3" Background="#FF1E1E2E" CornerRadius="10" Padding="2">
      <TextBox x:Name="LogBox"
               IsReadOnly="True"
               AcceptsReturn="True"
               TextWrapping="NoWrap"
               VerticalScrollBarVisibility="Auto"
               HorizontalScrollBarVisibility="Auto"
               Background="Transparent"
               BorderThickness="0"
               Foreground="#FFD4D4D4"
               FontFamily="Consolas"
               FontSize="12"
               Padding="12"/>
    </Border>

    <!-- Status -->
    <Grid Grid.Row="4" Margin="0,12,0,0">
      <TextBlock x:Name="StatusText" Text="Ready" Foreground="#FF6B7280" FontSize="12" VerticalAlignment="Center"/>
      <ProgressBar x:Name="ProgressBar" Width="140" Height="4" IsIndeterminate="True"
                   Foreground="#FF6366F1" Background="#FFE5E7EB"
                   HorizontalAlignment="Right" VerticalAlignment="Center"
                   Visibility="Collapsed"/>
    </Grid>
  </Grid>
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
$script:clearButton       = $window.FindName("ClearButton")
$script:logBox            = $window.FindName("LogBox")
$script:statusText        = $window.FindName("StatusText")
$script:progressBar       = $window.FindName("ProgressBar")

$script:modelBox.Text   = "llama3.2:3b"
$script:baseUrlBox.Text = "http://localhost:11434/v1"

$script:process = $null

# --- UI-thread marshalling helpers -------------------------------------------------
# NOTE: values are passed as delegate ARGUMENTS (never referenced via a closure),
# and controls are referenced via $script:. PowerShell scriptblocks use dynamic
# scoping, not lexical closures, so a [Action]{ $local } would resolve $local to
# $null when the delegate fires -- the original "exits when I click Install" bug.

function Append-Log([string]$Text) {
    if ($script:logBox.Dispatcher.CheckAccess()) {
        $script:logBox.AppendText($Text)
        $script:logBox.ScrollToEnd()
    } else {
        $script:logBox.Dispatcher.Invoke(
            [Action[string]]{ param($t) $script:logBox.AppendText($t); $script:logBox.ScrollToEnd() },
            $Text)
    }
}

function Set-Status([string]$Text) {
    if ($script:statusText.Dispatcher.CheckAccess()) {
        $script:statusText.Text = $Text
    } else {
        $script:statusText.Dispatcher.Invoke(
            [Action[string]]{ param($t) $script:statusText.Text = $t },
            $Text)
    }
}

function Set-RunningState([bool]$Running) {
    if ($script:runButton.Dispatcher.CheckAccess()) {
        $script:runButton.IsEnabled = -not $Running
        $script:cancelButton.IsEnabled = $Running
        $script:progressBar.Visibility = if ($Running) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
    } else {
        $script:runButton.Dispatcher.Invoke(
            [Action[bool]]{ param($r)
                $script:runButton.IsEnabled = -not $r
                $script:cancelButton.IsEnabled = $r
                $script:progressBar.Visibility = if ($r) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
            },
            $Running)
    }
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

# --- Run button --------------------------------------------------------------------
$script:runButton.Add_Click({
    try {
        if ($script:process -and -not $script:process.HasExited) { return }

        $script:logBox.Clear()
        Set-Status "Starting..."
        Set-RunningState $true

        $installer = $null
        try {
            $installer = Resolve-InstallerScript
        } catch {
            Append-Log "ERROR: $($_.Exception.Message)`r`n"
            Set-Status "Failed"
            Set-RunningState $false
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
            try { if ($e.Data) { Append-Log ($e.Data + "`r`n") } } catch {}
        })
        $script:process.add_ErrorDataReceived({
            param($s, $e)
            try { if ($e.Data) { Append-Log ($e.Data + "`r`n") } } catch {}
        })
        $script:process.add_Exited({
            try {
                $code = $script:process.ExitCode
                Append-Log ("`r`n=== Process exited (code $code) ===`r`n")
                if ($code -eq 0) { Set-Status "Install finished successfully" } else { Set-Status "Install finished with exit code $code" }
                Set-RunningState $false
                $script:process.Dispose()
                $script:process = $null
            } catch {
                try { Append-Log ("ERROR in exit handler: $($_.Exception.Message)`r`n") } catch {}
            }
        })

        try {
            $script:process.Start() | Out-Null
            $script:process.BeginOutputReadLine()
            $script:process.BeginErrorReadLine()
        } catch {
            Append-Log "ERROR: could not start installer: $($_.Exception.Message)`r`n"
            Set-Status "Failed to start"
            Set-RunningState $false
            $script:process = $null
        }
    } catch {
        try { Append-Log "ERROR: $($_.Exception.Message)`r`n" } catch {}
        try { Set-Status "Failed" } catch {}
        try { Set-RunningState $false } catch {}
    }
})

# --- Cancel / Clear / Closing ------------------------------------------------------
$script:cancelButton.Add_Click({
    if ($script:process -and -not $script:process.HasExited) {
        Set-Status "Cancelling..."
        Stop-RunningProcess
        Append-Log "`r`n=== Cancelled by user ===`r`n"
    }
})

$script:clearButton.Add_Click({
    $script:logBox.Clear()
})

$window.Add_Closing({
    Stop-RunningProcess
})

$window.ShowDialog() | Out-Null
