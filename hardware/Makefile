# --- Project Configuration ---
FAMILY      = artix7
PART        = xc7a35tcpg236-1
BOARD       = basys3
PROJECT     ?= main
TEST        ?= main_tb
CONSTRAINTS = constraints.xdc
BUILD_DIR   = build
SIM_DIR     = sim_build

# --- Paths & Tooling ---
CHIPDB      ?= chipdb
DBPART      = $(shell echo ${PART} | sed -e 's/-[0-9]//g')
PRJXRAY_DB_DIR ?= ${NEXTPNR_XILINX_DIR}/external/prjxray-db
NEXTPNR_XILINX_PYTHON_DIR ?= ${NEXTPNR_XILINX_DIR}/python
PYPY3       ?= pypy3

# --- GHDL & Source Logic ---
GHDL_OPTS    ?= --std=08 -fsynopsys
TOP_MODULE   = ${PROJECT}

# Explicit source directory definitions matching your working manual commands
SRC_DIR      = src
NEORV32_DIR  = risc_core/rtl/core

# Source lists grouped by architecture/library
NEORV32_SOURCES = $(wildcard $(NEORV32_DIR)/*.vhd)
PERIPH_SOURCES  = $(wildcard $(SRC_DIR)/*.vhd)
TOP_SOURCES     = $(PROJECT).vhd

# --- Build Settings ---
XDC         = ${CONSTRAINTS}
JTAG_LINK   = --board ${BOARD}

.PHONY: all clean program pnrclean test

all: ${BUILD_DIR}/${PROJECT}.bit

${BUILD_DIR}:
	mkdir -p ${BUILD_DIR}

# 1. Synthesis (Combined into a single flawless line for Yosys)
${BUILD_DIR}/${PROJECT}.json: ${NEORV32_SOURCES} ${PERIPH_SOURCES} ${TOP_SOURCES} | ${BUILD_DIR}
	yosys -m ghdl -p " \
		ghdl ${GHDL_OPTS} --work=lib ${PERIPH_SOURCES} --work=neorv32 ${NEORV32_SOURCES} --work=work ${TOP_SOURCES} -e ${TOP_MODULE} ; \
		synth_xilinx -flatten -arch xc7 -top ${TOP_MODULE} ; \
		write_json $@"

# 2. ChipDB Generation
${CHIPDB}/${DBPART}.bin:
	@mkdir -p ${CHIPDB}
	${PYPY3} ${NEXTPNR_XILINX_PYTHON_DIR}/bbaexport.py --device ${PART} --bba ${DBPART}.bba
	bbasm -l ${DBPART}.bba ${CHIPDB}/${DBPART}.bin
	rm -f ${DBPART}.bba

# 3. Place and Route
${BUILD_DIR}/${PROJECT}.fasm: ${BUILD_DIR}/${PROJECT}.json ${CHIPDB}/${DBPART}.bin ${XDC} | ${BUILD_DIR}
	nextpnr-xilinx --chipdb ${CHIPDB}/${DBPART}.bin --xdc ${XDC} --json $< --fasm $@ ${PNR_ARGS}

# 4. FASM to Frames
${BUILD_DIR}/${PROJECT}.frames: ${BUILD_DIR}/${PROJECT}.fasm | ${BUILD_DIR}
	fasm2frames --part ${PART} --db-root ${PRJXRAY_DB_DIR}/${FAMILY} $< > $@

# 5. Frames to Bitstream
${BUILD_DIR}/${PROJECT}.bit: ${BUILD_DIR}/${PROJECT}.frames | ${BUILD_DIR}
	xc7frames2bit --part_file ${PRJXRAY_DB_DIR}/${FAMILY}/${PART}/part.yaml --part_name ${PART} --frm_file $< --output_file $@

# --- Simulation Target ---
test:
	mkdir -p ${SIM_DIR}
	# Clear out any residual compiled tracking data from prior runs
	ghdl --clean
	# Step A: Import your peripherals into 'lib'
	ghdl -i ${GHDL_OPTS} --work=lib ${PERIPH_SOURCES}
	# Step B: Import core processor files into 'neorv32'
	ghdl -i ${GHDL_OPTS} --work=neorv32 ${NEORV32_SOURCES}
	# Step C: Import top module and testbench into the default 'work' namespace
	ghdl -i ${GHDL_OPTS} ${TOP_SOURCES} $(TEST).vhd
	# Step D: Let GHDL determine cross-library compilation order and build
	ghdl -m ${GHDL_OPTS} ${TEST}
	# Step E: Run simulation and output VCD track (Updated to 2us as per your configuration)
	ghdl -r ${GHDL_OPTS} ${TEST} --vcd=${SIM_DIR}/waveform.vcd --stop-time=2ms
	@echo "Simulation complete. Waveform saved to ${SIM_DIR}/waveform.vcd"

# --- Utilities ---
program:
	@if [ ! -f "${BUILD_DIR}/${PROJECT}.bit" ]; then \
		echo "❌ Error: Bitstream artifact missing (${BUILD_DIR}/${PROJECT}.bit). Run 'fpga build' first."; \
		exit 1; \
	fi
	openFPGALoader ${JTAG_LINK} --bitstream ${BUILD_DIR}/${PROJECT}.bit

clean:
	@rm -rf ${BUILD_DIR} ${SIM_DIR}
	ghdl --clean

pnrclean:
	rm -f ${BUILD_DIR}/*.fasm ${BUILD_DIR}/*.frames ${BUILD_DIR}/*.bit
