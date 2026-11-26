#!/usr/bin/env python3
"""csARM round 115: extract loose shader VCS files from VPK archives.

Diagnosis chain (#269/#270 + console): the engine reaches Clear+Present
every frame but issues ZERO draws; the console says
"!!!!!Using invalid shader combo!!!!! Shader: sky_vs20 static: 0 dynamic: 0"
and "CGLMShaderPair::SetProgramPair ... lightmappedgeneric_vs30 and pixel
shader null!".  Engine-internal ps30 VCS (engine_post etc.) DO load, so
the shader FILE layer works - the GAME shader VCS (lightmappedgeneric,
sky, vertexlitgeneric, ...) are only reachable inside pak01_dir.vpk, and
whatever mount/subset the engine sees misses them.

This tool parses the VPK v1/v2 index (Dragon UnPACKer layout: signature
0x55aa1234, tree of extension -> directory -> filename, entries point
into pak01_%03d.vpk chunks) and writes every entry under shaders/<dir>/
as a LOOSE file next to the archive (shaders/ dir = same search path the
engine already reads loose dev shaders from).  Never fatal: any parse
problem prints a marker and exits 0 - CI must keep booting the emulator.

usage: python3 extract_vpk_shaders.py <dir_vpk_path> [<dir_vpk_path> ...]
  out: <vpk_dir>/shaders/<vsh|psh|fxc|...>/<name>.vcs
"""
import os, struct, sys

VPK_SIG = 0x55aa1234
DIR_IDX = 0x7fff

def read_cstr(buf, pos):
    end = buf.index(b'\x00', pos)
    return buf[pos:end].decode('utf-8', 'replace'), end + 1

def extract(archive_path):
    base = os.path.dirname(os.path.abspath(archive_path))
    name = os.path.basename(archive_path)
    data = open(archive_path, 'rb').read()
    if len(data) < 12 or struct.unpack_from('<I', data, 0)[0] != VPK_SIG:
        print(f'VPK-EXTRACT {name}: bad signature - skip'); return 0
    version = struct.unpack_from('<I', data, 4)[0]
    tree_size = struct.unpack_from('<I', data, 8)[0]
    pos = 28 if version >= 2 else 12
    tree_end = pos + tree_size
    n = 0
    while pos < tree_end and data[pos] != 0:
        ext, pos = read_cstr(data, pos)
        while pos < tree_end and data[pos] != 0:
            dpath, pos = read_cstr(data, pos)
            while pos < tree_end and data[pos] != 0:
                fname, pos = read_cstr(data, pos)
                crc, preload, aidx, off, ln = struct.unpack_from(
                    '<IHHII', data, pos); pos += 16
                # adaptive entry layout (round 116): #272 proved the real
                # pak01_dir.vpk desyncs with a forced per-entry 0xffff
                # terminator ("term 0x6f63 != 0xffff at ..." drift).  Peek
                # the next u16: 0xffff -> v1 terminator present, consume it
                # (then the v2 u32 archiveMD5Index); otherwise treat those
                # bytes as the v2 u32 index directly (CS:GO writer omits
                # the terminator).  A u16 peek is safe: md5 indexes are
                # small section ordinals, never 0xffff in practice.
                term = struct.unpack_from('<H', data, pos)[0]
                if term == 0xffff:
                    pos += 2
                    if version >= 2:
                        pos += 4      # archiveMD5Index
                else:
                    pos += 4          # v2: archiveMD5Index, no terminator
                pre = data[pos:pos + preload]; pos += preload
                if ext.lower() != 'vcs' or not dpath.lower().startswith('shaders'):
                    continue
                if aidx == DIR_IDX:
                    blob = pre
                else:
                    chunk = os.path.join(base, name.replace('_dir', f'_{aidx:03d}'))
                    try:
                        with open(chunk, 'rb') as f:
                            f.seek(off); blob = f.read(ln)
                    except OSError as e:
                        print(f'VPK-EXTRACT {name}: chunk {aidx:03d} miss: {e}')
                        continue
                if len(blob) < ln:
                    print(f'VPK-EXTRACT {name}: short read {fname} ({len(blob)}/{ln})')
                    continue
                rel = f'{dpath.replace(chr(92), "/")}/{fname}.{ext}'
                outp = os.path.join(base, rel)
                os.makedirs(os.path.dirname(outp), exist_ok=True)
                open(outp, 'wb').write(blob)
                n += 1
            pos += 1
        pos += 1
    return n

if __name__ == '__main__':
    total = 0
    for p in sys.argv[1:]:
        if os.path.exists(p):
            k = extract(p)
            print(f'VPK-EXTRACT {os.path.basename(p)}: {k} VCS extracted')
            total += k
        else:
            print(f'VPK-EXTRACT {p}: archive missing - skip')
    print(f'VPK-EXTRACT TOTAL: {total}')
