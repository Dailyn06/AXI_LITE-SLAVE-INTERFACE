#!/usr/bin/env bash
# Usage: bash run.sh [--waves]
set -euo pipefail

SHOW_WAVES=false
case "${1:-}" in
    "") ;;
    --waves) SHOW_WAVES=true ;;
    *) echo "Usage: bash run.sh [--waves]" >&2; exit 2 ;;
esac
if (( $# > 1 )); then
    echo "Usage: bash run.sh [--waves]" >&2
    exit 2
fi

# Resolve sources relative to this script, regardless of the caller's directory.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TOP_MODULE=tb_axi_lite
for tool in verilator make g++; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Required tool not found: $tool" >&2
        exit 1
    fi
done

# A unique build directory avoids stale makefiles from other installations.
# Keep the build and waveform for inspection; no old output is deleted.
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/axi_lite_sim.XXXXXXXX")"
echo "Simulation artifacts: $BUILD_DIR"
trap 'echo "Simulation failed. Inspect artifacts in: $BUILD_DIR" >&2' ERR

verilator --binary --timing --trace -Wall -Wno-fatal \
    --top-module "$TOP_MODULE" \
    "$SCRIPT_DIR/axi_lite_slave.v" "$SCRIPT_DIR/tb_axi_lite.v" \
    -Mdir "$BUILD_DIR"

# Relative dump filenames are written into this run's fresh directory.
echo "Running simulation..."
(cd -- "$BUILD_DIR" && "./V${TOP_MODULE}")
echo "Simulation completed successfully."

WAVE_FILE="$BUILD_DIR/dump.vcd"
if [[ ! -f "$WAVE_FILE" ]]; then
    WAVE_FILE="$BUILD_DIR/${TOP_MODULE}.vcd"
fi
if [[ -f "$WAVE_FILE" ]]; then
    echo "Waveform: $WAVE_FILE"
    if [[ "$SHOW_WAVES" == true ]]; then
        if command -v gtkwave >/dev/null 2>&1; then
            gtkwave "$WAVE_FILE" >"$BUILD_DIR/gtkwave.log" 2>&1 &
            echo "GTKWave launched; log: $BUILD_DIR/gtkwave.log"
        else
            echo "GTKWave is unavailable; open the waveform after installing it." >&2
        fi
    fi
else
    echo "No waveform generated. Check the testbench dump settings."
fi
