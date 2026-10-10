#!/bin/sh
# Rebuild every raster of the Lunaway brand from the SVG sources in brand/.
#
#   tool/brand/generate.sh
#
# Needs rsvg-convert (librsvg), magick (ImageMagick 7) and oxipng
# (`cargo install oxipng`). The SVG sources are brand/lunaway-mark.svg (the
# master, edited by hand) and the files tool/brand/build_sources.py derives
# from it; run that script first when the mark or the wordmark changes.
#
# Every PNG is rendered at its final pixel size straight from the vector, never
# downscaled from a larger PNG, so small sizes stay sharp. oxipng then strips
# every metadata chunk, which also makes the output byte-identical from one run
# to the next. Scratch files go to data/tmp/brand/gen/ (gitignored) and are
# overwritten on the next run.
set -eu
LC_ALL=C
export LC_ALL
cd "$(dirname "$0")/../.."

for tool in rsvg-convert magick oxipng; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "generate.sh: $tool is missing (brew install librsvg imagemagick; cargo install oxipng)" >&2
    exit 1
  fi
done

NAVY='#061F43'
CREAM='#FDF1DB'
GEN=data/tmp/brand/gen
mkdir -p "$GEN"

# librsvg only loads images that sit next to the SVG that references them, so
# the compositions below and the sources they use live in the same directory.
cp brand/lunaway-mark.svg "$GEN/mark.svg"
cp brand/lunaway-mark-mono.svg "$GEN/mono.svg"
sed "s/fill=\"$NAVY\"/fill=\"#FFFFFF\"/" brand/lunaway-mark-mono.svg >"$GEN/mono-white.svg"

# Files to optimise at the end: small ones get the slower zopfli pass.
SMALL=""
LARGE=""

# mark_at W H PIN_H HREF: an <image> of the mark, PIN_H units tall, centred in
# a W x H canvas. The mark's view box is 454 x 552; centring its bounding box
# also centres the smallest circle around it, which is what the launcher masks
# and the splash circles crop to.
mark_at() {
  awk -v w="$1" -v h="$2" -v ph="$3" -v href="$4" 'BEGIN {
    pw = ph * 454 / 552
    printf "  <image href=\"%s\" x=\"%.3f\" y=\"%.3f\" width=\"%.3f\" height=\"%.3f\"/>\n", href, (w - pw) / 2, (h - ph) / 2, pw, ph
  }'
}

# png SVG SIZE OUT [small|large]: render a square composition at SIZE pixels.
png() {
  mkdir -p "$(dirname "$3")"
  rsvg-convert -w "$2" -h "$2" "$GEN/$1" -o "$3"
  if [ "${4:-small}" = small ]; then SMALL="$SMALL $3"; else LARGE="$LARGE $3"; fi
}

# png_h SVG HEIGHT OUT: render keeping the aspect ratio, HEIGHT pixels tall.
png_h() {
  mkdir -p "$(dirname "$3")"
  rsvg-convert -h "$2" "$1" -o "$3"
  SMALL="$SMALL $3"
}

# --- Compositions -----------------------------------------------------------

# Cream plate, mark at 60 % of the side: iOS icon, apple-touch-icon, store icon.
cat >"$GEN/plate.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">
  <rect width="1000" height="1000" fill="$CREAM"/>
$(mark_at 1000 1000 600 mark.svg)
</svg>
EOF

# The mark alone on transparency: iOS dark icon (the system draws the dark
# background), web "any" icons, Windows icon, favicon.
for pct in 60 88 96; do
  cat >"$GEN/bare-$pct.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">
$(mark_at 1000 1000 $((pct * 10)) mark.svg)
</svg>
EOF
done

# iOS tinted icon: a grey-scale image on black; the system tints the light parts.
cat >"$GEN/tinted.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">
  <rect width="1000" height="1000" fill="#000000"/>
$(mark_at 1000 1000 600 mono-white.svg)
</svg>
EOF

# Web maskable icon: the mark inside the 80 % safe circle, on cream.
cat >"$GEN/maskable.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">
  <rect width="1000" height="1000" fill="$CREAM"/>
$(mark_at 1000 1000 700 mark.svg)
</svg>
EOF

# Android adaptive icon layers, on the 108 dp canvas: the mark is 58 dp tall,
# inside the 66 dp safe circle every launcher mask keeps. The background layer
# is the cream colour resource.
cat >"$GEN/adaptive-foreground.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108">
$(mark_at 108 108 58 mark.svg)
</svg>
EOF
cat >"$GEN/adaptive-monochrome.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108">
$(mark_at 108 108 58 mono-white.svg)
</svg>
EOF

