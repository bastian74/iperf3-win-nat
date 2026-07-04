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
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/><RowDefinition Height="6"/>
          <RowDefinition Height="Auto"/><RowDefinition Height="6"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- line 1: role + host + port -->
        <StackPanel Grid.Row="0" Grid.Column="0" Orientation="Horizontal">
          <Label Content="Mode:"/>
          <RadioButton x:Name="rbClient" Content="Client" IsChecked="True" GroupName="role"/>
          <RadioButton x:Name="rbServer" Content="Server" GroupName="role"/>
        </StackPanel>
        <StackPanel Grid.Row="0" Grid.Column="1" Orientation="Horizontal" Margin="16,0,0,0">
          <Label Content="Host:"/>
          <TextBox x:Name="txtHost" Width="200" Text="127.0.0.1"/>
        </StackPanel>
        <Label Grid.Row="0" Grid.Column="2" Content="Port:"/>
        <TextBox Grid.Row="0" Grid.Column="3" x:Name="txtPort" Width="70" Text="5201"/>
        <StackPanel Grid.Row="0" Grid.Column="4" Grid.ColumnSpan="2" Orientation="Horizontal" Margin="16,0,0,0">
          <Label Content="Protocol:"/>
          <RadioButton x:Name="rbTcp" Content="TCP" IsChecked="True" GroupName="proto"/>
          <RadioButton x:Name="rbUdp" Content="UDP" GroupName="proto"/>
        </StackPanel>

        <!-- line 2: duration, streams, bitrate, window -->
        <StackPanel Grid.Row="2" Grid.Column="0" Grid.ColumnSpan="2" Orientation="Horizontal">
          <Label Content="Duration (-t):"/>
          <TextBox x:Name="txtTime" Width="50" Text="10"/>
          <Label Content="s" Margin="2,0,12,0"/>
          <Label Content="Streams (-P):"/>
          <TextBox x:Name="txtParallel" Width="45" Text="1"/>
          <Label Content="Interval (-i):" Margin="12,0,0,0"/>
          <TextBox x:Name="txtInterval" Width="45" Text="1"/>
          <Label Content="s"/>
        </StackPanel>
        <StackPanel Grid.Row="2" Grid.Column="2" Grid.ColumnSpan="4" Orientation="Horizontal" Margin="16,0,0,0">
          <Label Content="Bitrate (-b):"/>
          <TextBox x:Name="txtBitrate" Width="70" Text=""/>
          <Label Content="(e.g. 50M; UDP/capped TCP)" Foreground="#8080a0"/>
          <Label Content="Window (-w):" Margin="12,0,0,0"/>
          <TextBox x:Name="txtWindow" Width="60" Text=""/>
        </StackPanel>

        <!-- line 3: checkboxes + format + extra -->
        <StackPanel Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="3" Orientation="Horizontal">
          <CheckBox x:Name="chkReverse" Content="Reverse (-R)"/>
          <CheckBox x:Name="chkBidir" Content="Bidir (--bidir)"/>
          <CheckBox x:Name="chkNat" Content="NAT (--nat)" IsChecked="True"/>
          <CheckBox x:Name="chkUpnp" Content="Auto-forward (UPnP)" ToolTip="Server mode: ask the router to forward this port via UPnP"/>
        </StackPanel>
        <StackPanel Grid.Row="4" Grid.Column="3" Grid.ColumnSpan="3" Orientation="Horizontal" Margin="16,0,0,0">
          <Label Content="Extra args:"/>
          <TextBox x:Name="txtExtra" Width="230" Text=""/>
        </StackPanel>
      </Grid>
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

    <!-- Row 3: live stats -->
    <Border Grid.Row="3" Background="#26263440" BorderBrush="#3a3a52" BorderThickness="1"
            CornerRadius="4" Padding="8,4" Margin="0,6,0,6">
      <StackPanel Orientation="Horizontal">
        <TextBlock Foreground="#8080a0" Text="Current: "/>
        <TextBlock x:Name="lblCur" Foreground="#4fc3f7" FontWeight="Bold" Text="-" Width="130"/>
        <TextBlock Foreground="#8080a0" Text="Average: "/>
        <TextBlock x:Name="lblAvg" Foreground="#81c784" FontWeight="Bold" Text="-" Width="130"/>
        <TextBlock Foreground="#8080a0" Text="Peak: "/>
        <TextBlock x:Name="lblPeak" Foreground="#ffb74d" FontWeight="Bold" Text="-" Width="130"/>
        <TextBlock x:Name="lblExtra" Foreground="#b0b0c8" Text=""/>
      </StackPanel>
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
        <ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <TextBlock Grid.Column="0" x:Name="lblStatus" Foreground="#8080a0" Text="Idle." VerticalAlignment="Center"/>
      <TextBlock Grid.Column="1" x:Name="lblCmd" Foreground="#606078" VerticalAlignment="Center"
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
$script:points    = New-Object System.Collections.Generic.List[object]
$script:peak      = 0.0
$script:sumV      = 0.0
$script:running   = $false
$script:timer     = New-Object System.Windows.Threading.DispatcherTimer
$script:timer.Interval = [TimeSpan]::FromMilliseconds(200)
$script:upnpMappings   = @()      # list of @{Port=;Protocol=} we created on the router
$script:upnpExternalIp = $null    # WAN IP reported by the IGD, if any

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

