<#
    iperf3-nat GUI  --  a jperf-style front-end for iperf3-nat
    ----------------------------------------------------------
    A dependency-free WPF front-end (Windows PowerShell / WPF) that drives
    iperf3.exe, exposes the common command-line options as controls, and draws a
    real-time throughput graph by parsing iperf3's --json-stream output.

    Launch via iperf3-gui.cmd (which starts Windows PowerShell in STA mode), or:
        powershell.exe -STA -ExecutionPolicy Bypass -File iperf3-gui.ps1

    The script locates iperf3.exe automatically (same folder, ../src, or the
    dist/ build); use the Browse button to point at a specific binary.

    Server mode can optionally auto-forward its port on the router via UPnP IGD
    (the built-in Windows HNetCfg.NATUPnP COM API - no extra dependency), so a
    server behind NAT can become reachable without a manual port-forward. The
    mapping is removed again when the server is stopped or the GUI closes.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Windows.Forms

# ---------------------------------------------------------------------------
# Locate iperf3.exe
# ---------------------------------------------------------------------------
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
function Find-Iperf {
    $candidates = @(
        (Join-Path $scriptDir 'iperf3.exe'),
        (Join-Path $scriptDir '..\src\iperf3.exe'),
        (Join-Path $scriptDir '..\dist\iperf3-nat-windows\iperf3.exe')
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) { return (Resolve-Path $c).Path }
    }
    return $null
}
$script:IperfPath = Find-Iperf

