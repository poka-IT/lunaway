#!/bin/sh
# Rebuilds the app's typeface from its pinned upstream file:
#
#   app/tool/fonts/build.sh
#
# assets/fonts/figtree-lunaway/: Figtree 2.002 by Erik Kennedy, the variable
# font on the weight axis (300 to 900) as Google Fonts builds it
# (google/fonts, commit a60a77e1, from erikdkennedy/figtree commit 032dfa7f),
# with the tailed l by default and U+2009 and U+202F mapped
# (figtree_lunaway.py), and its licence.
#
# Downloads and a Python venv with the pinned fontTools go to data/tmp/fonts/
# (gitignored). Every download is checked against its SHA-256, fontTools too
# (requirements.txt), and so is every output: two runs give byte-identical
# files.
set -eu
cd "$(dirname "$0")/../.."
work="$(cd .. && pwd)/data/tmp/fonts"
mkdir -p "$work/src"
if [ ! -x "$work/venv/bin/python" ]; then
  python3 -m venv "$work/venv"
  "$work/venv/bin/pip" install -q --require-hashes --only-binary=:all: -r tool/fonts/requirements.txt
fi
ua="lunaway-fonts (+https://lunaway.net)"
figtree=https://raw.githubusercontent.com/google/fonts/a60a77e14f28abd4ef243a1b5dfc48df0cec5205/ofl/figtree

fetch() {
  # $1 file name in src/, $2 URL, $3 SHA-256
  if [ ! -s "$work/src/$1" ]; then
    curl -fsSL -A "$ua" -o "$work/src/$1" "$2"
  fi
  echo "$3  $work/src/$1" | shasum -a 256 -c -
}

fetch Figtree-VF.ttf "$figtree/Figtree%5Bwght%5D.ttf" 26ad3db9b31ff7dde67a91ff515d022d2f495cd506590699cf264f0bfe6fb714
fetch OFL-Figtree.txt "$figtree/OFL.txt" 140d37233e7f3ce7313798befa9600893bcceaf41a55fa0fa5ad52f7f657a268

"$work/venv/bin/python" tool/fonts/figtree_lunaway.py "$work/src/Figtree-VF.ttf" assets/fonts/figtree-lunaway
cp "$work/src/OFL-Figtree.txt" assets/fonts/figtree-lunaway/OFL.txt
shasum -a 256 -c tool/fonts/fonts.sha256
