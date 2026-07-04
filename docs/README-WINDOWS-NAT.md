# iperf3-nat — running iperf3 on Windows through NAT / PAT / firewalls

This is a fork of [esnet/iperf](https://github.com/esnet/iperf) (iperf3) focused on
making the tool practical to run **on Windows** and **across NAT, PAT (port-address
translation) and stateful firewalls**.

It changes very little in the core measurement engine — the wire protocol is
unchanged and it interoperates with stock `iperf3` — but it fixes the Windows
build so that the connection-keepalive machinery is actually compiled in, and it
adds a single convenience flag (`--nat`) plus documentation for the connection
patterns that traverse NAT cleanly.

---

## Why stock iperf3 is awkward across NAT/firewalls on Windows

Two separate problems:

1. **Windows build gap.** iperf3 detects optional socket features with `configure`
   probes that `#include <netinet/tcp.h>` on its own. On Cygwin/MSYS2 (the runtime
   iperf3 uses on Windows) that header does not compile standalone, so the probe
   *fails to compile* rather than failing to find a symbol. The net effect is that
   `HAVE_TCP_KEEPALIVE` is silently switched **off** on Windows, and the
   `--cntl-ka` control-connection keepalive — the exact feature you need for
   NAT/firewall traversal — is compiled out. This fork fixes the probes so the
   feature is enabled on Windows.

2. **Idle control connection.** During a test, iperf3 keeps a TCP *control*
   connection open alongside the data transfer. During a long UDP test (or any
   quiet period) that control connection carries no traffic. NAT/PAT devices and
   stateful firewalls drop idle mappings (commonly after 30–120 s), and when the
   test ends the summary exchange fails — the test "hangs" or errors out. Keeping
   the control connection warm with TCP keepalive avoids this.

---

## What actually traverses NAT (important, and already true in iperf3)

iperf3's connection model is friendly to NAT **if you understand it**:

* Every connection — the control connection *and* all data connections, in both
  test directions — is opened **from the client to the single server port**
  (default TCP 5201). The server never dials back to the client.
* Therefore you only need **one inbound TCP port reachable on the server side**
  (one port-forward / one firewall allow rule). Nothing needs to be opened toward
  the client.
* To measure **download** to a client that sits behind NAT, use reverse mode
  (`-R`) or bidirectional mode (`--bidir`). The server sends data back over
  connections the client already established outbound, so the client never needs
  an inbound port.

So the rule of thumb is:

> **Put the iperf3 *server* on the side you can port-forward to. Put the *client*
> on the NAT'd side. Use `-R` when you want to measure the download direction.**

UDP tests follow the same pattern (the client sends the first datagram; the
server learns the client's translated address from it), so UDP also works through
NAT/PAT as long as the server's UDP port is reachable and the mapping is kept
alive.

---

## The `--nat` flag

`--nat` is a convenience switch that turns on the control-connection TCP keepalive
with aggressive-but-safe defaults so the NAT/firewall mapping is refreshed long
before a typical idle timeout:

| Parameter                | Value | Meaning                                   |
|--------------------------|-------|-------------------------------------------|
| `TCP_KEEPIDLE`           | 15 s  | start probing after 15 s of idle          |
| `TCP_KEEPINTVL`          | 4 s   | then probe every 4 s                      |
| `TCP_KEEPCNT`            | 3     | give up after 3 unanswered probes         |

It is equivalent to `--cntl-ka=15/4/3`, but easier to remember. You can still
override the numbers explicitly with `--cntl-ka=IDLE/INTVL/CNT`.

Because any keepalive packet refreshes the NAT/firewall mapping in both
directions, enabling `--nat` on **the side behind NAT** (usually the client) is
enough; enabling it on both sides is harmless and also lets each side detect a
dead peer faster.

---

## Quick start

Server (on the port-forwarded / reachable side):

```
iperf3.exe -s --nat -p 5201
```

Forward inbound TCP **and** UDP port 5201 to that host, or open it in the
firewall.

Client (behind NAT):

```
# Upload (client -> server)
iperf3.exe -c SERVER_PUBLIC_IP -p 5201 --nat

# Download (server -> client), the common "test my down speed" case
iperf3.exe -c SERVER_PUBLIC_IP -p 5201 --nat -R

# Both directions at once
iperf3.exe -c SERVER_PUBLIC_IP -p 5201 --nat --bidir

# Long UDP test at 50 Mbit/s (keepalive keeps the mapping alive to the end)
iperf3.exe -c SERVER_PUBLIC_IP -p 5201 --nat -u -b 50M -t 300
```

Verify keepalive is active with `-V` (verbose); you should see a line like:

```
Control connection TCP Keepalive TCP_KEEPIDLE/TCP_KEEPINTVL/TCP_KEEPCNT are set to 15/4/3
```

---

## Firewall / port-forward checklist

* Forward exactly **one** port to the server (default 5201). Forward the same port
  number for both TCP and UDP if you intend to run UDP tests.
* On the **server** Windows host, allow `iperf3.exe` (or the port) inbound in
  Windows Defender Firewall. The **client** needs no inbound rule.
* If your provider uses carrier-grade NAT on the client side, that is fine — the
  client is the side dialing out. Only the server must be reachable.
* Pick a fixed server port and keep `--nat` on for anything longer than a few
  seconds or any UDP test.

---

## Building it yourself (native Windows, no Cygwin install for end users)

Install [MSYS2](https://www.msys2.org/), then from the MSYS2 shell:

```
pacman -S --needed gcc make autotools
git clone <this-fork-url>
cd iperf
./build-windows.sh
```

`build-windows.sh` configures, builds, and stages a **self-contained** folder at
`dist/iperf3-nat-windows/` containing `iperf3.exe` plus the one runtime DLL it
needs (`msys-2.0.dll`). Copy that folder to any Windows machine and run
`iperf3.exe` — no MSYS2 installation required on the target, exactly like the
popular Cygwin-based Windows iperf3 builds.

---

## GUI (jperf-style, with real-time graphing)

The `gui/` folder contains a dependency-free graphical front-end — the spiritual
successor to jperf, but built for iperf3. It is a WPF app driven by Windows
PowerShell (already present on every Windows machine; nothing to install) that
exposes the common command-line options as controls and draws a **live
throughput graph** by parsing iperf3's `--json-stream` output.

Launch it by double-clicking **`iperf3-gui.cmd`** (it starts PowerShell in the
STA mode WPF requires), or:

```
powershell.exe -STA -ExecutionPolicy Bypass -File gui\iperf3-gui.ps1
```

It auto-locates `iperf3.exe` (same folder, `..\src`, or the `dist` build); use
**Browse…** to point at a specific binary. `build-windows.sh` copies the GUI into
`dist/iperf3-nat-windows/` alongside the exe, so the packaged build is a complete,
self-contained bundle.

What it exposes:

* **Mode** — Client or Server
* **Host**, **Port**, **Protocol** (TCP/UDP)
* **Duration** (`-t`), **Streams** (`-P`), **Interval** (`-i`), **Bitrate**
  (`-b`), **Length/packet size** (`-l`), **Window** (`-w`), **DSCP** (`--dscp`)
* **Reverse** (`-R`), **Bidirectional** (`--bidir`), **NAT mode** (`--nat`)
* **Auto-forward (UPnP)** — server-mode only; see below
* A **Public IP** button — look up this machine's internet-visible address
* An **Extra args** box for anything else (passed through verbatim)

### Reading the live graph and stats

* Each **direction is a separate line**: cyan **TX** (this machine sending) and
  amber **RX** (this machine receiving), with a legend on the plot. A one-way test
  shows a single line; a **bidirectional** (`--bidir`) test shows both at once; a
  **reverse** (`-R`) test shows RX. On a server the labels follow the same rule
  (an upload test to the server shows RX).
* **Current / Average / Peak are reported per direction**, one row each, colour-
  matched to the graph line.
* The graph **resets at the start of each test**, so running several tests against
  a long-lived server no longer smears them into one tangled plot — you always see
  the current test.
* For **UDP** the stats row and log also show **jitter and packet loss** (measured
  on the receiving side); for **TCP** they show **retransmits**. The end-of-test
  summary logs every direction (sent/received, and the reverse pair for bidir).
* Note: iperf3 is a throughput tool and does **not** measure round-trip latency,
  so the GUI can't show it. Use `ping`/`pathping` alongside if you need latency.

### QoS / DSCP marking on Windows (important caveat)

The **DSCP** box passes `--dscp` (accepts names like `EF`, `CS5`, `AF11` or a
number 0-63) so iperf3 asks the socket to mark packets. **However, Windows
usually strips application-set DSCP/ToS values by default** — the socket call
succeeds but the bits never reach the wire. This is a Windows policy, not an
iperf3 limitation. To actually mark packets on Windows you generally need one of:

* a **Group Policy QoS Policy** (Computer/User Config → Policy-based QoS) that
  matches the app or port and sets the DSCP value — the recommended, supported
  way; or
* the legacy registry override
  `HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\DisableUserTOSSetting = 0`
  (a reboot is required, and it is disabled by default for a reason).

So treat the DSCP box as "request marking"; verify with a capture (Wireshark) or
switch statistics whether the bits actually survive on your network. On Linux/BSD
peers the same `--dscp` works without these hoops.

### Public IP button

Click **Public IP** to resolve this machine's internet-visible address (via a
public echo service such as api.ipify.org, with several fallbacks) and copy it to
the clipboard — that's the address remote clients on the internet should connect
to. It works whether or not UPnP is available, as long as outbound HTTPS is
allowed. Note this reports the address the outside world sees; if you are behind
carrier-grade NAT it will be a shared address that still won't accept inbound
connections. The router's own WAN IP (which may differ) is reported separately by
the UPnP mapping when you use Auto-forward.

### Auto-forward (UPnP) — for a server that *is* behind NAT

Normally iperf3's server has to be on the reachable side (one forwarded port).
The GUI's **Auto-forward (UPnP)** checkbox lets a server behind NAT open that port
itself: when you start the server with it ticked, the GUI asks your router — via
the UPnP IGD protocol built into Windows (`HNetCfg.NATUPnP`, no extra software) —
to forward the server port to this machine, and logs the **public IP** clients
should connect to. When you Stop the server (or close the GUI) the mapping is
removed again. If UDP is selected, both the TCP and UDP port are mapped (the
control channel is always TCP).

Caveats, stated honestly:

* **The router must have UPnP IGD enabled.** Many home routers do by default;
  many corporate/campus networks and all carrier-grade NAT deliberately do not.
  If it's unavailable the GUI logs a clear warning and the server still runs — you
  just have to port-forward manually (or you're out of luck behind CGNAT).
* UPnP maps the **router**, not the local Windows Firewall. If Windows prompts to
  allow `iperf3.exe`, still allow it (or add an inbound rule for the port).
* This is available in the **GUI server mode only**. The headless `iperf3.exe`
  itself does not do UPnP; that would need a UPnP C library linked into the
  binary. Ask if you need the CLI to do it too.

While a test runs it shows the live per-interval line graph plus current /
average / peak counters and a scrolling log; UDP tests additionally show jitter
and loss, and TCP tests show retransmits. **Stop** kills the run. Because it uses
`--json-stream` rather than scraping human-readable text (the brittle thing jperf
did with iperf2), the parsing is robust and works with reverse/bidir/UDP modes.

The GUI runs the same `iperf3.exe` documented above, so all the NAT guidance
applies: put the server on the reachable side, tick **NAT mode**, and tick
**Reverse** to graph a download test from a client behind NAT.

## Compatibility

* Wire-protocol compatible with upstream iperf3 3.21+. A `iperf3-nat` client can
  talk to a stock `iperf3` server and vice-versa; `--nat` only affects local
  socket options and does not change the protocol.
* The `--nat` keepalive requires `TCP_KEEPIDLE`/`TCP_KEEPINTVL`/`TCP_KEEPCNT`,
  which are present on Windows (MSYS2/Cygwin) and Linux. On a platform without
  them, `--nat` still enforces single-port usage guidance but prints a warning
  that keepalive is unavailable.
