# bin/fpga-utils.sh

# 1. Your smart serial connection function
connect-uart() {
	# Default to if01, but fallback to if00 if if01 isn't found
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
		return 1
	fi

	echo "🔌 Connecting to UART via $DEVICE..."
	tio -b 115200 -d 8 -p even "$DEVICE"
}

