# --- Top-Level Orchestrator Makefile ---

# Source tracking for incremental compilation
BOOTLOADER_SRCS := $(wildcard software/bootloader/src/**/*.rs) software/Cargo.toml software/bootloader/Cargo.toml software/bootloader/boot.ld software/.cargo/config.toml
ELF_OUT         := software/target/riscv32i-unknown-none-elf/release/bootloader
HEX_FILE        := hardware/firmware.hex
BIN_FILE        := hardware/firmware.bin

.PHONY: all test program clean

# Default rule: Build firmware, convert, and run synthesis
all: $(HEX_FILE)
	nix develop github:openxc7/toolchain-nix/0.7.0 --command make -C hardware all

# Route testing through the hardware nix environment shell
test: $(HEX_FILE)
	riscv64-none-elf-objdump -d $(ELF_OUT) > firmware.asm
	nix develop github:openxc7/toolchain-nix/0.7.0 --command make -C hardware test

# Route programming through the hardware nix environment shell
program:
	nix develop github:openxc7/toolchain-nix/0.7.0 --command make -C hardware program

# 1. Process flat binary into FPGA-ready hexadecimal format using dynamic arguments
$(HEX_FILE): $(BIN_FILE)
	@echo "--- Transforming Binary to Intel/Verilog Word Hex ---"
	python3 hex.py $(BIN_FILE) $(HEX_FILE)

# 2. Extract raw machine binary using local cross-compile utility
$(BIN_FILE): $(ELF_OUT)
	@echo "--- Extracting Raw Machine Binary Image ---"
	riscv64-none-elf-objdump -d $(ELF_OUT) > firmware.asm
	riscv64-none-elf-objcopy -O binary -R .eh_frame -R .riscv.attributes -R .comment $< $@

# 3. Natively compile the Rust project via your local toolchain
$(ELF_OUT): $(BOOTLOADER_SRCS)
	@echo "--- Compiling Bootloader Core Firmware (Rust) ---"
	cd software && cargo build -p bootloader --release

# Clean out everything up and down the stack
clean:
	rm -f $(BIN_FILE) $(HEX_FILE)
	cd software && cargo clean
	nix develop github:openxc7/toolchain-nix/0.7.0 --command make -C hardware clean
