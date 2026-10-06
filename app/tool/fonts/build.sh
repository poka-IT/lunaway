#!/bin/sh
# Rebuilds the app's two derived typefaces from pinned upstream files:
#
#   app/tool/fonts/build.sh
#
# - assets/fonts/atkinson-next-lunaway/: Atkinson Hyperlegible Next 2.001
#   (googlefonts/atkinson-hyperlegible-next, commit 5d633f80) with a plain
#   zero and U+202F mapped (atkinson_plain_zero.py);
# - assets/fonts/fraunces/Fraunces-Variable.ttf: Fraunces 1.003
#   (undercasetype/Fraunces, commit 7ccdec31) instanced at SOFT 0, WONK 0 and
#   subset to Latin (fraunces_subset.py).
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
atkinson=https://raw.githubusercontent.com/googlefonts/atkinson-hyperlegible-next/5d633f80fc654ef5fffa7cfc257528685158dcef/fonts/ttf
fraunces=https://raw.githubusercontent.com/undercasetype/Fraunces/7ccdec31c6028118dce3e47fe864e3744460371d/fonts/variable

fetch() {
  # $1 file name in src/, $2 URL, $3 SHA-256
  if [ ! -s "$work/src/$1" ]; then
    curl -fsSL -A "$ua" -o "$work/src/$1" "$2"
  fi
  echo "$3  $work/src/$1" | shasum -a 256 -c -
}

fetch AtkinsonHyperlegibleNext-Regular.ttf "$atkinson/AtkinsonHyperlegibleNext-Regular.ttf" 88ed5c31a71584c7772963b02d04bef1eb7e3d2e9c8b9cb204339b1f82cf432c
fetch AtkinsonHyperlegibleNext-Medium.ttf "$atkinson/AtkinsonHyperlegibleNext-Medium.ttf" dd50b08b3c560846097d23baaaf6a97ffa20dd077115d23c59df68083b9ea05e
fetch AtkinsonHyperlegibleNext-SemiBold.ttf "$atkinson/AtkinsonHyperlegibleNext-SemiBold.ttf" 8e2fff779f35ac25239656bb0f3b2bd35959a2009e3dd21a12141c3b9030362b
fetch AtkinsonHyperlegibleNext-Bold.ttf "$atkinson/AtkinsonHyperlegibleNext-Bold.ttf" 994414047df66bb4998d01c1cb1eeb4a2ddc4622d1aa56bbb8adbeca7645b041
fetch AtkinsonHyperlegibleNext-ExtraBold.ttf "$atkinson/AtkinsonHyperlegibleNext-ExtraBold.ttf" 445281bbc922d68229fe17d6b57f94d9b6ef66cf65017d0b1e14c3cfe5db4794
fetch Fraunces-VF.ttf "$fraunces/Fraunces%5BSOFT,WONK,opsz,wght%5D.ttf" 0776a870a0856b296e11639505ac0cf9be5e7800bb1849dfa21a1bd182455fc0

"$work/venv/bin/python" tool/fonts/atkinson_plain_zero.py "$work/src" assets/fonts/atkinson-next-lunaway
"$work/venv/bin/python" tool/fonts/fraunces_subset.py "$work/src/Fraunces-VF.ttf" assets/fonts/fraunces
shasum -a 256 -c tool/fonts/fonts.sha256
