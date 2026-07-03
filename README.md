Hier ist eine strukturierte, professionelle und direkt einsatzbereite `README.md` für dein Repository. Sie nutzt Markdown-Elemente für eine optimale Lesbarkeit und fasst deinen gesamten Workflow exakt zusammen.

---

```markdown
# FPGA Game Project & NeoV32 Bootloader

This repository contains a hardware/software co-design for an FPGA-based game engine limited to **36 Kb BRAM**. To bypass memory constraints, the project uses a custom video generator (Tilemap & Sprite engine) and a tiny Rust-based bootloader embedded directly within the FPGA bitstream.

---

## 🛠️ Prerequisites & Development Environment

The entire toolchain (GHDL/Verilator, Rust RISC-V target, OpenFPGALoader, Python dependencies) is completely managed via **Nix**.

To drop into the development shell with all required tools:
```bash
nix develop

```

---

## 📁 Repository Structure

* `hardware/` — Contains the VHDL top-level code, custom video generator, and the `neorv32` processor submodule.
* `software/` — A Rust workspace containing:
* `bootloader` — The minimalist primary bootloader (embedded into BRAM).
* `application` — The actual game logic.
* `pac / library` — Low-level hardware abstraction layer for the custom FPGA peripherals.



---

## 🚀 Development Workflow

The deployment workflow split into two phases: **Hardware Synthesis** (infrequent) and **Application Upload** (frequent development loop).

```
[ Nix Develop ] ──> 1. Build Bootloader ──> 2. Synthesize & Flash Bitstream (FPGA)
                                                      │
[ Code Game ]   ──> 3. Build App Bin   ──> 4. Stream via Serial (Python) ──> Run!

```

### Phase 1: Hardware & Bootloader Generation

The bootloader must be compiled in `release` mode to fit into the initial BRAM allocation embedded inside the FPGA bitstream.

1. **Compile the Bootloader:**
```bash
cd software
cargo build --release -p bootloader
cd ..

```


2. **Run Simulations (Optional):**
```bash
make test

```


3. **Synthesize and Program the FPGA:**
This compiles the VHDL code (injecting the compiled bootloader binary into the bitstream) and flashes the FPGA board.
```bash
make
sudo make program

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
Run the Python deployment script to send `app.bin` over the serial interface. The embedded bootloader will catch the binary, load it into the remaining RAM, and drop you directly into an interactive UART session.
```bash
python pyserial.py

```



---

## ⚡ Important Memory Constraints

 ⚠️ **Memory Warning:** The design operates with only 36 Kb of BRAM.
 * Always use `--release` for software builds.
 * Avoid `core::fmt` or complex `println!` macros in default builds to prevent binary bloat (`section .text will not fit in region ram`).
 