# ---------------------------------------------------------------------------
# XAML UI
# ---------------------------------------------------------------------------
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="iperf3-nat GUI" Height="820" Width="980"
        WindowStartupLocation="CenterScreen" Background="#1e1e2a">
  <Window.Resources>
    <Style TargetType="Label">
      <Setter Property="Foreground" Value="#d0d0e0"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Padding" Value="2,0,4,0"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="#d0d0e0"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Margin" Value="4,0,10,0"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="VerticalContentAlignment" Value="Center"/>
      <Setter Property="Height" Value="24"/>
      <Setter Property="Background" Value="#2c2c3c"/>
      <Setter Property="Foreground" Value="#f0f0f8"/>
      <Setter Property="BorderBrush" Value="#454560"/>
      <Setter Property="CaretBrush" Value="#f0f0f8"/>
    </Style>
    <Style TargetType="RadioButton">
      <Setter Property="Foreground" Value="#d0d0e0"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Margin" Value="4,0,10,0"/>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Height" Value="24"/>
    </Style>
  </Window.Resources>

  <Grid Margin="10">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Row 0: options panel -->
    <Border Grid.Row="0" Background="#26263440" BorderBrush="#3a3a52" BorderThickness="1"
            CornerRadius="4" Padding="8" Margin="0,0,0,6">
      <StackPanel>

        <!-- Common (applies to both roles) -->
        <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
          <Label Content="Mode:"/>
          <RadioButton x:Name="rbClient" Content="Client" IsChecked="True" GroupName="role"/>
          <RadioButton x:Name="rbServer" Content="Server" GroupName="role"/>
          <Label Content="Port:" Margin="16,0,0,0"/>
          <TextBox x:Name="txtPort" Width="70" Text="5201"/>
          <Label Content="Interval (-i):" Margin="16,0,0,0"/>
          <TextBox x:Name="txtInterval" Width="45" Text="1"/>
          <Label Content="s"/>
          <CheckBox x:Name="chkNat" Content="NAT (--nat)" IsChecked="True" Margin="16,0,0,0"/>
        </StackPanel>

        <!-- Client-only options (disabled in Server mode) -->
        <Border x:Name="grpClient" BorderBrush="#3a4a6a" BorderThickness="1" CornerRadius="4" Padding="6,4" Margin="0,2,0,2">
          <StackPanel>
            <TextBlock Text="CLIENT OPTIONS" Foreground="#6fa8dc" FontSize="10" FontWeight="Bold" Margin="0,0,0,3"/>
            <StackPanel Orientation="Horizontal" Margin="0,0,0,4">
              <Label Content="Host:"/>
              <TextBox x:Name="txtHost" Width="180" Text="127.0.0.1"/>
              <Label Content="Protocol:" Margin="12,0,0,0"/>
              <RadioButton x:Name="rbTcp" Content="TCP" IsChecked="True" GroupName="proto"/>
              <RadioButton x:Name="rbUdp" Content="UDP" GroupName="proto"/>
              <Label Content="Duration (-t):" Margin="12,0,0,0"/>
              <TextBox x:Name="txtTime" Width="45" Text="10"/><Label Content="s"/>
              <Label Content="Streams (-P):" Margin="12,0,0,0"/>
              <TextBox x:Name="txtParallel" Width="40" Text="1"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal">
              <Label Content="Bitrate (-b):"/>
              <TextBox x:Name="txtBitrate" Width="58" Text="" ToolTip="Target rate, e.g. 50M. UDP or capped TCP."/>
              <Label Content="Len (-l):" Margin="10,0,0,0"/>
              <TextBox x:Name="txtLen" Width="58" Text="" ToolTip="Packet/buffer size: UDP datagram or TCP read/write size, e.g. 1400 or 128K"/>
              <Label Content="Window (-w):" Margin="10,0,0,0"/>
              <TextBox x:Name="txtWindow" Width="58" Text=""/>
              <CheckBox x:Name="chkReverse" Content="Reverse (-R)" Margin="12,0,0,0"/>
              <CheckBox x:Name="chkBidir" Content="Bidir (--bidir)"/>
            </StackPanel>
          </StackPanel>
        </Border>

        <!-- Server-only options (disabled in Client mode) -->
        <Border x:Name="grpServer" BorderBrush="#5a4a2a" BorderThickness="1" CornerRadius="4" Padding="6,4" Margin="0,0,0,2">
          <StackPanel>
            <TextBlock Text="SERVER OPTIONS" Foreground="#c6a86f" FontSize="10" FontWeight="Bold" Margin="0,0,0,3"/>
            <StackPanel Orientation="Horizontal">
              <CheckBox x:Name="chkUpnp" Content="Auto-forward (UPnP)" ToolTip="Ask the router to forward this port via UPnP so a server behind NAT is reachable"/>
            </StackPanel>
          </StackPanel>
        </Border>

        <!-- Common: extra args passthrough -->
        <StackPanel Orientation="Horizontal" Margin="0,2,0,0">
          <Label Content="Extra args:"/>
          <TextBox x:Name="txtExtra" Width="420" Text="" ToolTip="Any additional iperf3 flags, passed through verbatim"/>
        </StackPanel>

        <!-- Common: Windows QoS / DSCP marking (applies to whichever side sends) -->
        <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
          <Label Content="Windows QoS - DSCP:"/>
          <TextBox x:Name="txtDscp" Width="60" Text="" ToolTip="DSCP value: EF, CS5, AF11 or 0-63. Passed as --dscp for clients, and used by Apply to create a Windows QoS policy."/>
          <Button x:Name="btnQosApply" Content="Apply policy" Width="90" Height="24" Margin="8,0,0,0"
                  ToolTip="Create a Windows Policy-based QoS rule (needs admin) so iperf3.exe packets are actually DSCP-marked on the wire"/>
          <Button x:Name="btnQosClear" Content="Clear" Width="56" Height="24" Margin="6,0,0,0"
                  ToolTip="Remove the Windows QoS policy created by Apply"/>
          <Label Content="marks iperf3.exe outbound (admin); Windows ignores app-set DSCP without this" Foreground="#8080a0" Margin="8,0,0,0"/>
        </StackPanel>

      </StackPanel>
    </Border>

    <!-- Row 1: iperf path + run/stop -->
    <Grid Grid.Row="1" Margin="0,0,0,6">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <Label Grid.Column="0" Content="iperf3.exe:"/>
      <TextBox Grid.Column="1" x:Name="txtIperf" Margin="0,0,6,0"/>
      <Button Grid.Column="2" x:Name="btnPubIp" Content="Public IP" Width="90" Height="26" Margin="0,0,10,0"
              ToolTip="Look up this machine's internet-visible public IP and copy it to the clipboard"/>
      <Button Grid.Column="3" x:Name="btnBrowse" Content="Browse..." Width="80" Height="26" Margin="0,0,10,0"/>
      <Button Grid.Column="4" x:Name="btnRun" Content="Run" Width="90" Height="26" Margin="0,0,6,0"
              Background="#2e7d32" Foreground="White" FontWeight="Bold"/>
      <Button Grid.Column="5" x:Name="btnStop" Content="Stop" Width="90" Height="26"
              Background="#7d2e2e" Foreground="White" FontWeight="Bold" IsEnabled="False"/>
    </Grid>

    <!-- Row 2: graph -->
    <Border Grid.Row="2" Background="#15151f" BorderBrush="#3a3a52" BorderThickness="1" CornerRadius="4">
      <Canvas x:Name="graph" ClipToBounds="True"/>
    </Border>

    <!-- Row 3: live stats (per direction, filled dynamically) -->
    <Border Grid.Row="3" Background="#26263440" BorderBrush="#3a3a52" BorderThickness="1"
            CornerRadius="4" Padding="8,4" Margin="0,6,0,6" MinHeight="28">
      <StackPanel x:Name="spStats" Orientation="Vertical"/>
    </Border>

    <!-- Row 4: log -->
    <!-- Height set explicitly to override the shared 24px TextBox style (that
         height is meant for the single-line inputs, not this multi-line log). -->
    <TextBox Grid.Row="4" x:Name="txtLog" Margin="0,0,0,6" IsReadOnly="True" Height="240"
             VerticalScrollBarVisibility="Visible" HorizontalScrollBarVisibility="Auto"
             VerticalContentAlignment="Top"
             FontFamily="Consolas" FontSize="13" Background="#15151f" Foreground="#c0c0d0"
             TextWrapping="NoWrap"/>

    <!-- Row 5: status bar -->
    <Grid Grid.Row="5">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <TextBlock Grid.Column="0" x:Name="lblStatus" Foreground="#8080a0" Text="Idle." VerticalAlignment="Center"/>
      <TextBlock Grid.Column="1" x:Name="lblExtra" Foreground="#b0b0c8" Margin="16,0,0,0" VerticalAlignment="Center"/>
      <TextBlock Grid.Column="2" x:Name="lblCmd" Foreground="#606078" VerticalAlignment="Center"
                 FontFamily="Consolas" FontSize="10"/>
    </Grid>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win = [Windows.Markup.XamlReader]::Load($reader)