function Reset-Graph {
    $script:points.Clear()
    $script:peak = 0.0
    $script:sumV = 0.0
    $script:graph.Children.Clear()
    $script:lblCur.Text  = '-'
    $script:lblAvg.Text  = '-'
    $script:lblPeak.Text = '-'
    $script:lblExtra.Text = ''
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

    # scales
    $maxV = [Math]::Max($script:peak, 1.0)
    # round the axis max up to something readable
    $mag = [Math]::Pow(10, [Math]::Floor([Math]::Log10($maxV)))
    $niceMax = [Math]::Ceiling($maxV / $mag) * $mag
    if ($niceMax -le 0) { $niceMax = 1 }

    $maxT = 1.0
    if ($script:points.Count -gt 0) { $maxT = [Math]::Max($script:points[$script:points.Count-1].T, 1.0) }

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

    if ($script:points.Count -lt 1) { return }

    # polyline
    $pl = New-Object Windows.Shapes.Polyline
    $pl.Stroke = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromRgb(79,195,247))
    $pl.StrokeThickness = 2
    $pts = New-Object Windows.Media.PointCollection
    foreach ($p in $script:points) {
        $x = $left + ($p.T / $maxT) * $plotW
        $y = $top + $plotH - ($p.V / $niceMax) * $plotH
        $pts.Add((New-Object Windows.Point $x, $y))
    }
    $pl.Points = $pts
    [void]$c.Children.Add($pl)

    # fill area under the line (subtle)
    if ($script:points.Count -ge 2) {
        $poly = New-Object Windows.Shapes.Polygon
        $poly.Fill = New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color]::FromArgb(40,79,195,247))
        $fpts = New-Object Windows.Media.PointCollection
        $fpts.Add((New-Object Windows.Point ($left), ($top + $plotH)))
        foreach ($p in $script:points) {
            $x = $left + ($p.T / $maxT) * $plotW
            $y = $top + $plotH - ($p.V / $niceMax) * $plotH
            $fpts.Add((New-Object Windows.Point $x, $y))
        }
        $fpts.Add((New-Object Windows.Point ($left + ($maxT/$maxT)*$plotW), ($top + $plotH)))
        $poly.Points = $fpts
        [void]$c.Children.Add($poly)
    }
}

