import serial
import struct
import sys

def send_packet(ser, cmd, offset, payload=b''):
    length = len(payload)
    # Pack header: Cmd (B), Length (H = 2 bytes), Offset (H = 2 bytes)
    header = struct.pack(">BHH", cmd, length, offset)
    
    # Calculate simple XOR checksum
    checksum = 0
    for byte in header + payload:
        checksum ^= byte
        
    # Send: Sync Byte + Header + Payload + Checksum
    ser.write(b'\xAA' + header + payload + bytes([checksum]))
    
    # Wait for ACK
    response = ser.read(1)
    return response == b'\x06'

# Open serial port
ser = serial.Serial('/dev/ttyUSB1', 115200, timeout=1)

with open("app.bin", "rb") as f:
    binary_data = f.read()

# Send data in 128-byte chunks
chunk_size = 128
for offset in range(0, len(binary_data), chunk_size):
    chunk = binary_data[offset:offset+chunk_size]
    print(f"Sending chunk at offset {offset}...")
    while not send_packet(ser, 0x01, offset, chunk):
        print("Retrying chunk due to error...")

# Tell bootloader to jump to app!
print("Booting application...")
if send_packet(ser, 0x02, 0):
    print("Boot command ACK received! Switching to terminal monitor mode...\n")
else:
    print("Boot command NACK received or timed out. Entering monitor mode anyway...\n")

# --- MONITOR MODE ---
# Change timeout to None so it blocks until data actually arrives from the FPGA
ser.timeout = None 

try:
    while True:
        # Read whatever characters are available in the serial buffer
        if ser.in_waiting > 0:
            # Read all buffered incoming bytes
            data = ser.read(ser.in_waiting)
            # Decode to text (handling invalid characters gracefully if memory gets corrupted)
            text = data.decode('utf-8', errors='replace')
            # Print to local stdout immediately without extra trailing newlines
            sys.stdout.write(text)
            sys.stdout.flush()
except KeyboardInterrupt:
    print("\n=================== MONITOR DISCONNECTED ===================")
    ser.close()