# Bind named elements to variables
$xaml.SelectNodes("//*[@*[local-name()='Name']]") | ForEach-Object {
    Set-Variable -Name $_.Name -Value $win.FindName($_.Name) -Scope Script
}

$txtIperf.Text = if ($script:IperfPath) { $script:IperfPath } else { '' }

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
$script:proc      = $null
$script:logFile   = $null
$script:bytePos   = 0
$script:buffer    = ''
$script:series    = [ordered]@{}   # direction label (TX/RX) -> series object with its own points/stats
$script:running   = $false
$script:timer     = New-Object System.Windows.Threading.DispatcherTimer
$script:timer.Interval = [TimeSpan]::FromMilliseconds(200)
$script:upnpMappings   = @()      # list of @{Port=;Protocol=} we created on the router
$script:upnpExternalIp = $null    # WAN IP reported by the IGD, if any
$script:qosProc        = $null    # elevated New/Remove-NetQosPolicy process
$script:qosFile        = $null    # temp file the elevated process writes its result to
$script:qosTimer       = $null

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Add-Log([string]$text, [string]$color = '#c0c0d0') {
    $script:txtLog.AppendText($text + "`r`n")
    $script:txtLog.ScrollToEnd()
}

function Format-Rate([double]$mbps) {
    if ($mbps -ge 1000) { return ('{0:N2} Gbit/s' -f ($mbps / 1000)) }
    return ('{0:N1} Mbit/s' -f $mbps)
}

# --- UPnP IGD (router port-forwarding) via the built-in Windows COM API --------
# No external dependency: HNetCfg.NATUPnP ships with Windows. Requires the router
# to have UPnP IGD enabled; if not, we degrade gracefully to a warning.

function Get-LocalIPv4 {
    # Determine the LAN IPv4 of the interface that reaches the default gateway,
    # without sending anything (UDP "connect" only selects the local endpoint).
    try {
        $s = New-Object System.Net.Sockets.Socket(
            [System.Net.Sockets.AddressFamily]::InterNetwork,
            [System.Net.Sockets.SocketType]::Dgram,
            [System.Net.Sockets.ProtocolType]::Udp)
        $s.Connect('8.8.8.8', 65530)
        $ip = ([System.Net.IPEndPoint]$s.LocalEndPoint).Address.ToString()
        $s.Close()
        return $ip
    } catch { return $null }
}

function Add-UpnpMapping {
    param([int]$Port, [string[]]$Protocols, [string]$LocalIP, [string]$Desc)
    $res = [pscustomobject]@{ Ok = $false; External = $null; Mapped = @(); Error = $null }
    $nat = $null
    try { $nat = New-Object -ComObject HNetCfg.NATUPnP }
    catch { $res.Error = "UPnP COM interface unavailable: $($_.Exception.Message)"; return $res }

    $coll = $null
    try { $coll = $nat.StaticPortMappingCollection } catch { }
    if ($null -eq $coll) {
        $res.Error = "no UPnP IGD device found (router UPnP disabled or unsupported)"
        return $res
    }

    $mapped = New-Object System.Collections.Generic.List[object]
    foreach ($proto in $Protocols) {
        try {
            try { $coll.Remove($Port, $proto) } catch { }   # clear any stale mapping
            $m = $coll.Add($Port, $proto, $Port, $LocalIP, $true, $Desc)
            [void]$mapped.Add(@{ Port = $Port; Protocol = $proto })
            if (-not $res.External) { try { $res.External = $m.ExternalIPAddress } catch { } }
        } catch {
            $res.Error = "failed to map $proto/$Port ($($_.Exception.Message))"
        }
    }
    $res.Mapped = $mapped
    $res.Ok = ($mapped.Count -gt 0)
    if ($res.Ok -and -not $res.External) {
        try { foreach ($e in $coll) { if ($e.ExternalIPAddress) { $res.External = $e.ExternalIPAddress; break } } } catch { }
    }
    return $res
}

function Remove-UpnpMappings {
    if (-not $script:upnpMappings -or @($script:upnpMappings).Count -eq 0) { return }
    try {
        $nat  = New-Object -ComObject HNetCfg.NATUPnP
        $coll = $nat.StaticPortMappingCollection
        if ($coll) {
            foreach ($mp in $script:upnpMappings) {
                try { $coll.Remove([int]$mp.Port, [string]$mp.Protocol) } catch { }
            }
            Add-Log ("UPnP: removed router port mapping(s).")
        }
    } catch { }
    $script:upnpMappings   = @()
    $script:upnpExternalIp = $null
}

# --- Public (internet-visible) IP resolution -----------------------------------
# Ask an external echo service what our internet-facing IP is. Works regardless
# of UPnP, as long as outbound HTTPS is allowed. Several endpoints are tried for
# resilience; the first that answers a valid address wins.

function Get-PublicIP {
    $endpoints = @(
        'https://api.ipify.org',
        'https://checkip.amazonaws.com',
        'https://ifconfig.me/ip',
        'https://icanhazip.com'
    )
    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch { }
    foreach ($url in $endpoints) {
        try {
            $resp = Invoke-RestMethod -Uri $url -TimeoutSec 4
            $ip = ("$resp").Trim()
            if ($ip -match '^\d{1,3}(\.\d{1,3}){3}$' -or ($ip -match ':' -and $ip -match '^[0-9a-fA-F:]+$')) {
                return [pscustomobject]@{ Ip = $ip; Source = ([Uri]$url).Host }
            }
        } catch { }
    }
    return $null
}