function Add-Point([double]$t, [double]$mbps, [string]$extra = '') {
    $script:points.Add([pscustomobject]@{ T = $t; V = $mbps })
    if ($mbps -gt $script:peak) { $script:peak = $mbps }
    $script:sumV += $mbps
    $script:lblCur.Text  = Format-Rate $mbps
    $script:lblAvg.Text  = Format-Rate ($script:sumV / $script:points.Count)
    $script:lblPeak.Text = Format-Rate $script:peak
    if ($extra) { $script:lblExtra.Text = $extra }
    Redraw-Graph
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
            $d = $obj.data
            if ($d.PSObject.Properties.Name -contains 'connecting_to') {
                Add-Log ("Connecting to {0} port {1}" -f $d.connecting_to.host, $d.connecting_to.port)
            }
            if ($d.PSObject.Properties.Name -contains 'test_start') {
                $ts = $d.test_start
                Add-Log ("Test start: {0}, {1} stream(s), reverse={2}, bidir={3}" -f `
                         $ts.protocol, $ts.num_streams, $ts.reverse, $ts.bidir)
            }
        }
        'interval' {
            $s = $obj.data.sum
            $mbps = [double]$s.bits_per_second / 1e6
            $extra = ''
            if ($s.PSObject.Properties.Name -contains 'jitter_ms') {
                $extra = ('jitter {0:N3} ms, lost {1:N1}%' -f [double]$s.jitter_ms, [double]$s.lost_percent)
            }
            if ($s.PSObject.Properties.Name -contains 'retransmits' -and $null -ne $s.retransmits) {
                $extra = ('retransmits: {0}' -f $s.retransmits)
            }
            Add-Point ([double]$s.end) $mbps $extra
            Add-Log ("[{0,6:N1}s] {1}" -f [double]$s.end, (Format-Rate $mbps))
        }
        'end' {
            $d = $obj.data
            if ($d.PSObject.Properties.Name -contains 'sum_sent') {
                Add-Log ("SUMMARY  sent: {0}" -f (Format-Rate ([double]$d.sum_sent.bits_per_second/1e6)))
            }
            if ($d.PSObject.Properties.Name -contains 'sum_received') {
                Add-Log ("SUMMARY  recv: {0}" -f (Format-Rate ([double]$d.sum_received.bits_per_second/1e6)))
            }
        }
        default {
            # unknown JSON (e.g. an error object) - dump compact
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
    foreach ($ctl in @($rbClient,$rbServer,$rbTcp,$rbUdp,$txtHost,$txtPort,$txtTime,
                       $txtParallel,$txtInterval,$txtBitrate,$txtWindow,$chkReverse,
                       $chkBidir,$chkNat,$chkUpnp,$txtExtra,$txtIperf,$btnBrowse,$btnPubIp)) {
        $ctl.IsEnabled = -not $on
    }
    if (-not $on) {
        # Re-apply role-based enable/disable (client-only vs server-only fields)
        $isClient = $rbClient.IsChecked
        foreach ($ctl in @($txtHost,$txtTime,$txtParallel,$txtBitrate,$txtWindow,$chkReverse,$chkBidir)) {
            $ctl.IsEnabled = $isClient
        }
        $chkUpnp.IsEnabled = -not $isClient
    }
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
    if ($rbUdp.IsChecked)         { $a.Add('-u') }
    if ($chkNat.IsChecked)        { $a.Add('--nat') }
    if ($txtInterval.Text.Trim()) { $a.Add('-i'); $a.Add($txtInterval.Text.Trim()) }

    if ($isClient) {
        if ($txtTime.Text.Trim())     { $a.Add('-t'); $a.Add($txtTime.Text.Trim()) }
        if ($txtParallel.Text.Trim()) { $a.Add('-P'); $a.Add($txtParallel.Text.Trim()) }
        if ($txtBitrate.Text.Trim())  { $a.Add('-b'); $a.Add($txtBitrate.Text.Trim()) }
        if ($txtWindow.Text.Trim())   { $a.Add('-w'); $a.Add($txtWindow.Text.Trim()) }
        if ($chkReverse.IsChecked)    { $a.Add('-R') }
        if ($chkBidir.IsChecked)      { $a.Add('--bidir') }
    }
    # Real-time machine-readable stream
    $a.Add('--json-stream'); $a.Add('--forceflush')
    if ($txtExtra.Text.Trim()) {
        foreach ($tok in ($txtExtra.Text.Trim() -split '\s+')) { if ($tok) { $a.Add($tok) } }
    }
    return $a
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
            $protos = @('TCP')
            if ($rbUdp.IsChecked) { $protos += 'UDP' }   # UDP tests also need the UDP port
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
$updateRole = {
    $isClient = $rbClient.IsChecked
    foreach ($ctl in @($txtHost,$txtTime,$txtParallel,$txtBitrate,$txtWindow,$chkReverse,$chkBidir)) {
        $ctl.IsEnabled = $isClient
    }
    $chkUpnp.IsEnabled = -not $isClient   # UPnP auto-forward is a server-side action
}
$rbClient.Add_Checked($updateRole)
$rbServer.Add_Checked($updateRole)
& $updateRole   # apply once at startup (default is client mode -> UPnP disabled)

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
