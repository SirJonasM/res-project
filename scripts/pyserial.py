#!/usr/bin/env python3
import sys
import struct
import serial

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

def main():
    if len(sys.argv) < 2:
        print("❌ Error: Missing binary file argument.")
        print("Usage: python3 pyserial.py <path_to_app.bin>")
        sys.exit(1)

    bin_path = sys.argv[1]

    try:
        with open(bin_path, "rb") as f:
            binary_data = f.read()
    except FileNotFoundError:
        print(f"❌ Error: File not found at '{bin_path}'")
        sys.exit(1)

    print(f"📡 Opening serial link on /dev/ttyUSB1 (115200, 8E1)...")
    try:
        # Match your exact tio settings: Even Parity (PARITY_EVEN), 8 Data Bits (EIGHTBITS)
        ser = serial.Serial(
            port='/dev/ttyUSB1', 
            baudrate=115200, 
            parity=serial.PARITY_EVEN, 
            bytesize=serial.EIGHTBITS, 
            timeout=1
        )
    except Exception as e:
        print(f"❌ Error: Could not open serial port /dev/ttyUSB1: {e}")
        sys.exit(1)

    # Send data in 128-byte chunks
    chunk_size = 128
    print(f"📦 Flashing binary ({len(binary_data)} bytes)...")
    
    for offset in range(0, len(binary_data), chunk_size):
        chunk = binary_data[offset:offset+chunk_size]
        
        retry_count = 0
        max_retries = 5
        while not send_packet(ser, 0x01, offset, chunk):
            retry_count += 1
            print(f"⚠️ Retrying chunk at offset {offset} ({retry_count}/{max_retries})...")
            if retry_count >= max_retries:
                print("❌ Flash Failure: Too many failed communication retries. Closing link.")
                ser.close()
                sys.exit(1)

    # Tell bootloader to jump to app
    print("🚀 Sending boot execution instruction...")
    if send_packet(ser, 0x02, 0):
        print("✅ Flash Success! Boot command ACK received. Connection cleanly closed.")
        ser.close()
        sys.exit(0)
    else:
        print("❌ Flash Failure: Boot command NACK received or timed out.")
        ser.close()
        sys.exit(1)

if __name__ == "__main__":
    main()
