"""Writes the test fixtures of lunaway-media.

Run from anywhere:  python3 backend/crates/lunaway-media/tests/fixtures/make_fixtures.py
(needs Pillow)
Then add the XMP packet and the comment to the GPS JPEG with exiftool (see
the end of this file, printed as a reminder). Every image is synthetic: no
real photo, no real person.
"""

import io
import os
import struct
import zlib

from PIL import Image, ImageDraw

OUT = os.path.dirname(os.path.abspath(__file__))


def scene(width, height, seed_color=(40, 110, 160)):
    """A landscape-looking picture: sky gradient, ground, a few shapes, and
    a red block in the stored top-left corner so a test can tell how the
    image was turned."""
    img = Image.new("RGB", (width, height))
    px = img.load()
    for y in range(height):
        t = y / max(1, height - 1)
        for x in range(width):
            s = x / max(1, width - 1)
            if t < 0.6:
                px[x, y] = (int(seed_color[0] + 80 * t), int(seed_color[1] + 60 * t), int(seed_color[2] + 50 * s))
            else:
                px[x, y] = (int(60 + 40 * s), int(120 - 30 * t), int(40 + 20 * s))
    d = ImageDraw.Draw(img)
    d.ellipse((width * 0.7, height * 0.1, width * 0.82, height * 0.26), fill=(250, 230, 120))
    d.rectangle((width * 0.3, height * 0.45, width * 0.5, height * 0.62), fill=(230, 230, 225))
    d.polygon([(width * 0.28, height * 0.45), (width * 0.4, height * 0.33), (width * 0.52, height * 0.45)], fill=(150, 50, 40))
    block = max(8, min(width, height) // 8)
    d.rectangle((0, 0, block, block), fill=(255, 0, 0))
    return img


def gps_jpeg():
    img = scene(640, 480)
    exif = img.getexif()
    exif[0x0112] = 6  # Orientation: rotate 90 degrees clockwise to display.
    exif[0x010F] = "LunawayTestCam"  # Make
    exif[0x0110] = "Fixture 1"  # Model
    # The GPS block is written by exiftool afterwards (see the end of the
    # file): Pillow drops a GPS IFD created from scratch.
    path = os.path.join(OUT, "gps_orientation6.jpg")
    img.save(path, "JPEG", quality=85, exif=exif.tobytes())
    return path


def alpha_png():
    img = Image.new("RGBA", (300, 200), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rectangle((0, 0, 149, 199), fill=(20, 120, 60, 255))
    d.rectangle((150, 0, 299, 199), fill=(20, 120, 60, 0))
    img.save(os.path.join(OUT, "alpha.png"), "PNG")


def webp():
    img = scene(400, 300, (90, 60, 140))
    img.save(os.path.join(OUT, "photo.webp"), "WEBP", quality=80)


def large_jpeg():
    # A phone-sized 12 MP picture, drawn small and scaled up so it stays a
    # smooth, compressible image under 200 KB.
    small = scene(504, 378)
    big = small.resize((4032, 3024), Image.BILINEAR)
    big.save(os.path.join(OUT, "large_12mp.jpg"), "JPEG", quality=20)


def png_chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)


def png_bomb():
    """A PNG declaring 100000 x 100000 grey pixels (10 GB once decoded),
    with a few hundred bytes of compressed zeros."""
    width = height = 100_000
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)
    row = b"\x00" + b"\x00" * width
    body = zlib.compress(row * 4, 9)
    data = b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", ihdr) + png_chunk(b"IDAT", body) + png_chunk(b"IEND", b"")
    with open(os.path.join(OUT, "bomb_100000.png"), "wb") as f:
        f.write(data)


def jpeg_bomb():
    """A small JPEG whose frame header claims 60000 x 60000 pixels."""
    buf = io.BytesIO()
    Image.new("RGB", (16, 16), (128, 128, 128)).save(buf, "JPEG", quality=50)
    data = bytearray(buf.getvalue())
    i = 2
    while i < len(data):
        marker = data[i + 1]
        length = struct.unpack(">H", data[i + 2 : i + 4])[0]
        if marker in (0xC0, 0xC1, 0xC2):
            struct.pack_into(">HH", data, i + 5, 60000, 60000)
            break
        i += 2 + length
    with open(os.path.join(OUT, "bomb_60000.jpg"), "wb") as f:
        f.write(bytes(data))


def gif():
    scene(64, 48).convert("P").save(os.path.join(OUT, "animation.gif"), "GIF")


def heic_like():
    """The first box of an HEIC file (`ftyp`, brand `heic`): what an iPhone
    sends when the app forgets to convert."""
    ftyp = struct.pack(">I", 24) + b"ftyp" + b"heic" + struct.pack(">I", 0) + b"mif1" + b"heic"
    with open(os.path.join(OUT, "photo.heic"), "wb") as f:
        f.write(ftyp + b"\x00" * 40)


def not_an_image():
    with open(os.path.join(OUT, "not_an_image.svg"), "w") as f:
        f.write('<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10"/></svg>\n')


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    gps_jpeg()
    alpha_png()
    webp()
    large_jpeg()
    png_bomb()
    jpeg_bomb()
    gif()
    heic_like()
    not_an_image()
    print("written to", OUT)
    print("now: exiftool -overwrite_original -XMP-dc:Creator=LunawayFixture "
          "-Comment=LunawayFixtureComment -GPSLatitude=45.899247 -GPSLatitudeRef=N "
          "-GPSLongitude=6.129383 -GPSLongitudeRef=E " + os.path.join(OUT, "gps_orientation6.jpg"))
