#!/usr/bin/env python3
import sys
import struct

def main():
    if len(sys.argv) < 3:
        print("Usage: python3 bin_to_hex.py <input_bin> <output_hex>")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]

    with open(input_path, "rb") as f_in, open(output_path, "w") as f_out:
        bytes_data = f_in.read()
        
        # Efficiently pad to make sure it aligns to 4-byte boundaries
        remainder = len(bytes_data) % 4
        if remainder != 0:
            bytes_data += b'\x00' * (4 - remainder)
            
        # Read 4 bytes at a time
        for i in range(0, len(bytes_data), 4):
            word = bytes_data[i:i+4]
            # Use '<I' for little-endian (Standard RISC-V memory organization)
            value = struct.unpack('<I', word)[0]
            f_out.write(f"{value:08X}\n")

if __name__ == "__main__":
    main()