# Android legacy launcher icons (API 24 and 25), on the 48 dp canvas.
cat >"$GEN/legacy-square.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <rect x="1" y="1" width="46" height="46" rx="9" fill="$CREAM"/>
$(mark_at 48 48 29 mark.svg)
</svg>
EOF
cat >"$GEN/legacy-round.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">
  <circle cx="24" cy="24" r="23" fill="$CREAM"/>
$(mark_at 48 48 29 mark.svg)
</svg>
EOF

# Splash icon: Android 12 scales it to 288 dp (240 dp on an icon background)
# and crops a circle of two thirds of that; the mark is 56 % of the side, so
# it stays inside. The pre-12 splash and the iOS launch image use the same
# proportions; at night they sit on a cream disc of two thirds of the side,
# the size Android draws its icon background.
cat >"$GEN/splash.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">
$(mark_at 1000 1000 560 mark.svg)
</svg>
EOF
cat >"$GEN/splash-night.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">
  <circle cx="500" cy="500" r="333.333" fill="$CREAM"/>
$(mark_at 1000 1000 560 mark.svg)
</svg>
EOF

# macOS icon grid: an 824 px rounded plate centred in 1024, with the soft
# shadow of the system icons; the mark is 60 % of the plate.
cat >"$GEN/macos.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">
  <defs>
    <filter id="shadow" x="-10%" y="-10%" width="120%" height="125%">
      <feGaussianBlur in="SourceAlpha" stdDeviation="10"/>
      <feOffset dy="10"/>
      <feComponentTransfer><feFuncA type="linear" slope="0.3"/></feComponentTransfer>
      <feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge>
    </filter>
  </defs>
  <rect x="100" y="100" width="824" height="824" rx="185" fill="$CREAM" filter="url(#shadow)"/>
$(mark_at 1024 1024 494 mark.svg)
</svg>
EOF

# --- Android -----------------------------------------------------------------

