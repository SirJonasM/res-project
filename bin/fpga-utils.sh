#!/usr/bin/env bash

# Global UI Control Flags
VERBOSE=false
LOG_FILE="/dev/null"

# Array to store non-flag arguments (the subcommands)
SUBCOMMANDS=()

# Process arguments out of order from anywhere in the command string
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -l|--log-file)
            LOG_FILE="$2"
            shift 2
            ;;
        *)
            SUBCOMMANDS+=("$1")
            shift
            ;;
    esac
done

# Reconstruct the positional parameters array using only subcommands
set -- "${SUBCOMMANDS[@]}"

# Automatically resolve the root directory where flake.nix / .git lives
find-root() {
    git rev-parse --show-toplevel 2>/dev/null || pwd
}
# ... (rest of the script remains completely identical)

ROOT=$(find-root)
SCRIPTS_DIR="$ROOT/scripts"
BUILD_DIR="$ROOT/build"
HEX_FILE="$BUILD_DIR/firmware.hex"
BIN_FILE="$BUILD_DIR/firmware.bin"
ELF_OUT="$ROOT/software/target/riscv32i-unknown-none-elf/release/bootloader"

# Helper to execute commands inside the openxc7 toolchain nix environment
run-toolchain() {
    local SYSTEM
    SYSTEM=$(nix eval --raw nixpkgs#stdenv.hostPlatform.system)
    nix develop "github:openxc7/toolchain-nix/0.7.0#devShell.$SYSTEM" --command "$@"
}

# --- Spinner & Logging Core Subsystem ---
# Executes a command and wraps it in a terminal spinner unless VERBOSE is active
run-task() {
    local MSG="$1"
    shift
    
    if [ "$VERBOSE" = true ]; then
        echo "➡️  $MSG"
        # Run natively directly on stdout/stderr
        "$@"
        return $?
    fi

    # Run in silent/log mode with loading animation
    echo -n "⏳ $MSG... "
    
    # Run the workload in the background, routing output to our target log destination
    if [ "$LOG_FILE" != "/dev/null" ]; then
        echo "=== Task: $MSG ===" >> "$LOG_FILE"
        "$@" >> "$LOG_FILE" 2>&1 &
    else
        "$@" > /dev/null 2>&1 &
    fi
    
    local PID=$!
    local SPINNER='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    
    # While the process is alive, cycle through the frames
    while kill -0 $PID 2>/dev/null; do
        for (( i=0; i<${#SPINNER}; i++ )); do
            sleep 0.1
            printf "\b%s" "${SPINNER:$i:1}"
        done
    done
    
    # Collect exit status code of the background process
    wait $PID
    local STATUS=$?
    
    if [ $STATUS -eq 0 ]; then
        printf "\b\033[32m✔ Done\033[0m\n"
    else
        printf "\b\033[31m✘ Failed\033[0m\n"
        if [ "$LOG_FILE" != "/dev/null" ]; then
            echo "❌ Task failed. Check details in $LOG_FILE"
        else
            echo "❌ Task failed. Run with --verbose (-v) to debug."
        fi
        exit 1
    fi
}

# --- Core Build Implementations ---

build-all() {
    echo "🏗️ Starting full build pipeline..."
    build-bootloader
    build-app
    build-hardware
}

build-app() {
    mkdir -p "$BUILD_DIR"
    run-task "Compiling Application Workspace (Rust)" bash -c "cd '$ROOT/software' && cargo build -p application --release"
    run-task "Extracting Application Binary via objcopy" bash -c "cd '$ROOT/software' && cargo objcopy -p application --release -- -O binary '$BUILD_DIR/app.bin'"
}

build-bootloader() {
    mkdir -p "$BUILD_DIR"
    run-task "Compiling Bootloader Core Firmware (Rust)" bash -c "cd '$ROOT/software' && cargo build -p bootloader --release"
    run-task "Generating Machine Binary & ASM Dumps" bash -c "riscv64-none-elf-objdump -d '$ELF_OUT' > '$BUILD_DIR/firmware.asm' && riscv64-none-elf-objcopy -O binary -R .eh_frame -R .riscv.attributes -R .comment '$ELF_OUT' '$BIN_FILE'"
    run-task "Transforming Binary to Intel Hex Format" python3 "$SCRIPTS_DIR/hex.py" "$BIN_FILE" "$HEX_FILE"
}

build-hardware() {
    if [ ! -f "$HEX_FILE" ]; then
        echo "⚠️ firmware.hex missing. Resolving bootloader dependencies first..."
        build-bootloader
    fi
    run-task "Running Yosys & nextpnr Hardware Synthesis Pipeline" run-toolchain make -C "$ROOT/hardware" all
}

# --- Core Clean Implementations ---

clean-all() {
    echo "🧹 Cleaning down the whole stack..."
    clean-hardware
    run-task "Purging Rust Workspace Cache" bash -c "cd '$ROOT/software' && cargo clean"
    rm -rf "$BUILD_DIR"
    echo "✅ Complete workspace clean complete."
}

clean-hardware() {
    run-task "Cleaning hardware synthesis workspaces" run-toolchain make -C "$ROOT/hardware" clean
}

clean-app() {
    run-task "Purging application profile build targets" bash -c "cd '$ROOT/software' && cargo clean"
    rm -f "$BUILD_DIR/app.bin"
}

clean-bootloader() {
    clean-hardware
    run-task "Purging bootloader target caches" bash -c "cd '$ROOT/software' && cargo clean -p bootloader"
    rm -f "$HEX_FILE" "$BIN_FILE" "$BUILD_DIR/firmware.asm"
}

# --- Other Utility Routines ---

test-hardware() {
    mkdir -p "$BUILD_DIR"
    if [ ! -f "$HEX_FILE" ]; then
        build-bootloader
    fi
    run-task "Running Hardware Test Suite" run-toolchain make -C "$ROOT/hardware" FIRMWARE_HEX="$HEX_FILE" test
}

program-fpga() {
    run-task "Programming Bitstream to FPGA Board via JTAG" run-toolchain make -C "$ROOT/hardware" program
}

connect-uart() {
    local DEVICE=""
    for f in /dev/serial/by-id/usb-Digilent_*if01*; do
        if [ -e "$f" ]; then DEVICE="$f"; break; fi
    done
    if [ -z "$DEVICE" ]; then
        for f in /dev/serial/by-id/usb-Digilent_*; do
            if [ -e "$f" ]; then DEVICE="$f"; break; fi
        done
    fi

    if [ -z "$DEVICE" ]; then
        echo "❌ Error: Digilent USB serial device not found."
        exit 1
    fi
    echo "🔌 Connecting to UART via $DEVICE..."
    exec tio -b 115200 -d 8 -p even "$DEVICE"
}

flash-app() {
    build-app
    echo "📡 Transferring app.bin via serial link..."
    python3 "$ROOT/scripts/pyserial.py" "$BUILD_DIR/app.bin"
    connect-uart
}

attach-usb() {
    echo "🔍 Scanning Windows host for Digilent USB Serial Converters..."
    BUS_IDS=$(usbipd.exe list 2>/dev/null | tr -d '\r' | awk '/USB Serial Converter/ { print $1 }')

    if [ -z "$BUS_IDS" ]; then
        echo "❌ Error: No matching 'USB Serial Converter' found in 'usbipd list'."
        return 1
    fi

    for busid in $BUS_IDS; do
        echo "🔌 Attaching Bus ID: $busid to WSL..."
        powershell.exe -Command "Start-Process usbipd -ArgumentList 'attach --wsl --busid $busid' -Verb RunAs"
    done
}

run-cycle() {
    echo "🔄 Initiating Full Stack Deployment Cycle..."
    clean-all
    build-all
    program-fpga
    flash-app
}

help-fpga() {
    echo "=========================================================="
    echo "🔨 FPGA Development Utilities (Project Root: $ROOT)"
    echo "=========================================================="
    echo "  Global Options:"
    echo "    -v, --verbose      Disable loading animation, stream raw terminal output"
    echo "    -l, --log-file F   Keep animation, but write detailed output logs to file F"
    echo ""
    echo "  Commands:"
    echo "    fpga build [sub]   - Build everything, app, bootloader, or hardware (Defaults to all)"
    echo "    fpga clean [sub]   - Clean everything, app, bootloader, or hardware (Defaults to all)"
    echo "    fpga test          - Route hardware simulation/testing steps through toolchain shell"
    echo "    fpga program       - Route FPGA board programming through the toolchain shell"
    echo "    fpga flash         - Compile application and send down wire over serial link"
    echo "    fpga connect       - Connect to the FPGA UART serial console using tio"
    echo "    fpga attach        - Find and forward USB serial devices from Windows host to WSL"
    echo "    fpga cycle         - Run complete pipeline: clean ➔ build ➔ program ➔ flash ➔ tio"
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
    *) echo "Unknown command: $1. Run 'fpga help' for shortcuts." ; exit 1 ;;
esac
