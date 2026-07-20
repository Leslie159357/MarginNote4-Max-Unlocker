#!/usr/bin/env python3
"""
Inject LC_LOAD_DYLIB into a Mach-O binary.
Usage: python3 inject.py <binary_path> <dylib_name>
"""
import struct, sys

def inject_dylib(binary_path, dylib_name_str):
    dylib_name = dylib_name_str.encode() + b'\x00'
    while len(dylib_name) % 8:
        dylib_name += b'\x00'

    with open(binary_path, 'rb') as f:
        data = bytearray(f.read())

    magic = struct.unpack_from('<I', data, 0)[0]
    assert magic == 0xFEEDFACF, f'Not MH_MAGIC_64: 0x{magic:x}'

    cputype, cpusubtype, filetype, ncmds, sizeofcmds = struct.unpack_from('<IIIII', data, 4)
    print(f'ncmds={ncmds} sizeofcmds={sizeofcmds}')

    # Build new LC_LOAD_DYLIB
    LC_LOAD_DYLIB = 0x35
    cmd_size = 4 + 4 + 16 + len(dylib_name)
    cmd_data = struct.pack('<II', LC_LOAD_DYLIB, cmd_size)
    cmd_data += struct.pack('<IIII', 16, 2, 0, 0)
    cmd_data += dylib_name
    print(f'New command: size={cmd_size}')

    lc_end = 32 + sizeofcmds
    remaining = data[lc_end:]
    data = data[:lc_end] + cmd_data + remaining

    # Update header
    struct.pack_into('<II', data, 16, ncmds + 1)
    struct.pack_into('<I', data, 20, sizeofcmds + cmd_size)

    # Update segment/section file offsets
    offset = 32
    for i in range(ncmds + 1):
        cmd = struct.unpack_from('<I', data, offset)[0]
        cmdsize = struct.unpack_from('<I', data, offset+4)[0]
        if cmd == 0x19:  # LC_SEGMENT_64
            segname = data[offset+8:offset+24].split(b'\x00')[0].decode()
            old_fileoff = struct.unpack_from('<Q', data, offset+40)[0]
            if old_fileoff >= lc_end:
                new_fileoff = old_fileoff + cmd_size
                struct.pack_into('<Q', data, offset+40, new_fileoff)
                print(f'  {segname}: 0x{old_fileoff:x} -> 0x{new_fileoff:x}')
                nsects = struct.unpack_from('<I', data, offset+64)[0]
                sect_off = offset + 72
                for _ in range(nsects):
                    sf = struct.unpack_from('<Q', data, sect_off+48)[0]
                    if sf >= lc_end:
                        struct.pack_into('<Q', data, sect_off+48, sf + cmd_size)
                    sect_off += 80
        offset += cmdsize

    # Update LINKEDIT-related load commands
    offset = 32
    for _ in range(ncmds + 1):
        cmd = struct.unpack_from('<I', data, offset)[0]
        cmdsize = struct.unpack_from('<I', data, offset+4)[0]
        if cmd == 0x22:  # LC_SYMTAB
            for field in [8, 16]:
                v = struct.unpack_from('<I', data, offset+field)[0]
                if v >= lc_end:
                    struct.pack_into('<I', data, offset+field, v + cmd_size)
        elif cmd in (0x2A, 0x2B, 0x2C):
            for field in [8, 12, 16, 20, 24, 28]:
                v = struct.unpack_from('<I', data, offset+field)[0]
                if v >= lc_end:
                    struct.pack_into('<I', data, offset+field, v + cmd_size)
        elif cmd == 0x33:  # LC_DYSYMTAB
            for field in [8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60, 64, 68]:
                v = struct.unpack_from('<I', data, offset+field)[0]
                if v >= lc_end:
                    struct.pack_into('<I', data, offset+field, v + cmd_size)
        elif cmd == 0x32:  # LC_FUNCTION_STARTS
            v = struct.unpack_from('<I', data, offset+8)[0]
            if v >= lc_end:
                struct.pack_into('<I', data, offset+8, v + cmd_size)
        elif cmd == 0x38:  # LC_DATA_IN_CODE
            v = struct.unpack_from('<I', data, offset+8)[0]
            if v >= lc_end:
                struct.pack_into('<I', data, offset+8, v + cmd_size)
        offset += cmdsize

    with open(binary_path, 'wb') as f:
        f.write(data)
    print('LC_LOAD_DYLIB injected!')

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print(f'Usage: {sys.argv[0]} <binary> <dylib_name>')
        sys.exit(1)
    inject_dylib(sys.argv[1], sys.argv[2])
