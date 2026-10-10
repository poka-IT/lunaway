# Lunaway brand

The mark is a map pin holding a night landscape: a crescent moon, a
four-point star, a dot and a small diamond over two bands of teal hills, and
a white road running down to the tip of the pin.

## Files

| file | what it is |
|---|---|
| `lunaway-mark.svg` | the master, full colour on transparency, edited by hand |
| `lunaway-mark-mono.svg` | one colour: the pin with the moon, star and road cut out |
| `lunaway-lockup.svg` | mark and wordmark, navy text, for light backgrounds |
| `lunaway-lockup-dark.svg` | the same with cream text, for dark backgrounds |
| `feature-graphic-<lang>.svg` (en, fr, de, es, it, nl) | store feature graphic, 1024 x 500, with the tagline in the language of the listing |
| `social-preview.svg`, `social-preview.png` | repository social preview, 1280 x 640, to upload in the GitHub settings |

Every other file is derived from these; nothing under `app/` or `fastlane/`
that carries the mark is edited by hand.

## Palette

| colour | hex | role |
|---|---|---|
| navy | `#061F43` | night sky, near ground and road dashes; text on light; night splash; theme colour |
| cream | `#FDF1DB` | moon and stars; icon plates and day splash; text on dark |
| light teal | `#409FA7` | far hills |
| dark teal | `#15576D` | mid hills |
| white | `#FDFDFD` | the road |
| night | `#020B1B` | top of the sky gradient in the store art only, never in the mark |

The values were sampled as medians over the inside of each flat area of the
original drawing (anti-aliased edges excluded); the navy of the sky, of the
near ground and of the road dashes is one colour.

## Using the mark

- Clear space: keep at least a quarter of the mark's height free on every
  side, for the mark alone and for the lockup (measured on its mark).
- Minimum size: the full-colour mark 24 px tall on screen (8 mm in print);
  below that, the mono mark, down to 16 px. The lockup 32 px tall.
- Backgrounds: the navy pin needs a lighter ground to show its outline.
  Cream and white are the natural grounds. On navy, place the mark on a cream
  disc whose diameter is 1.2 times the mark's height (the night splash
  screens do this); on near-black (`#0D1117` and darker) the mark can stand
  on its own, as in the dark lockup.
- Do not recolour, outline, rotate or stretch the mark, and do not add
  effects to it. The mono mark takes any single colour.

## Construction

The master was traced from the maintainer's 768 px drawing: colour
boundaries extracted at sub-pixel precision, fitted with cubic Bezier curves,
then cleaned by hand. The pin is exact geometry: a circle of radius 227
centred at (227, 227) and two arcs of radius 640 tangent to it, meeting at the
tip (227, 552). Cleanups of the drawing: the pin is symmetric (the drawn tip
leaned 10 px to the left), the moon's tips, the star and the dashes are
sharp, and the star is symmetric on both axes. Each landscape layer fills down
past the base of the pin and the next one covers it, so shared edges have no
seams; the pin is applied as a mask, which keeps its outline free of the
fringe a clip path leaves where the white road meets the edge.

## Wordmark

"Lunaway" is set in Fraunces 72pt SemiBold, with the L-u pair tightened by
70 font units; the taglines use Fraunces 72pt Regular. The text is converted
to outlines, so no font file ships with the brand.

Fraunces is by Undercase Type (Phaedra Charles and Flavia Zimbardi), from
https://github.com/undercasetype/Fraunces (commit
`7ccdec31c6028118dce3e47fe864e3744460371d`), under the SIL Open Font License
1.1. Glyph outlines in a logo are a document made with the font, which the
licence leaves free; its condition 5 ends: "The requirement for fonts to
remain under this license does not apply to any document created using the
Font Software." No copy of the licence is needed next to these files.

## Regenerating

```bash
python3 tool/brand/build_sources.py   # mono mark, lockups, store art (needs fontTools and hb-shape)
tool/brand/generate.sh                # every raster, from the SVGs (needs rsvg-convert, magick, oxipng)
```

`build_sources.py` downloads the two Fraunces files once, at the pinned
commit, checks their SHA-256 and keeps them in `data/tmp/brand/fonts/`.
`generate.sh` renders each PNG at its final size straight from the vector,
then strips every metadata chunk with oxipng; two runs give byte-identical
files. It writes:

- Android: legacy and round launcher icons, the adaptive icon foreground and
  monochrome layers (the background is the `ic_launcher_background` colour
  resource), and the splash icon, for every density;
- iOS: the 1024 px app icon (opaque) with its dark and tinted variants, and
  the launch image in light and dark;
- macOS: the app icon from 16 to 1024 px on the system icon grid;
- Windows: `app_icon.ico` with 16, 24, 32, 48, 64, 128 and 256 px entries;
- web: favicons (PNG and an SVG that follows the browser theme), the PWA
  icons and their maskable versions, the apple-touch icon, and the mark used
  by the loading screen;
- store listings: the 512 px icon and the feature graphic per locale, under
  `fastlane/metadata/android/<locale>/images/`;
- in-app assets: the SVGs and PNG exports at 1x, 2x and 3x in
  `app/assets/brand/`.

The XML and JSON that reference these files (adaptive icon, splash styles,
asset catalogs, launch storyboard, web manifest and `index.html`) are edited
by hand.
