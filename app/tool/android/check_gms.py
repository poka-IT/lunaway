"""Lists Google Play Services classes compiled into an APK: the F-Droid build
must define none. Classes are read from the dex class definitions, so a mere
reference left in a library's dead code does not count.

    python3 tool/android/check_gms.py <apk>
"""

import struct
import sys
import zipfile


def _uleb(data, pos):
    result = shift = 0
    while True:
        b = data[pos]
        pos += 1
        result |= (b & 0x7F) << shift
        if b < 0x80:
            return result, pos
        shift += 7


def defined_classes(dex):
    string_ids_size, string_ids_off, type_ids_size, type_ids_off = struct.unpack_from("<IIII", dex, 0x38)
    class_defs_size, class_defs_off = struct.unpack_from("<II", dex, 0x60)

    def string(i):
        (off,) = struct.unpack_from("<I", dex, string_ids_off + 4 * i)
        _, pos = _uleb(dex, off)
        end = dex.index(b"\x00", pos)
        return dex[pos:end].decode("utf-8", "replace")

    for i in range(class_defs_size):
        (type_idx,) = struct.unpack_from("<I", dex, class_defs_off + 32 * i)
        (descriptor,) = struct.unpack_from("<I", dex, type_ids_off + 4 * type_idx)
        yield string(descriptor)


def main(apk):
    gms = []
    with zipfile.ZipFile(apk) as z:
        for name in z.namelist():
            if name.endswith(".dex"):
                gms += [c for c in defined_classes(z.read(name)) if c.startswith("Lcom/google/android/gms/")]
    print(f"{len(gms)} Play Services class(es) defined")
    for c in sorted(gms)[:5]:
        print("  ", c)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
