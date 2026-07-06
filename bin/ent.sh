#!/usr/bin/env bash

# Global UI Control Flags
VERBOSE=false
VERSION=false
LOG_FILE="/dev/null"
DEPTH=0 

SUBCOMMANDS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION=true; shift ;;
        -v|--verbose) VERBOSE=true; shift ;;
        -l|--log-file) LOG_FILE="$2"; shift 2 ;;
        *) SUBCOMMANDS+=("$1"); shift ;;
    esac
done
set -- "${SUBCOMMANDS[@]}"

# Handle version string print request early
if [ "$VERSION" = true ]; then
    echo "ent // Forest-Orchestrated Hardware Utilities - version 0.1.0"
    exit 0
fi

find-root() { git rev-parse --show-toplevel 2>/dev/null || pwd; }
ROOT=$(find-root)
SCRIPTS_DIR="$ROOT/scripts"
BUILD_DIR="$ROOT/build"
HEX_FILE="$BUILD_DIR/firmware.hex"
BIN_FILE="$BUILD_DIR/firmware.bin"

run-toolchain() {
    local SYSTEM
    SYSTEM=$(nix eval --raw nixpkgs#stdenv.hostPlatform.system)
    nix develop "github:openxc7/toolchain-nix/0.7.0#devShell.$SYSTEM" --command "$@"
}

# --- UI Formatting Engine ---

log-step() {
    local MSG="$1"
    local INDENT=""
    for ((i=0; i<DEPTH; i++)); do INDENT+="    "; done
    echo "${INDENT}${MSG}"
}

run-task() {
    local MSG="$1"
    shift
    
    local INDENT=""
    if [ $DEPTH -gt 0 ]; then
        for ((i=0; i<$((DEPTH-1)); i++)); do INDENT+="    "; done
        INDENT+="    └─▶ "
    else
        for ((i=0; i<DEPTH; i++)); do INDENT+="    "; done
    fi

    if [ "$VERBOSE" = true ]; then
        echo "${INDENT} -> $MSG"
        "$@"
        return $?
    fi

    echo -n "${INDENT}$MSG... "
    
    if [ "$LOG_FILE" != "/dev/null" ]; then
        echo "=== Task: $MSG ===" >> "$LOG_FILE"
        "$@" >> "$LOG_FILE" 2>&1 &
    else
        "$@" > /dev/null 2>&1 &
    fi
    
    local PID=$!
    local SPINNER='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    while kill -0 $PID 2>/dev/null; do
        for (( i=0; i<${#SPINNER}; i++ )); do
            sleep 0.1
            printf "\b%s" "${SPINNER:$i:1}"
        done
    done
    
    wait $PID
    local STATUS=$?
    
    if [ $STATUS -eq 0 ]; then
        printf "\b\033[32m✔ Done\033[0m\n"
    else
        printf "\b\033[31m✘ Failed (Exit Code: $STATUS)\033[0m\n"
        exit 1
    fi
}

# --- Raw Operational Tasks (No Logs/Headers Inside) ---

_build-bootloader-raw() {
    mkdir -p "$BUILD_DIR"
    run-task "Compiling Bootloader" bash -c "cd '$ROOT/software' && cargo build -p bootloader --release"
    run-task "Generating Assembly text dump" bash -c "cd '$ROOT/software' && cargo objdump -p bootloader --release -- -d > '$BUILD_DIR/firmware.asm'"
    run-task "Extracting Binary image" bash -c "cd '$ROOT/software' && cargo objcopy -p bootloader --release -- -O binary -R .eh_frame -R .riscv.attributes -R .comment '$BIN_FILE'"
    run-task "Converting to Intel Hex format" python3 "$SCRIPTS_DIR/hex.py" "$BIN_FILE" "$HEX_FILE"
}

_build-app-raw() {
    mkdir -p "$BUILD_DIR"
    run-task "Compiling Application" bash -c "cd '$ROOT/software' && cargo build -p application --release"
    run-task "Generating Assembly text dump" bash -c "cd '$ROOT/software' && cargo objdump -p application --release -- -d > '$BUILD_DIR/app.asm'"
    run-task "Extracting Binary image" bash -c "cd '$ROOT/software' && cargo objcopy -p application --release -- -O binary '$BUILD_DIR/app.bin'"
}

_build-hardware-raw() {
    if [ ! -f "$HEX_FILE" ]; then
        log-step "firmware.hex missing. Resolving bootloader target first..."
        local DEPTH=$((DEPTH + 1))
        _build-bootloader-raw
    fi
    run-task "Running Hardware Synthesis Pipeline" run-toolchain make -C "$ROOT/hardware" all
}

_clean-hardware-raw() {
    run-task "Cleaning hardware workspaces" run-toolchain make -C "$ROOT/hardware" clean
}

_clean-bootloader-raw() {
    _clean-hardware-raw
    run-task "Purging bootloader target cache" bash -c "cd '$ROOT/software' && cargo clean -p bootloader"
    rm -f "$BUILD_DIR"/firmware.*
}

_clean-app-raw() {
    run-task "Purging application target cache" bash -c "cd '$ROOT/software' && cargo clean -p application"
    rm -f "$BUILD_DIR"/app.*
}

_flash-app-raw() {
    run-task "Uploading binary chunks over serial" python3 "$ROOT/scripts/pyserial.py" "$BUILD_DIR/app.bin"
}

_program-fpga-raw() {
    run-task "Programming Bitstream via JTAG" run-toolchain make -C "$ROOT/hardware" program
}

# --- Standalone Target Commands (Used by direct CLI invokations) ---

build-bootloader() { log-step "Building Bootloader Structure:"; local DEPTH=$((DEPTH + 1)); _build-bootloader-raw; }
build-app()        { log-step "Building Application Structure:"; local DEPTH=$((DEPTH + 1)); _build-app-raw; }
build-hardware()   { log-step "Running Hardware Stack:"; local DEPTH=$((DEPTH + 1)); _build-hardware-raw; }

build-all() {
    log-step "Starting full build pipeline..."
    local DEPTH=$((DEPTH + 1))
    build-bootloader
    build-app
    build-hardware
}

clean-hardware()   { log-step "Cleaning hardware targets:"; local DEPTH=$((DEPTH + 1)); _clean-hardware-raw; }
clean-bootloader() { log-step "Removing Bootloader workspaces:"; local DEPTH=$((DEPTH + 1)); _clean-bootloader-raw; }
clean-app()        { log-step "Removing Application workspaces:"; local DEPTH=$((DEPTH + 1)); _clean-app-raw; }

clean-all() {
    log-step "Purging entire project development tree..."
    local DEPTH=$((DEPTH + 1))
    _clean-hardware-raw
    run-task "Purging Rust Workspace Cache" bash -c "cd '$ROOT/software' && cargo clean"
    rm -rf "$BUILD_DIR"
}

test-hardware() {
    mkdir -p "$BUILD_DIR"
    if [ ! -f "$HEX_FILE" ]; then build-bootloader; fi
    log-step "Initializing Verification Hardware Tests:"
    local DEPTH=$((DEPTH + 1))
    run-task "Running Hardware Test Suite" run-toolchain make -C "$ROOT/hardware" FIRMWARE_HEX="$HEX_FILE" test
}

program-fpga() {
    log-step "Initiating FPGA Configuration Link:"
    local DEPTH=$((DEPTH + 1))
    run-task "Programming Bitstream via JTAG" run-toolchain make -C "$ROOT/hardware" program
}

connect-uart() {
    local DEVICE=""
    for f in /dev/serial/by-id/usb-Digilent_*if01*; do [ -e "$f" ] && DEVICE="$f" && break; done
    if [ -z "$DEVICE" ]; then
        for f in /dev/serial/by-id/usb-Digilent_*; do [ -e "$f" ] && DEVICE="$f" && break; done
    fi
    if [ -z "$DEVICE" ]; then
        echo "Error: Digilent USB serial device not found."
        exit 1
    fi
    log-step "Connecting UART console via $DEVICE..."
    exec tio -b 115200 -d 8 -p none --stopbits 1 "$DEVICE" 
}

flash-app() {
    build-app
    _program-fpga-raw
    log-step "Uploading Application image over serial connection:"
    local DEPTH=$((DEPTH + 1))
    _flash-app-raw
}

attach-usb() {
    log-step "Scanning Windows host for Digilent USB Serial Converters..."
    BUS_IDS=$(usbipd.exe list 2>/dev/null | tr -d '\r' | awk '/USB Serial Converter/ { print $1 }')
    if [ -z "$BUS_IDS" ]; then
        echo "Error: No matching USB converter found."
        return 1
    fi
    for busid in $BUS_IDS; do
        log-step "Attaching Bus ID: $busid to WSL..."
        powershell.exe -Command "Start-Process usbipd -ArgumentList 'attach --wsl --busid $busid' -Verb RunAs"
    done
}

# --- The Orchestrated 4-Stage Lifecycle Engine ---

run-cycle() {
    log-step "Initiating Full Stack Deployment Cycle..."
    local DEPTH=$((DEPTH + 1))
    
    # Stage 1: Clean Everything
    log-step "STAGE 1/4: Cleaning Project Workspace Tree..."
    (
        local DEPTH=$((DEPTH + 1))
        _clean-hardware-raw
        run-task "Purging Rust Workspace Cache" bash -c "cd '$ROOT/software' && cargo clean"
        rm -rf "$BUILD_DIR"
    )

    # Stage 2: Unified Serial Build Pipeline
    log-step "STAGE 2/4: Running Full Production Build Pipeline..."
    (
        local DEPTH=$((DEPTH + 1))
        log-step "Building Bootloader Infrastructure:"
        ( local DEPTH=$((DEPTH + 1)); _build-bootloader-raw; )
        
        log-step "Building Application Firmware Structure:"
        ( local DEPTH=$((DEPTH + 1)); _build-app-raw; )
        
        log-step "Running System Hardware Stack:"
        ( local DEPTH=$((DEPTH + 1)); _build-hardware-raw; )
    )

    # Stage 3: Program & Deploy to Board Target
    log-step "STAGE 3/4: Programming Bitstream and Flashing Software..."
    (
        local DEPTH=$((DEPTH + 1))
        run-task "Programming Bitstream via JTAG" run-toolchain make -C "$ROOT/hardware" program
        
        log-step "Uploading Application image over serial connection:"
        (
            local DEPTH=$((DEPTH + 1))
            _flash-app-raw
        )
    )

    # Stage 4: Enter Interactive Monitoring State
    log-step "STAGE 4/4: Connecting Interactive UART Terminal Console..."
    (
        local DEPTH=$((DEPTH + 1))
        connect-uart
    )
}

help-fpga() {
    echo "=========================================================="
    echo "  ent // Forest-Orchestrated Hardware Utilities ($ROOT)"
    echo "=========================================================="
    echo "  Global Options:"
    echo "    --version         Print build tool version"
    echo "    -v, --verbose       Stream raw tool outputs directly"
    echo "    -l, --log-file F    Redirect detailed standard log traces to file F"
    echo ""
    echo "  Commands:"
    echo "    ent build [sub]   - Shape targets: all, app, bootloader, or hardware"
    echo "    ent clean [sub]   - Clear targets: all, app, bootloader, or hardware"
    echo "    ent test          - Run verification tests inside the toolchain shell"
    echo "    ent program       - Pass compiled hardware bitstreams down via JTAG"
    echo "    ent flash         - Spin up the application and pass over serial link"
    echo "    ent connect       - Open interactive serial communication via tio"
    echo "    ent attach        - Root out Digilent devices from Windows into WSL"
    echo "    ent cycle         - Complete awakening: clean -> build -> program -> flash -> connect"
    echo "=========================================================="
}

# Subcommand Router
case "$1" in
    build)
        shift
        case "$1" in
            app)        build-app ;;
            bootloader) build-bootloader ;;
            hardware)   build-hardware ;;
            all|"")     build-all ;;
            *) echo "Unknown build target: $1. Choose: all, app, bootloader, hardware" ; exit 1 ;;
        esac
        ;;
    clean)
        shift
        case "$1" in
            app)        clean-app ;;
            bootloader) clean-bootloader ;;
            hardware)   clean-hardware ;;
            all|"")     clean-all ;;
            *) echo "Unknown clean target: $1. Choose: all, app, bootloader, hardware" ; exit 1 ;;
        esac
        ;;
    test)    shift; test-hardware "$@" ;;
    program) shift; program-fpga "$@" ;;
    connect) shift; connect-uart "$@" ;;
    flash)   shift; flash-app "$@" ;;
    attach)  shift; attach-usb "$@" ;; 
    cycle)   shift; run-cycle "$@" ;;
    help|--help|-h|"") help-fpga ;;
    *) echo "Unknown command: $1. Run 'ent help' for shortcuts." ; exit 1 ;;
esac
