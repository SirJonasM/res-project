---

### Updated `README.md`
# FPGA Game Project & NeoV32 Bootloader

This repository contains a hardware/software co-design for an FPGA-based game engine limited to **36 Kb BRAM**. To bypass memory constraints, the project uses a custom video generator (Tilemap & Sprite engine) and a tiny Rust-based bootloader embedded directly within the FPGA bitstream.

---

## Prerequisites & Development Environment

The entire toolchain (GHDL, NextPNR, Yosys, Rust RISC-V targets, OpenFPGALoader, Python dependencies) is fully managed via **Nix**. 

To drop into the development shell with all required host tools:
```bash
nix develop

```

### WSL 2 Hardware Bridging (Required for Windows Hosts)

Because the FPGA toolchain runs inside a Linux environment, WSL 2 requires an active USB bridge to communicate with your physical board (e.g., Digilent Basys3).

1. **Install `usbipd-win` on Windows** via Administrator PowerShell:
```powershell
winget install usbipd

```


2. **Configure WSL Permissions (First-time setup inside Ubuntu):**
Ensure `udev` rules grant your user interface access to the FTDI JTAG chip:
```bash
sudo nano /etc/udev/rules.d/99-ftdi.rules
# Paste this line inside, then save and exit:
ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", MODE="666", GROUP="plugdev"

# Reload the daemon
sudo service udev start
sudo udevadm control --reload-rules && sudo udevadm trigger

```


3. **Attach the Hardware Device (Every session):**
Connect your board via USB, then open an **Administrator PowerShell on Windows** to forward the port:
```powershell
usbipd list
# Find the BUSID for "USB Serial Converter A, USB Serial Converter B" (e.g., 4-7)
usbipd attach --wsl --busid <BUSID>

```

---

## Repository Structure

* `hardware/` — Contains the VHDL top-level code, custom video generator, and the `neorv32` processor submodule.
* `software/` — A Rust workspace containing:
* `bootloader` — The minimalist primary bootloader (embedded into BRAM).
* `application` — The actual game logic.
* `pac / library` — Low-level hardware abstraction layer for the custom FPGA peripherals.



---

## Development Workflow

The deployment workflow is split into two phases: **Hardware Synthesis** (infrequent) and **Application Upload** (frequent development loop).

```
1. Build Bootloader ➔ 2. Synthesize & Flash FPGA ➔ 3. Build App Bin ➔ 4. Stream via Serial

```

### Phase 1: Hardware & Bootloader Generation

The bootloader must be compiled in `release` mode to fit into the initial BRAM allocation embedded inside the FPGA bitstream. The root-level orchestrator `Makefile` handles the execution pipeline across target Nix environments automatically.

1. **Synthesize and Generate Bitstream:**
Compiles the local Rust bootloader project, processes the flat binary image into an FPGA-ready hex format, and runs synthesis tools:
```bash
make

```


2. **Run Simulations & Testing:**
Routes simulation validation checks through the openXC7 framework:
```bash
make test

```


3. **Program the FPGA:**
Flashes the generated bitstream directly onto the attached board over the shared JTAG channel:
```bash
make program

```

### Phase 2: Application Development Loop

Once the hardware and bootloader are flashed onto the FPGA, you do not need to re-synthesize the bitstream to update your game. You simply stream the application binary over UART.

1. **Build the Game Application:**
*(Crucial to use `--release` due to the strict 36 Kb memory limit)*
```bash
cd software
cargo build --release -p application

```


2. **Extract the Raw Binary:**
Convert the compiled ELF target into a flat binary image at the project root:
```bash
cargo objcopy -p application --release -- -O binary ../app.bin
cd ..

```


3. **Upload and Execute:**
Run the Python deployment script to send `app.bin` over the serial interface. The embedded bootloader will catch the binary, load it into the remaining RAM, and drop you directly into an interactive UART session:
```bash
python pyserial.py

```

---

## Important Memory Constraints

 [!WARNING]
 **Memory Warning:** The design operates with only 36 Kb of BRAM.
 * Always use `--release` for software builds.
 
 