function Resolve-AndShowPublicIP {
    $r = Get-PublicIP
    if ($r) {
        Add-Log ("Public (internet) IP: {0}   [via {1}]" -f $r.Ip, $r.Source)
        $script:lblExtra.Text = "Public IP: $($r.Ip)"
        return $r.Ip
    }
    Add-Log "Could not resolve public IP (no outbound internet, or the lookup services are blocked)."
    return $null
}

# --- Windows Policy-based QoS (real DSCP marking) ------------------------------
# Windows ignores DSCP that an app sets on its socket, so --dscp alone does not
# mark packets on the wire. A Policy-based QoS rule (applied by the QoS Packet
# Scheduler) does. Creating/removing one needs admin, so we relaunch elevated.

function Convert-Dscp([string]$v) {
    if (-not $v) { return $null }
    $v = $v.Trim().ToUpper()
    $map = @{ 'BE'=0;'CS0'=0;'CS1'=8;'CS2'=16;'CS3'=24;'CS4'=32;'CS5'=40;'CS6'=48;'CS7'=56;
              'AF11'=10;'AF12'=12;'AF13'=14;'AF21'=18;'AF22'=20;'AF23'=22;'AF31'=26;'AF32'=28;'AF33'=30;
              'AF41'=34;'AF42'=36;'AF43'=38;'EF'=46 }
    if ($map.ContainsKey($v)) { return $map[$v] }
    $n = 0
    if ([int]::TryParse($v, [ref]$n) -and $n -ge 0 -and $n -le 63) { return $n }
    return $null
}

function Invoke-QosPolicy([string]$mode) {   # 'apply' or 'clear'
    $name = 'iperf3-nat-gui'
    $resultFile = [IO.Path]::Combine([IO.Path]::GetTempPath(), ("iperf3qos_{0}.txt" -f ([guid]::NewGuid().ToString('N'))))

    if ($mode -eq 'apply') {
        $dscp = Convert-Dscp $txtDscp.Text.Trim()
        if ($null -eq $dscp) {
            [System.Windows.MessageBox]::Show("Enter a DSCP value first (0-63, or a name like EF, CS5, AF11).",
                "iperf3-nat GUI", 'OK', 'Warning') | Out-Null
            return
        }
        $exeName = [IO.Path]::GetFileName($txtIperf.Text.Trim())
        if (-not $exeName) { $exeName = 'iperf3.exe' }
        $inner = "try { Remove-NetQosPolicy -Name '$name' -Confirm:`$false -ErrorAction SilentlyContinue; " +
                 "New-NetQosPolicy -Name '$name' -AppPathNameMatchCondition '$exeName' " +
                 "-IPProtocolMatchCondition Both -DSCPAction $dscp -NetworkProfile All -ErrorAction Stop | Out-Null; " +
                 "'OK: applied DSCP $dscp to $exeName outbound (all network profiles).' } " +
                 "catch { 'ERROR: ' + `$_.Exception.Message } | Set-Content -Path '$resultFile'"
        Add-Log ("QoS: requesting elevation to mark {0} with DSCP {1} ..." -f $exeName, $dscp)
    }
    else {
        $inner = "try { Remove-NetQosPolicy -Name '$name' -Confirm:`$false -ErrorAction Stop; " +
                 "'OK: removed QoS policy.' } catch { 'ERROR: ' + `$_.Exception.Message } | Set-Content -Path '$resultFile'"
        Add-Log "QoS: requesting elevation to remove the QoS policy ..."
    }

    try {
        $proc = Start-Process powershell -Verb RunAs -PassThru -WindowStyle Hidden `
                    -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-Command', $inner
    } catch {
        Add-Log ("QoS: elevation was cancelled or failed ({0})." -f $_.Exception.Message)
        return
    }

    # Poll (on the UI thread) for the elevated process to finish, then report.
    $script:qosProc  = $proc
    $script:qosFile  = $resultFile
    $script:qosTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:qosTimer.Interval = [TimeSpan]::FromMilliseconds(400)
    $script:qosTimer.Add_Tick({
        if ($script:qosProc -and $script:qosProc.HasExited) {
            $script:qosTimer.Stop()
            $msg = ''
            if (Test-Path $script:qosFile) {
                $msg = (Get-Content $script:qosFile -Raw).Trim()
                Remove-Item $script:qosFile -ErrorAction SilentlyContinue
            }
            if ($msg) { Add-Log ("QoS: " + $msg) }
            else      { Add-Log "QoS: elevated command finished (no result captured)." }
            if ($msg -like 'OK:*') {
                Add-Log "QoS: verify on the RECEIVER with Wireshark filter  ip.dsfield.dscp == <value>."
            }
        }
    })
    $script:qosTimer.Start()
}

function Reset-Graph {
    $script:series = [ordered]@{}
    $script:graph.Children.Clear()
    $script:spStats.Children.Clear()
}

function Get-DirColor([string]$label) {
    switch ($label) {
        'TX' { return [Windows.Media.Color]::FromRgb(79,195,247) }   # cyan  - this host sending
        'RX' { return [Windows.Media.Color]::FromRgb(255,183,77) }   # amber - this host receiving
        default { return [Windows.Media.Color]::FromRgb(129,199,132) }
    }
}

function Get-Series([string]$label) {
    if (-not $script:series.Contains($label)) {
        $script:series[$label] = [pscustomobject]@{
            Label  = $label
            Color  = (Get-DirColor $label)
            Points = (New-Object System.Collections.Generic.List[object])
            Peak   = 0.0; Sum = 0.0; Count = 0; Last = 0.0; Extra = ''
        }
    }
    return $script:series[$label]
}

function Add-Sample([string]$label, [double]$t, [double]$mbps, [string]$extra = '') {
    $ser = Get-Series $label
    $ser.Points.Add([pscustomobject]@{ T = $t; V = $mbps })
    if ($mbps -gt $ser.Peak) { $ser.Peak = $mbps }
    $ser.Sum += $mbps; $ser.Count += 1; $ser.Last = $mbps; $ser.Extra = $extra
    Redraw-Graph
    Update-Stats
}

function Update-Stats {
    $sp = $script:spStats
    $sp.Children.Clear()
    $grey = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(208,208,224))
    foreach ($k in $script:series.Keys) {
        $ser = $script:series[$k]
        $row = New-Object Windows.Controls.StackPanel
        $row.Orientation = 'Horizontal'
        $lab = New-Object Windows.Controls.TextBlock
        $lab.Text = ("{0}: " -f $ser.Label)
        $lab.Foreground = (New-Object Windows.Media.SolidColorBrush $ser.Color)
        $lab.FontWeight = 'Bold'; $lab.Width = 40
        [void]$row.Children.Add($lab)
        $avg = if ($ser.Count -gt 0) { $ser.Sum / $ser.Count } else { 0 }
        $val = New-Object Windows.Controls.TextBlock
        $val.Foreground = $grey
        $extra = if ($ser.Extra) { "     $($ser.Extra)" } else { '' }
        $val.Text = ("Current {0}     Average {1}     Peak {2}{3}" -f `
                     (Format-Rate $ser.Last), (Format-Rate $avg), (Format-Rate $ser.Peak), $extra)
        [void]$row.Children.Add($val)
        [void]$sp.Children.Add($row)
    }
}

