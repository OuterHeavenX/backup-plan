#!/usr/bin/env python3
"""Small toolbox for the Godot 4.7 web export in this repo.

  pck_tools.py list <index.pck>
  pck_tools.py extract <index.pck> <out_dir>
  pck_tools.py make-test-build <repo_dir> <out_dir> <main_scene>

`make-test-build` produces a runnable copy of the web export whose project
settings point at a different main scene (e.g. res://tests/test_runner.tscn)
so the headless test scenes can be run in a browser. Everything else in the
pck is left untouched.
"""
import hashlib
import os
import shutil
import struct
import sys


# ---------------------------------------------------------------- pck
def read_pck(path):
    d = open(path, "rb").read()
    assert d[:4] == b"GDPC", "not a Godot pck"
    fmt = struct.unpack_from("<I", d, 4)[0]
    assert fmt == 4, "unsupported pck format %d" % fmt
    file_base = struct.unpack_from("<Q", d, 24)[0]
    dir_off = struct.unpack_from("<Q", d, 32)[0]
    header = d[:file_base]
    p = dir_off
    n = struct.unpack_from("<I", d, p)[0]
    p += 4
    entries = []
    for _ in range(n):
        L = struct.unpack_from("<I", d, p)[0]
        name = d[p + 4:p + 4 + L].rstrip(b"\0").decode()
        p += 4 + L
        off, size = struct.unpack_from("<QQ", d, p)
        p += 16 + 16
        flags = struct.unpack_from("<I", d, p)[0]
        p += 4
        entries.append([name, d[off + file_base:off + file_base + size], flags])
    return header, file_base, entries


def write_pck(path, header, file_base, entries):
    header = bytearray(header)
    body = bytearray()
    dir_entries = []
    for name, data, flags in sorted(entries, key=lambda e: e[0]):
        abs_off = file_base + len(body)
        pad = (-abs_off) % 32
        body += b"\0" * pad
        abs_off += pad
        dir_entries.append((name, abs_off - file_base, len(data), hashlib.md5(data).digest(), flags))
        body += data
    dir_off = file_base + len(body)
    dir_off += (-dir_off) % 32
    body += b"\0" * (dir_off - file_base - len(body))
    dirb = bytearray(struct.pack("<I", len(dir_entries)))
    for name, off, size, md5, flags in dir_entries:
        nb = name.encode()
        pad = (-len(nb)) % 4
        dirb += struct.pack("<I", len(nb) + pad) + nb + b"\0" * pad
        dirb += struct.pack("<QQ", off, size) + md5 + struct.pack("<I", flags)
    struct.pack_into("<Q", header, 32, dir_off)
    with open(path, "wb") as f:
        f.write(bytes(header) + bytes(body) + bytes(dirb))


# ---------------------------------------------------------------- project.binary
def patch_ecfg_string(data, key, value):
    assert data[:4] == b"ECFG"
    p = 4
    n = struct.unpack_from("<I", data, p)[0]
    p += 4
    entries = []
    for _ in range(n):
        kl = struct.unpack_from("<I", data, p)[0]
        p += 4
        k = data[p:p + kl]
        p += kl
        vl = struct.unpack_from("<I", data, p)[0]
        p += 4
        v = data[p:p + vl]
        p += vl
        entries.append([k, v])
    sb = value.encode()
    pad = (-len(sb)) % 4
    newv = struct.pack("<II", 4, len(sb)) + sb + b"\0" * pad
    hit = False
    for e in entries:
        if e[0] == key.encode():
            e[1] = newv
            hit = True
    assert hit, "key not found: " + key
    out = bytearray(b"ECFG" + struct.pack("<I", len(entries)))
    for k, v in entries:
        out += struct.pack("<I", len(k)) + k + struct.pack("<I", len(v)) + v
    return bytes(out)


# ---------------------------------------------------------------- commands
WEB_FILES = ["index.js", "index.wasm", "index.png", "index.icon.png", "index.apple-touch-icon.png",
             "index.audio.worklet.js", "index.audio.position.worklet.js"]


def make_test_build(repo, out, main_scene):
    os.makedirs(out, exist_ok=True)
    header, file_base, entries = read_pck(os.path.join(repo, "index.pck"))
    for e in entries:
        if e[0] == "project.binary":
            e[1] = patch_ecfg_string(e[1], "application/run/main_scene", main_scene)
    pck_path = os.path.join(out, "index.pck")
    write_pck(pck_path, header, file_base, entries)
    for f in WEB_FILES:
        src = os.path.join(repo, f)
        dst = os.path.join(out, f)
        if os.path.lexists(dst):
            os.remove(dst)
        os.symlink(os.path.abspath(src), dst)
    html = open(os.path.join(repo, "index.html")).read()
    size = os.path.getsize(pck_path)
    import re
    html = re.sub(r'"index.pck":\d+', '"index.pck":%d' % size, html)
    open(os.path.join(out, "index.html"), "w").write(html)
    print("test build written to %s (main scene %s)" % (out, main_scene))


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    cmd = argv[1]
    if cmd == "list":
        _, _, entries = read_pck(argv[2])
        for name, data, flags in entries:
            print("%8d  %s" % (len(data), name))
    elif cmd == "extract":
        _, _, entries = read_pck(argv[2])
        for name, data, _ in entries:
            path = os.path.join(argv[3], name)
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "wb").write(data)
        print("extracted %d files" % len(entries))
    elif cmd == "make-test-build":
        make_test_build(argv[2], argv[3], argv[4])
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
