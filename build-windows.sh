#!/usr/bin/env bash
#
# build-windows.sh - build iperf3-nat on Windows under MSYS2 and produce a
# self-contained distribution folder (iperf3.exe + required runtime DLLs +
# docs) that can be copied to any Windows machine and run without installing
# MSYS2/Cygwin.
#
# Prerequisites (run once inside the MSYS2 shell):
#     pacman -S --needed gcc make autotools
#
# Usage (from the MSYS2 shell, in the repo root):
#     ./build-windows.sh
#
# Result:
#     dist/iperf3-nat-windows/   <- copy this whole folder anywhere and run iperf3.exe
#
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"

echo "==> Regenerating build system (autoreconf)"
autoreconf -fi

echo "==> Configuring"
./configure --disable-shared

echo "==> Building"
make clean >/dev/null 2>&1 || true
make -j"$(nproc)"

exe="src/iperf3.exe"
if [ ! -f "$exe" ]; then
    echo "ERROR: build did not produce $exe" >&2
    exit 1
fi

outdir="dist/iperf3-nat-windows"
echo "==> Staging distribution in $outdir"
rm -rf "$outdir"
mkdir -p "$outdir"
cp "$exe" "$outdir/"
cp -f COPYING LICENSE README.md docs/README-WINDOWS-NAT.md "$outdir/" 2>/dev/null || true

# Bundle the GUI front-end (jperf-style, with real-time graphing) next to the exe
# so it finds iperf3.exe in its own folder.
cp -f gui/iperf3-gui.ps1 gui/iperf3-gui.cmd "$outdir/" 2>/dev/null || true

# Copy every non-system DLL the exe depends on (msys-2.0.dll, and anything else
# ldd reports outside of C:\Windows) so the folder is self-contained.
echo "==> Resolving runtime DLL dependencies"
ldd "$exe" \
  | grep -ioE '/[^ ]+\.dll' \
  | grep -ivE '/c/windows|/c/WINDOWS' \
  | sort -u \
  | while read -r dll; do
        if [ -f "$dll" ]; then
            echo "    + $(basename "$dll")"
            cp -f "$dll" "$outdir/"
        fi
    done

echo
echo "==> Done. Self-contained build is in: $outdir"
echo "    Contents:"
ls -1 "$outdir" | sed 's/^/      /'
echo
echo "    Copy that folder to any Windows machine and run, e.g.:"
echo "      iperf3.exe -s --nat -p 5201            (server)"
echo "      iperf3.exe -c HOST -p 5201 --nat -R    (client behind NAT, download test)"