function Redraw-Graph {
    $c = $script:graph
    $w = $c.ActualWidth; $h = $c.ActualHeight
    if ($w -le 0 -or $h -le 0) { return }
    $c.Children.Clear()

    $left = 56.0; $right = 12.0; $top = 10.0; $bottom = 24.0
    $plotW = $w - $left - $right
    $plotH = $h - $top - $bottom
    if ($plotW -le 0 -or $plotH -le 0) { return }

    # global vertical/horizontal scale across all series
    $maxV = 1.0; $maxT = 1.0
    foreach ($k in $script:series.Keys) {
        $ser = $script:series[$k]
        if ($ser.Peak -gt $maxV) { $maxV = $ser.Peak }
        if ($ser.Points.Count -gt 0) {
            $lt = $ser.Points[$ser.Points.Count - 1].T
            if ($lt -gt $maxT) { $maxT = $lt }
        }
    }
    # round the axis max up to something readable
    $mag = [Math]::Pow(10, [Math]::Floor([Math]::Log10($maxV)))
    $niceMax = [Math]::Ceiling($maxV / $mag) * $mag
    if ($niceMax -le 0) { $niceMax = 1 }

    # gridlines + Y labels
    $gridBrush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(48,48,68))
    $txtBrush  = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(128,128,160))
    for ($i = 0; $i -le 4; $i++) {
        $frac = $i / 4.0
        $y = $top + $plotH - ($frac * $plotH)
        $ln = New-Object Windows.Shapes.Line
        $ln.X1 = $left; $ln.X2 = $left + $plotW; $ln.Y1 = $y; $ln.Y2 = $y
        $ln.Stroke = $gridBrush; $ln.StrokeThickness = 1
        [void]$c.Children.Add($ln)
        $tb = New-Object Windows.Controls.TextBlock
        $tb.Text = (Format-Rate ($niceMax * $frac))
        $tb.Foreground = $txtBrush; $tb.FontSize = 10
        [Windows.Controls.Canvas]::SetLeft($tb, 2)
        [Windows.Controls.Canvas]::SetTop($tb, $y - 8)
        [void]$c.Children.Add($tb)
    }
    # X labels (0 and max time)
    foreach ($tv in @(0.0, $maxT)) {
        $x = $left + ($tv / $maxT) * $plotW
        $tb = New-Object Windows.Controls.TextBlock
        $tb.Text = ('{0:N0}s' -f $tv)
        $tb.Foreground = $txtBrush; $tb.FontSize = 10
        [Windows.Controls.Canvas]::SetLeft($tb, [Math]::Min($x, $left + $plotW - 20))
        [Windows.Controls.Canvas]::SetTop($tb, $top + $plotH + 4)
        [void]$c.Children.Add($tb)
    }

    # one polyline per direction series, plus a small legend
    $legendRow = 0
    foreach ($k in $script:series.Keys) {
        $ser = $script:series[$k]
        if ($ser.Points.Count -lt 1) { continue }
        $brush = New-Object Windows.Media.SolidColorBrush $ser.Color
        $pl = New-Object Windows.Shapes.Polyline
        $pl.Stroke = $brush; $pl.StrokeThickness = 2
        $pts = New-Object Windows.Media.PointCollection
        foreach ($p in $ser.Points) {
            $x = $left + ($p.T / $maxT) * $plotW
            $y = $top + $plotH - ($p.V / $niceMax) * $plotH
            $pts.Add((New-Object Windows.Point $x, $y))
        }
        $pl.Points = $pts
        [void]$c.Children.Add($pl)

        # legend swatch + label (top-left of plot area)
        $ly = $top + 4 + ($legendRow * 16)
        $sw = New-Object Windows.Shapes.Line
        $sw.X1 = $left + 8; $sw.X2 = $left + 26; $sw.Y1 = $ly + 8; $sw.Y2 = $ly + 8
        $sw.Stroke = $brush; $sw.StrokeThickness = 3
        [void]$c.Children.Add($sw)
        $lt = New-Object Windows.Controls.TextBlock
        $lt.Text = $ser.Label; $lt.Foreground = $brush; $lt.FontSize = 11; $lt.FontWeight = 'Bold'
        [Windows.Controls.Canvas]::SetLeft($lt, $left + 30)
        [Windows.Controls.Canvas]::SetTop($lt, $ly)
        [void]$c.Children.Add($lt)
        $legendRow += 1
    }
}

