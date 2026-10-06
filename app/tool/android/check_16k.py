"""Checks that every 64-bit native library of an APK is ready for 16 KB pages:
each PT_LOAD segment aligned on at least 16 KB (ELF), as Play requires for
apps targeting Android 15 and later. 16 KB pages exist on 64-bit devices
only, so 32-bit libraries are listed for information. Zip alignment is
checked separately with `zipalign -c -P 16 -v 4 <apk>`.

    python3 tool/android/check_16k.py <apk>
"""

import struct
import sys
import zipfile

PT_LOAD = 1


def load_alignments(data):
    if data[:4] != b"\x7fELF":
        return []
    is64 = data[4] == 2
    little = data[5] == 1
    e = "<" if little else ">"
    if is64:
        phoff, = struct.unpack_from(e + "Q", data, 0x20)
        phentsize, phnum = struct.unpack_from(e + "HH", data, 0x36)
    else:
        phoff, = struct.unpack_from(e + "I", data, 0x1C)
        phentsize, phnum = struct.unpack_from(e + "HH", data, 0x2A)
    out = []
    for i in range(phnum):
        off = phoff + i * phentsize
        p_type, = struct.unpack_from(e + "I", data, off)
        if p_type != PT_LOAD:
            continue
        align = struct.unpack_from(e + "Q", data, off + 48)[0] if is64 else struct.unpack_from(e + "I", data, off + 28)[0]
        out.append(align)
    return out


def main(apk):
    bad = 0
    with zipfile.ZipFile(apk) as z:
        for name in sorted(n for n in z.namelist() if n.startswith("lib/") and n.endswith(".so")):
            aligns = load_alignments(z.read(name))
            low = min(aligns) if aligns else 0
            wide = name.split("/")[1] in ("arm64-v8a", "x86_64")
            ok = low >= 16384 or not wide
            bad += 0 if ok else 1
            label = "ok " if low >= 16384 else ("n/a" if not wide else "BAD")
            print(f"{label} {name}  min PT_LOAD align {low}")
    print("every 64-bit native library is 16 KB aligned" if bad == 0 else f"{bad} 64-bit library(ies) not 16 KB aligned")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
