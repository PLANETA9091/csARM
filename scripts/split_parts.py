#!/usr/bin/env python3
"""Split a download tree into chunk file lists capped at <max> bytes each.

Used by .github/workflows/content.yml: GitHub release assets are capped at
2 GiB per file, so the fetched game content is packed into several zip parts.
This script only produces the chunk lists (zip packing happens in bash so
that relative paths inside the archives stay depot-rooted).

Usage: split_parts.py <root> <max_bytes> <outdir>
Prints CHUNK|<listfile>|<total_bytes>|<nfiles> per chunk and a TOTAL line.
"""
import os
import sys


def main() -> int:
    if len(sys.argv) != 4:
        print(__doc__)
        return 2
    root, maxb, outdir = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    os.makedirs(outdir, exist_ok=True)
    for old in os.listdir(outdir):
        if old.startswith("chunk_") and old.endswith(".lst"):
            os.unlink(os.path.join(outdir, old))

    files = []
    for dp, _dns, fns in os.walk(root):
        for fn in fns:
            p = os.path.join(dp, fn)
            rel = os.path.relpath(p, root).replace(os.sep, "/")
            files.append((rel, os.path.getsize(p)))
    files.sort()

    chunks, cur, cursz = [], [], 0
    for rel, sz in files:
        if sz > maxb:  # oversized single file gets its own chunk anyway
            chunks.append([(rel, sz)])
            continue
        if cur and cursz + sz > maxb:
            chunks.append(cur)
            cur, cursz = [], 0
        cur.append((rel, sz))
        cursz += sz
    if cur:
        chunks.append(cur)

    total = 0
    for i, ch in enumerate(chunks, 1):
        lst = os.path.join(outdir, f"chunk_{i:02d}.lst")
        with open(lst, "w", encoding="utf-8") as f:
            for rel, _sz in ch:
                f.write(rel + "\n")
        sz = sum(s for _, s in ch)
        total += sz
        print(f"CHUNK|{lst}|{sz}|{len(ch)}")
    print(f"TOTAL|{len(chunks)}|{total}|{sum(len(c) for c in chunks)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
