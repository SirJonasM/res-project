#!/usr/bin/env python3
import sys
import struct
import serial


def send_packet(ser, cmd, offset, payload=b''):
    length = len(payload)
    header = struct.pack(">BHH", cmd, length, offset)
    
    checksum = 0
    for byte in header + payload:
        checksum ^= byte
        
    ser.write(b'\xAA' + header + payload + bytes([checksum]))
    response = ser.read(1)
    return response == b'\x06'

def main():
    if len(sys.argv) < 2:
        sys.exit(2) # Missing file arg

    bin_path = sys.argv[1]

    try:
        with open(bin_path, "rb") as f:
            binary_data = f.read()
    except FileNotFoundError:
        sys.exit(3) # File missing

    try:
        # Configuration updated to match: tio -b 115200 -d 8 -p none --stopbits 1
        ser = serial.Serial(
            port='/dev/ttyUSB1',
            baudrate=115200,
            parity=serial.PARITY_NONE,
            bytesize=serial.EIGHTBITS,
            stopbits=serial.STOPBITS_ONE,
            timeout=1
        )
    except Exception:
        sys.exit(4) # Port connection failed

    chunk_size = 128
    for offset in range(0, len(binary_data), chunk_size):
        chunk = binary_data[offset:offset+chunk_size]
        
        retry_count = 0
        max_retries = 5
        while not send_packet(ser, 0x01, offset, chunk):
            retry_count += 1
            if retry_count >= max_retries:
                ser.close()
                sys.exit(5) # Data transmission failure

    # Trigger Execution Jump
    if send_packet(ser, 0x02, 0):
        ser.close()
        sys.exit(0) # Success!
    else:
        ser.close()
        sys.exit(6) # NACK on execute jump

if __name__ == "__main__":
    main()
