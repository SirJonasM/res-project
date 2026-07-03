# bin_to_hex.py
import struct

with open("hardware/firmware.bin", "rb") as f_in, open("hardware/firmware.hex", "w") as f_out:
    bytes_data = f_in.read()
    # Pad to make sure it aligns to 4-byte boundaries
    while len(bytes_data) % 4 != 0:
        bytes_data += b'\x00'
        
    # Read 4 bytes at a time
    for i in range(0, len(bytes_data), 4):
        word = bytes_data[i:i+4]
        # Use '<I' for little-endian (Standard RISC-V memory organization)
        value = struct.unpack('<I', word)[0]
        f_out.write(f"{value:08X}\n")
