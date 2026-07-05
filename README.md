# FPGA Game Project & NeoV32 Bootloader

This repository contains a hardware/software co-design for an FPGA-based game engine limited to **36 Kb BRAM**. To bypass memory constraints, the project uses a custom video generator (Tilemap & Sprite engine) and a tiny Rust-based bootloader embedded directly within the FPGA bitstream.

All orchestration—from building software targets to hardware synthesis, USB bridging, and serial flashing—is handled by our custom repository tool: `ent`.

---

## Prerequisites & Development Environment

The entire toolchain (GHDL, NextPNR, Yosys, Rust RISC-V targets, OpenFPGALoader, Python dependencies) is fully managed via **Nix**.

To drop into the development shell with all required host tools:

```bash
nix develop

```

### WSL 2 Hardware Bridging (Required for Windows Hosts)

Because the FPGA toolchain runs inside a Linux environment, WSL 2 requires an active USB bridge to communicate with your physical board (e.g., Digilent Basys3).

1. **Configure WSL Permissions (First-time setup inside Ubuntu):**
Ensure `udev` rules grant your user interface access to the FTDI JTAG chip:

```bash
sudo nano /etc/udev/rules.d/99-ftdi.rules
# Paste this line inside, then save and exit:
ATTRS{idVendor}=="0403", ATTRS{idProduct}=="6010", MODE="666", GROUP="plugdev"

# Reload the daemon
sudo service udev start
sudo udevadm control --reload-rules && sudo udevadm trigger

```

2. **Attach the Hardware Device (Every session):**
Connect your board via USB, then use `ent` to automate the `usbipd` attachment from the Windows host into your WSL environment:

```bash
ent attach

```

---

## Repository Structure

* `hardware/` — Contains the VHDL top-level code, custom video generator, and the `neorv32` processor submodule.
* `software/` — A Rust workspace containing:
* `bootloader` — The minimalist primary bootloader (embedded into BRAM).
* `application` — The actual game logic.
* `pac / library` — Low-level hardware abstraction layer for the custom FPGA peripherals.


* `scripts/` — Internal data translation and serial link helpers.

---

## Development Workflow

The deployment workflow is fully orchestrated by `ent`. You can manage targets individually or trigger the complete automation pipeline in a single command.

```
ent clean ➔ ent build ➔ ent program ➔ ent flash ➔ ent connect

```

### The All-in-One Lifecycle Command

For a pristine full-stack deployment cycle (cleaning build caches, synthesizing the hardware bitstream, programming the JTAG, compiling/flashing the application, and launching the interactive serial console), simply run:

```bash
ent cycle

```

### Granular Execution Phases

#### Phase 1: Hardware & Bootloader Generation

The bootloader must be compiled in `release` mode to fit into the initial BRAM allocation embedded inside the FPGA bitstream.

1. **Synthesize the Infrastructure:**
Compiles the bootloader target, converts it to Intel Hex format, and runs synthesis tools:

```bash
ent build hardware

```

2. **Run Simulations & Testing:**
Routes verification simulation tests through the toolchain shell:

```bash
ent test

```

3. **Program the FPGA Bitstream:**
Flashes the synthesized hardware configuration image onto the board via JTAG:

```bash
ent program

```

#### Phase 2: Application Development Loop

Once the hardware and bootloader are flashed onto the FPGA, you do not need to re-synthesize the bitstream to iterate on your game. You simply stream the application binary over UART.

1. **Build and Flash the Game Application:**
Compiles the application workspace using aggressive release optimizations and streams the binary image directly to the board over the serial wire:

```bash
ent flash

```

2. **Connect to the Console:**
Open an interactive UART monitoring session via `tio` to view game diagnostics or interact with console utilities:

```bash
ent connect

```

---

## Important Memory Constraints

> ⚠️ **Memory Warning:** The hardware design operates with an absolute limit of **36 Kb of BRAM**.
> * Never compile software components without the release profile optimization flag. `ent` enforces this under the hood during builds and flashes.
> 
>