# Direction label for a "sum" object: TX = this host is sending, RX = receiving.
function Dir-Label($sumObj) {
    if ($sumObj -and ($sumObj.PSObject.Properties.Name -contains 'sender') -and $sumObj.sender) { return 'TX' }
    return 'RX'
}

# Extra per-interval detail: jitter/loss for UDP, retransmits for TCP.
function Sum-Extra($s) {
    if ($s.PSObject.Properties.Name -contains 'jitter_ms' -and $null -ne $s.jitter_ms) {
        return ('jitter {0:N2} ms, loss {1:N1}% ({2}/{3})' -f `
                [double]$s.jitter_ms, [double]$s.lost_percent, [int]$s.lost_packets, [int]$s.packets)
    }
    if ($s.PSObject.Properties.Name -contains 'retransmits' -and $null -ne $s.retransmits) {
        return ('retransmits {0}' -f [int]$s.retransmits)
    }
    return ''
}

function Process-Line([string]$line) {
    $line = $line.Trim()
    if (-not $line) { return }
    $obj = $null
    try { $obj = $line | ConvertFrom-Json } catch { }
    if ($null -eq $obj) {
        # non-JSON line: server text output, errors, etc.
        Add-Log $line
        return
    }
    $evt = $null
    if ($obj.PSObject.Properties.Name -contains 'event') { $evt = $obj.event }
    switch ($evt) {
        'start' {
            # Each test begins with a 'start' event. Reset the graph so successive
            # runs against a server don't smear together into one messy plot.
            Reset-Graph
            $d = $obj.data
            if ($d.PSObject.Properties.Name -contains 'connecting_to') {
                Add-Log ("Connecting to {0} port {1}" -f $d.connecting_to.host, $d.connecting_to.port)
            }
            if ($d.PSObject.Properties.Name -contains 'test_start') {
                $ts = $d.test_start
                Add-Log ("--- Test start: {0}, {1} stream(s), reverse={2}, bidir={3} ---" -f `
                         $ts.protocol, $ts.num_streams, $ts.reverse, $ts.bidir)
            }
        }
        'interval' {
            $d = $obj.data
            $logbits = @()
            # primary direction
            $s = $d.sum
            $lbl = Dir-Label $s
            $mbps = [double]$s.bits_per_second / 1e6
            Add-Sample $lbl ([double]$s.end) $mbps (Sum-Extra $s)
            $logbits += ("{0} {1}" -f $lbl, (Format-Rate $mbps))
            # reverse direction (bidirectional tests only)
            if ($d.PSObject.Properties.Name -contains 'sum_bidir_reverse' -and $d.sum_bidir_reverse) {
                $r = $d.sum_bidir_reverse
                $lbl2 = Dir-Label $r
                $mbps2 = [double]$r.bits_per_second / 1e6
                Add-Sample $lbl2 ([double]$r.end) $mbps2 (Sum-Extra $r)
                $logbits += ("{0} {1}" -f $lbl2, (Format-Rate $mbps2))
            }
            Add-Log ("[{0,5:N1}s]  {1}" -f [double]$s.end, ($logbits -join '   '))
        }
        'end' {
            $d = $obj.data
            Add-Log "--- Test complete ---"
            foreach ($pair in @(
                @('sum_sent','sent (TX)'), @('sum_received','received (RX)'),
                @('sum_sent_bidir_reverse','sent reverse'), @('sum_received_bidir_reverse','received reverse'))) {
                $key = $pair[0]; $name = $pair[1]
                if ($d.PSObject.Properties.Name -contains $key -and $d.$key) {
                    $sm = $d.$key
                    $x = Sum-Extra $sm
                    Add-Log ("SUMMARY {0,-16} {1}{2}" -f $name, (Format-Rate ([double]$sm.bits_per_second/1e6)),
                             $(if ($x) { "   $x" } else { '' }))
                }
            }
        }
        default {
            Add-Log $line
        }
    }
}