RES=app/android/app/src/main/res
for d in mdpi:1 hdpi:1.5 xhdpi:2 xxhdpi:3 xxxhdpi:4; do
  name=${d%%:*}
  scale=${d#*:}
  legacy=$(awk -v s="$scale" 'BEGIN { printf "%d", 48 * s }')
  layer=$(awk -v s="$scale" 'BEGIN { printf "%d", 108 * s }')
  splash=$(awk -v s="$scale" 'BEGIN { printf "%d", 288 * s }')
  png legacy-square.svg "$legacy" "$RES/mipmap-$name/ic_launcher.png"
  png legacy-round.svg "$legacy" "$RES/mipmap-$name/ic_launcher_round.png"
  png adaptive-foreground.svg "$layer" "$RES/mipmap-$name/ic_launcher_foreground.png"
  png adaptive-monochrome.svg "$layer" "$RES/mipmap-$name/ic_launcher_monochrome.png"
  if [ "$splash" -le 512 ]; then size=small; else size=large; fi
  png splash.svg "$splash" "$RES/drawable-$name/splash_icon.png" "$size"
done

# --- iOS ---------------------------------------------------------------------

IOS=app/ios/Runner/Assets.xcassets
png plate.svg 1024 "$IOS/AppIcon.appiconset/AppIcon-1024.png" large
png bare-60.svg 1024 "$IOS/AppIcon.appiconset/AppIcon-1024-dark.png" large
png tinted.svg 1024 "$IOS/AppIcon.appiconset/AppIcon-1024-tinted.png" large
# Launch image: 240 pt square, light and dark appearances.
png splash.svg 240 "$IOS/LaunchImage.imageset/LaunchImage.png"
png splash.svg 480 "$IOS/LaunchImage.imageset/LaunchImage@2x.png"
png splash.svg 720 "$IOS/LaunchImage.imageset/LaunchImage@3x.png" large
png splash-night.svg 240 "$IOS/LaunchImage.imageset/LaunchImageDark.png"
png splash-night.svg 480 "$IOS/LaunchImage.imageset/LaunchImageDark@2x.png"
png splash-night.svg 720 "$IOS/LaunchImage.imageset/LaunchImageDark@3x.png" large

# --- macOS -------------------------------------------------------------------

for size in 16 32 64 128 256 512 1024; do
  if [ "$size" -le 512 ]; then kind=small; else kind=large; fi
  png macos.svg "$size" "app/macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$size.png" "$kind"
done

# --- Windows -----------------------------------------------------------------

# 32-bit entries; the 256 px one is stored as PNG, as Windows expects.
ICO_PARTS=""
for size in 16 24 32 48 64 128 256; do
  rsvg-convert -w "$size" -h "$size" "$GEN/bare-96.svg" -o "$GEN/ico-$size.png"
  ICO_PARTS="$ICO_PARTS $GEN/ico-$size.png"
done
# shellcheck disable=SC2086
magick $ICO_PARTS -type TrueColorAlpha -define icon:png-compression-size=256 app/windows/runner/resources/app_icon.ico

# --- Web ---------------------------------------------------------------------

WEB=app/web
png bare-96.svg 32 "$WEB/favicon.png"
png bare-88.svg 192 "$WEB/icons/Icon-192.png"
png bare-88.svg 512 "$WEB/icons/Icon-512.png"
png maskable.svg 192 "$WEB/icons/Icon-maskable-192.png"
png maskable.svg 512 "$WEB/icons/Icon-maskable-512.png"
png plate.svg 180 "$WEB/apple-touch-icon.png"
# The tab icon follows the browser theme: navy on light, cream on dark.
sed 's|<title>Lunaway</title>|<title>Lunaway</title>\
  <style>@media (prefers-color-scheme: dark) { .mark { fill: '"$CREAM"'; } }</style>|' \
  brand/lunaway-mark-mono.svg >"$WEB/favicon.svg"
# The loading screen of index.html shows the mark itself.
cp brand/lunaway-mark.svg "$WEB/icons/lunaway-mark.svg"

# --- Store listings (Google Play and F-Droid) ----------------------------------

for locale in en-US fr-FR de-DE es-ES it-IT nl-NL; do
  lang=${locale%%-*}
  dir=fastlane/metadata/android/$locale/images
  png plate.svg 512 "$dir/icon.png"
  # Google Play asks for a 32-bit PNG: keep an (opaque) alpha channel.
  magick "$dir/icon.png" "PNG32:$dir/icon.png"
  rsvg-convert -w 1024 -h 500 "brand/feature-graphic-$lang.svg" -o "$dir/featureGraphic.png"
  LARGE="$LARGE $dir/featureGraphic.png"
done
rsvg-convert -w 1280 -h 640 brand/social-preview.svg -o brand/social-preview.png
LARGE="$LARGE brand/social-preview.png"

# --- In-app assets (Flutter picks 2.0x/ and 3.0x/ by device pixel ratio) -----

ASSETS=app/assets/brand
mkdir -p "$ASSETS"
cp brand/lunaway-mark.svg brand/lunaway-mark-mono.svg brand/lunaway-lockup.svg brand/lunaway-lockup-dark.svg "$ASSETS/"
for ratio in 1 2 3; do
  if [ "$ratio" = 1 ]; then dir=$ASSETS; else dir=$ASSETS/$ratio.0x; fi
  png_h brand/lunaway-mark.svg $((128 * ratio)) "$dir/lunaway-mark.png"
  png_h brand/lunaway-lockup.svg $((64 * ratio)) "$dir/lunaway-lockup.png"
  png_h brand/lunaway-lockup-dark.svg $((64 * ratio)) "$dir/lunaway-lockup-dark.png"
done

# --- Optimise ------------------------------------------------------------------

# The store icons keep their colour type (RGBA, see above). Everything else
# stays as rsvg-convert writes it or loses what it does not use: the opaque
# icons (iOS, apple-touch, feature graphics) are plain RGB, without alpha.
STORE_ICONS=""
for locale in en-US fr-FR de-DE es-ES it-IT nl-NL; do
  STORE_ICONS="$STORE_ICONS fastlane/metadata/android/$locale/images/icon.png"
done
SMALL_REST=""
for f in $SMALL; do
  case " $STORE_ICONS " in
    *" $f "*) ;;
    *) SMALL_REST="$SMALL_REST $f" ;;
  esac
done
# shellcheck disable=SC2086
oxipng -q -o max -z --strip all $SMALL_REST
# shellcheck disable=SC2086
oxipng -q -o max -z --strip all --nc $STORE_ICONS
# shellcheck disable=SC2086
oxipng -q -o max --strip all $LARGE

echo "brand: rasters rebuilt from brand/*.svg"
