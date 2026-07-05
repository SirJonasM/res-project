#!/usr/bin/env bash

# Automatically resolve the root directory where flake.nix / .git lives
find-root() {
	git rev-parse --show-toplevel 2>/dev/null || pwd
}

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

# --- Core Build Implementations ---

# Build everything: Bootloader hex, app binary, and hardware synthesis
build-all() {
	echo "🏗️ Starting full build pipeline..."
	build-bootloader
	build-app
	build-hardware
}

# Build just the application firmware and extract app.bin
build-app() {
	echo "🔨 Building application workspace..."
	mkdir -p "$BUILD_DIR"
	(cd "$ROOT/software" && cargo build -p application --release)
	(cd "$ROOT/software" && cargo objcopy -p application --release -- -O binary "$BUILD_DIR/app.bin")
}

# Build just the bootloader and translate it to firmware.hex
build-bootloader() {
	echo "--- Compiling Bootloader Core Firmware (Rust) ---"
	mkdir -p "$BUILD_DIR"
	(cd "$ROOT/software" && cargo build -p bootloader --release)
	
	echo "--- Extracting Raw Machine Binary Image ---"
	riscv64-none-elf-objdump -d "$ELF_OUT" > "$BUILD_DIR/firmware.asm"
	riscv64-none-elf-objcopy -O binary -R .eh_frame -R .riscv.attributes -R .comment "$ELF_OUT" "$BIN_FILE"

	echo "--- Transforming Binary to Intel/Verilog Word Hex ---"
	python3 "$SCRIPTS_DIR/hex.py" "$BIN_FILE" "$HEX_FILE"
}

# Run the hardware synthesis pipeline using the generated bootloader firmware.hex
build-hardware() {
	if [ ! -f "$HEX_FILE" ]; then
		echo "⚠️ firmware.hex missing. Building bootloader dependencies first..."
		build-bootloader
	fi
	echo "--- Running Hardware Synthesis Pipeline ---"
	run-toolchain make -C "$ROOT/hardware" all
}

# --- Core Clean Implementations ---

# Purge all build targets, software compilation targets, and hardware runs
clean-all() {
    echo "🧹 Cleaning down the whole stack..."
    clean-hardware
    
    # Running plain cargo clean resets the entire target workspace completely
    (cd "$ROOT/software" && cargo clean)
    rm -rf "$BUILD_DIR"
    echo "✅ Complete workspace clean complete."
}

# Just clean the hardware synthesis workspace
clean-hardware() {
    echo "🧹 Cleaning hardware files..."
    run-toolchain make -C "$ROOT/hardware" clean
}

# Clean the application artifacts and app.bin targets
clean-app() {
    echo "🧹 Cleaning application artifacts..."
    (cd "$ROOT/software" && cargo clean )
    rm -f "$BUILD_DIR/app.bin"
}

# Clean hardware files, bootloader artifacts, and bootloader targets in build
clean-bootloader() {
    echo "🧹 Cleaning bootloader targets and hardware environment..."
    clean-hardware
    (cd "$ROOT/software" && cargo clean -p bootloader)
    rm -f "$HEX_FILE" "$BIN_FILE" "$BUILD_DIR/firmware.asm"
}

# --- Other Utility Routines ---

# Route hardware simulation/testing steps through the toolchain shell
test-hardware() {
	mkdir -p "$BUILD_DIR"
	if [ ! -f "$HEX_FILE" ]; then
		build-bootloader
	fi
	echo "🔬 Running Hardware Test Suite..."
	run-toolchain make -C "$ROOT/hardware" FIRMWARE_HEX="$HEX_FILE" test
}

# Route FPGA board programming through the toolchain shell
program-fpga() {
	echo "⚡ Programming FPGA Board..."
	run-toolchain make -C "$ROOT/hardware" program
}

# Connect to the FPGA UART serial console using tio
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

# Compile the application via objcopy and send it down the wire over serial
flash-app() {
	build-app
	echo "📡 Transferring app.bin via serial link..."
	python3 "$ROOT/scripts/pyserial.py" "$BUILD_DIR/app.bin"
	connect-uart
}

# Attach the FPGA USB hardware device from Windows to WSL using usbipd
# Automatically discover and attach the Digilent USB serial converters from Windows to WSL
attach-usb() {
    echo "🔍 Scanning Windows host for Digilent USB Serial Converters..."

    # Call the Windows binary directly, drop trailing CRs, search for the description, and parse the first column
    BUS_IDS=$(usbipd.exe list 2>/dev/null | tr -d '\r' | awk '
        /USB Serial Converter/ { print $1 }
    ')

    if [ -z "$BUS_IDS" ]; then
        echo "❌ Error: No matching 'USB Serial Converter' found in 'usbipd list'."
        return 1
    fi

    # Loop through found IDs (handles boards that present separate A and B interface links)
    for busid in $BUS_IDS; do
        echo "🔌 Attaching Bus ID: $busid to WSL..."
        powershell.exe -Command "Start-Process usbipd -ArgumentList 'attach --wsl --busid $busid' -Verb RunAs"
    done
}

# Display this help menu showing all available development shortcuts
help-fpga() {
	echo "=========================================================="
	echo "🔨 FPGA Development Utilities (Project Root: $ROOT)"
	echo "=========================================================="
	echo "  fpga build [sub]   - Build everything, app, bootloader, or hardware (Defaults to all)"
	echo "  fpga clean [sub]   - Clean everything, app, bootloader, or hardware (Defaults to all)"
	echo "  fpga test          - Route hardware simulation/testing steps through toolchain shell"
	echo "  fpga program       - Route FPGA board programming through the toolchain shell"
	echo "  fpga flash         - Compile application and send down wire over serial link"
	echo "  fpga connect       - Connect to the FPGA UART serial console using tio"
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
	test) 		  shift; test-hardware "$@" ;;
	program)	  shift; program-fpga "$@" ;;
	connect)      shift; connect-uart "$@" ;;
	flash)        shift; flash-app "$@" ;;
	attach)       shift; attach-usb "$@" ;; 
	help|--help|-h|"") help-fpga ;;
	*) echo "Unknown command: $1. Run 'fpga help' for shortcuts." ; exit 1 ;;
esac
