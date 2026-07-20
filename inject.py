#!/usr/bin/env python3
"""
Mach-O dylib injector for thin arm64 binaries.
Adds LC_LOAD_DYLIB command by finding/creating space in the load commands area.
Works on Linux. No macOS required.
"""
import struct, os, sys, shutil, copy

def align(x, a):
    return (x + a - 1) & ~(a - 1)

def read_cstring(data, offset, maxlen=256):
    end = offset
    while end < len(data) and data[end] != 0 and (end - offset) < maxlen:
        end += 1
    return data[offset:end].decode('utf-8', errors='replace')

LC_SEGMENT_64 = 0x19
LC_LOAD_DYLIB = 0x0C
LC_ID_DYLIB = 0x1C
LC_LOAD_WEAK_DYLIB = 0x1E
LC_LAZY_LOAD_DYLIB = 0x2B
LC_REEXPORT_DYLIB = 0x2D
LC_CODE_SIGNATURE = 0x1D
LC_SYMTAB = 0x02
LC_DYSYMTAB = 0x0B
LC_UUID = 0x1B

def inject_dylib(binary_path, dylib_load_path):
    """
    Inject LC_LOAD_DYLIB into a thin arm64 Mach-O binary.
    Finds free space among existing load commands or appends data.
    """
    with open(binary_path, 'rb') as f:
        data = bytearray(f.read())
    
    # Parse header
    magic = struct.unpack_from('<I', data, 0)[0]
    if magic not in (0xFEEDFACF, 0xFEEDFACE):
        print(f"Error: Invalid Mach-O magic: {hex(magic)}")
        return False
    
    is_64 = magic == 0xFEEDFACF
    hdr_size = 32 if is_64 else 28
    
    cputype = struct.unpack_from('<I', data, 4)[0]
    filetype = struct.unpack_from('<I', data, 12)[0]
    ncmds = struct.unpack_from('<I', data, 16)[0]
    sizeofcmds = struct.unpack_from('<I', data, 20)[0]
    
    print(f"64-bit: {is_64}, cputype={hex(cputype)}, filetype={hex(filetype)}")
    print(f"ncmds: {ncmds}, sizeofcmds: {sizeofcmds}")
    
    # Parse all load commands
    offset = hdr_size
    load_cmd_entries = []
    max_cmd_end = hdr_size
    code_signature_off = None
    code_signature_size = None
    
    for i in range(ncmds):
        cmd = struct.unpack_from('<I', data, offset)[0]
        cmdsize = struct.unpack_from('<I', data, offset + 4)[0]
        
        entry = {'cmd': cmd, 'cmdsize': cmdsize, 'offset': offset}
        
        if cmd == LC_SEGMENT_64:
            segname = data[offset+8:offset+24].rstrip(b'\x00').decode('utf-8', errors='replace')
            entry['segname'] = segname
            
            nsects = struct.unpack_from('<I', data, offset+72)[0]
            seg_cmdsize = cmdsize
            entry['nsects'] = nsects
            entry['fileoff'] = struct.unpack_from('<Q', data, offset+40)[0]
            entry['filesize'] = struct.unpack_from('<Q', data, offset+48)[0]
            entry['vmaddr'] = struct.unpack_from('<Q', data, offset+24)[0]
            entry['vmsize'] = struct.unpack_from('<Q', data, offset+32)[0]
        
        elif cmd == LC_CODE_SIGNATURE:
            code_signature_off = struct.unpack_from('<I', data, offset+8)[0]
            code_signature_size = struct.unpack_from('<I', data, offset+12)[0]
            entry['cs_off'] = code_signature_off
            entry['cs_size'] = code_signature_size
        
        elif cmd == LC_LOAD_DYLIB:
            name_off = offset + struct.unpack_from('<I', data, offset+8)[0]
            dylib_name = read_cstring(data, name_off)
            entry['dylib_name'] = dylib_name
        
        load_cmd_entries.append(entry)
        cmd_end = offset + cmdsize
        if cmd_end > max_cmd_end:
            max_cmd_end = cmd_end
        
        offset += cmdsize
    
    # Find the first non-PAGEZERO segment data
    first_data_seg = None
    for entry in load_cmd_entries:
        if entry.get('cmd') == LC_SEGMENT_64 and entry.get('fileoff', 0) > 0 and entry.get('filesize', 0) > 0:
            first_data_seg = entry
            break
    
    gap_start = max_cmd_end
    gap_end = first_data_seg['fileoff'] if first_data_seg else max_cmd_end
    gap_size = gap_end - gap_start
    
    print(f"Load commands end at: {max_cmd_end}")
    print(f"First data segment ({first_data_seg['segname']}) at offset: {first_data_seg['fileoff']}")
    print(f"Gap between load cmds and data: {gap_size} bytes")
    
    if code_signature_off:
        print(f"Code signature at: {code_signature_off}, size: {code_signature_size}")
    
    # Build the new dylib load command
    path_bytes = dylib_load_path.encode('utf-8') + b'\x00'
    
    # LC_LOAD_DYLIB: cmd(4) + cmdsize(4) + dylib(4+4+4+4+path)
    # dylib structure: name_off(4) + timestamp(4) + current_version(4) + compat_version(4) + path
    cmd_content_size = 24 + len(path_bytes)
    cmd_aligned_size = align(cmd_content_size, 8)
    
    new_cmd = bytearray(cmd_aligned_size)
    struct.pack_into('<I', new_cmd, 0, LC_LOAD_DYLIB)
    struct.pack_into('<I', new_cmd, 4, cmd_aligned_size)
    struct.pack_into('<I', new_cmd, 8, 24)  # offset to path
    struct.pack_into('<I', new_cmd, 12, 2)  # timestamp
    struct.pack_into('<I', new_cmd, 16, 0x10000)  # current version
    struct.pack_into('<I', new_cmd, 20, 0x10000)  # compat version
    new_cmd[24:24+len(path_bytes)] = path_bytes
    
    print(f"New LC_LOAD_DYLIB: cmd_size={cmd_aligned_size}, path={dylib_load_path}")
    
    if gap_size >= cmd_aligned_size:
        # There's space in the gap - just insert
        print(f"Found enough space in gap ({gap_size} >= {cmd_aligned_size})")
        insert_pos = gap_start
        replacement_data = bytearray(data)
        
        # Write new command
        replacement_data[insert_pos:insert_pos+cmd_aligned_size] = new_cmd
        
        # Zero out remaining gap (or leave as is)
        fill_start = insert_pos + cmd_aligned_size
        if fill_start < gap_end:
            for i in range(fill_start, gap_end):
                replacement_data[i] = 0
        
        # Update header
        struct.pack_into('<I', replacement_data, 16, ncmds + 1)  # ncmds++
        struct.pack_into('<I', replacement_data, 20, max_cmd_end + cmd_aligned_size)  # sizeofcmds
        
    else:
        # Not enough space - we need to replace or shift
        print(f"Not enough space in gap ({gap_size} < {cmd_aligned_size})")
        print(f"Need {cmd_aligned_size - gap_size} more bytes")
        
        # Strategy: look for existing dylib load commands we can replace
        # Find dylib commands with long paths that we can reuse
        replace_candidates = []
        for entry in load_cmd_entries:
            if entry.get('cmd') == LC_LOAD_DYLIB and 'dylib_name' in entry:
                dylib_entry_size = entry['cmdsize']
                # If this dylib command is as large as or larger than our new one
                if dylib_entry_size >= cmd_aligned_size:
                    replace_candidates.append((entry['offset'], dylib_entry_size, entry['dylib_name']))
        
        # Sort by size (largest first, we want best fit)
        replace_candidates.sort(key=lambda x: -x[1])
        
        if replace_candidates:
            best_offset, best_size, old_name = replace_candidates[0]
            print(f"Replacing existing dylib load command at {best_offset} (size={best_size}): {old_name}")
            
            replacement_data = bytearray(data)
            # Write new command (pad with zeros if needed)
            replacement_data[best_offset:best_offset+cmd_aligned_size] = new_cmd
            if cmd_aligned_size < best_size:
                for i in range(best_offset + cmd_aligned_size, best_offset + best_size):
                    replacement_data[i] = 0
            
            # ncmds stays the same, sizeofcmds might stay the same too
            # No header changes needed
        else:
            print("No viable replacement found - attempting to expand and shift...")
            # This is the complex case. We need to:
            # 1. Insert the new command after the last load command
            # 2. Shift all subsequent data
            # 3. Update all file offsets
            # 
            # Instead, let's use a different approach:
            # We can add space by linking as LC_LOAD_WEAK_DYLIB
            # or by removing the code signature (which we'd need to rebuild)
            
            print("ERROR: Cannot inject without proper Mach-O tool. Use macOS.")
            return False
    
    # Save modified binary
    backup_path = binary_path + '.bak'
    if not os.path.exists(backup_path):
        shutil.copy2(binary_path, backup_path)
        print(f"Backup: {backup_path}")
    
    with open(binary_path, 'wb') as f:
        f.write(replacement_data)
    
    print(f"✓ Modified: {binary_path}")
    return True

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print(f"Usage: {sys.argv[0]} <macho_binary> <dylib_load_path>")
        print(f"Example: {sys.argv[0]} app \"@executable_path/FridaGadget.dylib\"")
        sys.exit(1)
    
    binary = sys.argv[1]
    dylib_path = sys.argv[2]
    
    if not os.path.exists(binary):
        print(f"Binary not found: {binary}")
        sys.exit(1)
    
    success = inject_dylib(binary, dylib_path)
    sys.exit(0 if success else 1)