function Poll-Output {
    if (-not $script:logFile -or -not (Test-Path $script:logFile)) { return }
    try {
        $stream = New-Object System.IO.FileStream($script:logFile, [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        [void]$stream.Seek($script:bytePos, [System.IO.SeekOrigin]::Begin)
        $sr = New-Object System.IO.StreamReader($stream)
        $text = $sr.ReadToEnd()
        $script:bytePos = $stream.Position
        $sr.Close(); $stream.Close()
    } catch { return }

    if ($text) {
        $script:buffer += $text
        while (($idx = $script:buffer.IndexOf("`n")) -ge 0) {
            $line = $script:buffer.Substring(0, $idx)
            $script:buffer = $script:buffer.Substring($idx + 1)
            Process-Line $line
        }
    }
}

function Set-Running([bool]$on) {
    $script:running = $on
    $script:btnRun.IsEnabled  = -not $on
    $script:btnStop.IsEnabled = $on
    # Group containers (grpClient/grpServer) disable all their children via WPF
    # IsEnabled propagation, so we only toggle the containers + the common controls.
    foreach ($ctl in @($rbClient,$rbServer,$txtPort,$txtInterval,$chkNat,$txtExtra,$txtDscp,
                       $btnQosApply,$btnQosClear,$grpClient,$grpServer,$txtIperf,$btnBrowse,$btnPubIp)) {
        $ctl.IsEnabled = -not $on
    }
    if (-not $on) { & $script:updateRole }   # re-apply which role's group is active
}

function Build-Args {
    $a = New-Object System.Collections.Generic.List[string]
    $isClient = $rbClient.IsChecked
    if ($isClient) {
        $a.Add('-c'); $a.Add($txtHost.Text.Trim())
    } else {
        $a.Add('-s')
    }
    if ($txtPort.Text.Trim())     { $a.Add('-p'); $a.Add($txtPort.Text.Trim()) }
    if ($chkNat.IsChecked)        { $a.Add('--nat') }
    if ($txtInterval.Text.Trim()) { $a.Add('-i'); $a.Add($txtInterval.Text.Trim()) }

    if ($isClient) {
        # -u (UDP) is a client-only flag in iperf3; the server auto-detects the
        # protocol from the client, so it must never be sent in server mode.
        if ($rbUdp.IsChecked)         { $a.Add('-u') }
        if ($txtTime.Text.Trim())     { $a.Add('-t'); $a.Add($txtTime.Text.Trim()) }
        if ($txtParallel.Text.Trim()) { $a.Add('-P'); $a.Add($txtParallel.Text.Trim()) }
        if ($txtBitrate.Text.Trim())  { $a.Add('-b'); $a.Add($txtBitrate.Text.Trim()) }
        if ($txtLen.Text.Trim())      { $a.Add('-l'); $a.Add($txtLen.Text.Trim()) }
        if ($txtWindow.Text.Trim())   { $a.Add('-w'); $a.Add($txtWindow.Text.Trim()) }
        if ($txtDscp.Text.Trim())     { $a.Add('--dscp'); $a.Add($txtDscp.Text.Trim()) }
        if ($chkReverse.IsChecked)    { $a.Add('-R') }
        if ($chkBidir.IsChecked)      { $a.Add('--bidir') }
    }
    # Real-time machine-readable stream
    $a.Add('--json-stream'); $a.Add('--forceflush')
    if ($txtExtra.Text.Trim()) {
        foreach ($tok in ($txtExtra.Text.Trim() -split '\s+')) { if ($tok) { $a.Add($tok) } }
    }
    # Return with the unary comma so PowerShell does NOT unroll the List into the
    # pipeline (which would make the caller receive a fixed-size object[] and fail
    # on the later .Add() calls).
    return ,$a
}

function Start-Run {
    if ($script:running) { return }
    $exe = $txtIperf.Text.Trim()
    if (-not $exe -or -not (Test-Path $exe)) {
        [System.Windows.MessageBox]::Show("Could not find iperf3.exe. Use Browse to select it.",
            "iperf3-nat GUI", 'OK', 'Warning') | Out-Null
        return
    }
    if ($rbClient.IsChecked -and -not $txtHost.Text.Trim()) {
        [System.Windows.MessageBox]::Show("Enter a host to connect to (client mode).",
            "iperf3-nat GUI", 'OK', 'Warning') | Out-Null
        return
    }

    $txtLog.Clear()
    Reset-Graph
    $argList = Build-Args
    $lblCmd.Text = 'iperf3 ' + ($argList -join ' ')

    # Route output to a temp file that we tail (decouples the child process from the UI thread)
    $script:logFile = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(),
                        ('iperf3gui_{0}.jsonl' -f ([guid]::NewGuid().ToString('N'))))
    $argList.Add('--logfile'); $argList.Add($script:logFile)
    $script:bytePos = 0
    $script:buffer  = ''

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = ($argList | ForEach-Object {
        if ($_ -match '\s') { '"' + $_ + '"' } else { $_ }
    }) -join ' '
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    $psi.RedirectStandardError = $true

    try {
        $script:proc = [System.Diagnostics.Process]::Start($psi)
    } catch {
        Add-Log ("Failed to start iperf3: " + $_.Exception.Message)
        return
    }
    Add-Log ("> " + $exe + " " + $psi.Arguments)
    Set-Running $true

    # Server mode: optionally ask the router to forward this port via UPnP so a
    # server behind NAT becomes reachable without a manual port-forward.
    if ($rbServer.IsChecked -and $chkUpnp.IsChecked) {
        $port = 5201
        [void][int]::TryParse($txtPort.Text.Trim(), [ref]$port)
        $localIP = Get-LocalIPv4
        if (-not $localIP) {
            Add-Log "UPnP: could not determine this machine's LAN IP; skipping port mapping."
        } else {
            # A server accepts both TCP and UDP clients, and protocol is chosen by
            # the client, so forward both to be safe.
            $protos = @('TCP','UDP')
            Add-Log ("UPnP: requesting router forward of port {0}/{1} -> {2} ..." -f $port, ($protos -join '+'), $localIP)
            $lblStatus.Text = 'Requesting UPnP port mapping from router...'
            $u = Add-UpnpMapping -Port $port -Protocols $protos -LocalIP $localIP -Desc 'iperf3-nat'
            if ($u.Ok) {
                $script:upnpMappings   = $u.Mapped
                $script:upnpExternalIp = $u.External
                if ($u.External) {
                    Add-Log ("UPnP: SUCCESS - clients should connect to  {0}:{1}   (WAN -> {2}:{1})" -f $u.External, $port, $localIP)
                    $lblExtra.Text = ("Public: {0}:{1}" -f $u.External, $port)
                } else {
                    Add-Log "UPnP: mapping created on the router (external IP not reported)."
                }
            } else {
                Add-Log ("UPnP: could not create mapping - " + $u.Error + ".")
                Add-Log ("UPnP: continuing without auto-forward; forward TCP{0} port {1} to {2} manually if the server is behind NAT." -f `
                         ($(if ($rbUdp.IsChecked) {'/UDP'} else {''})), $port, $localIP)
            }
        }
    }

    if ($rbServer.IsChecked -and -not $script:upnpExternalIp) {
        Add-Log "Tip: click 'Public IP' to get the internet address remote clients should connect to."
    }

    $lblStatus.Text = if ($rbServer.IsChecked) { 'Server running - waiting for clients...' } else { 'Test running...' }
    $script:timer.Start()
}

function Stop-Run([string]$reason = 'Stopped.') {
    if ($script:proc -and -not $script:proc.HasExited) {
        try { $script:proc.Kill() } catch { }
    }
    Start-Sleep -Milliseconds 100
    Poll-Output   # final drain
    $script:timer.Stop()
    if ($script:proc) {
        $err = ''
        try { $err = $script:proc.StandardError.ReadToEnd() } catch { }
        if ($err) { Add-Log $err }
    }
    Remove-UpnpMappings
    Set-Running $false
    $lblStatus.Text = $reason
    if ($script:logFile -and (Test-Path $script:logFile)) {
        try { Remove-Item $script:logFile -Force -ErrorAction SilentlyContinue } catch { }
    }
    $script:proc = $null
}

# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------
$script:timer.Add_Tick({
    Poll-Output
    if ($script:proc -and $script:proc.HasExited) {
        Stop-Run 'Done.'
    }
})

$btnRun.Add_Click({ Start-Run })
$btnStop.Add_Click({ Stop-Run 'Stopped by user.' })

$btnPubIp.Add_Click({
    $btnPubIp.IsEnabled = $false
    $lblStatus.Text = 'Resolving public IP...'
    # let the status text repaint before the (brief, blocking) web call
    $win.Dispatcher.Invoke([action]{}, [System.Windows.Threading.DispatcherPriority]::Render)
    $ip = Resolve-AndShowPublicIP
    if ($ip) {
        try { [System.Windows.Clipboard]::SetText($ip) } catch { }
        $lblStatus.Text = "Public IP: $ip  (copied to clipboard)"
    } else {
        $lblStatus.Text = 'Public IP lookup failed.'
    }
    $btnPubIp.IsEnabled = $true
})

$btnQosApply.Add_Click({ Invoke-QosPolicy 'apply' })
$btnQosClear.Add_Click({ Invoke-QosPolicy 'clear' })

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'iperf3 executable (iperf3.exe)|iperf3.exe|All executables (*.exe)|*.exe'
    $dlg.Title  = 'Locate iperf3.exe'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtIperf.Text = $dlg.FileName
    }
})

# Redraw graph on canvas resize
$graph.Add_SizeChanged({ Redraw-Graph })

# Enable/disable client-only fields when role changes
$script:updateRole = {
    $isClient = $rbClient.IsChecked
    $grpClient.IsEnabled = $isClient        # CLIENT OPTIONS group
    $grpServer.IsEnabled = -not $isClient   # SERVER OPTIONS group
}
$rbClient.Add_Checked($script:updateRole)
$rbServer.Add_Checked($script:updateRole)
& $script:updateRole   # apply once at startup (default is client mode)

$win.Add_Closing({
    if ($script:running) { Stop-Run 'Closing.' }
})

if (-not $script:IperfPath) {
    Add-Log "iperf3.exe not found automatically - use Browse to select it."
} else {
    Add-Log ("Using iperf3: " + $script:IperfPath)
}
Add-Log "Set options above and click Run. Client mode graphs live throughput; use -R for a download test through NAT."

[void]$win.ShowDialog()
