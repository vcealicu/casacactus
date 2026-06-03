#!/usr/bin/env bash
#
# rename-images.sh — Casa Cactus image intake
#
# Renames raw photo uploads to the brand naming convention
# (zone-subject-descriptors[-view]), converts them to .webp, drops them into
# the site's images directory, and optionally rewrites index.html to use the
# new filenames.
#
#   Usage:
#     ./rename-images.sh                 # convert + copy + rewrite HTML
#     ./rename-images.sh --dry-run       # show what would happen, touch nothing
#     ./rename-images.sh --no-html       # convert + copy only, leave index.html alone
#     ./rename-images.sh --quality 90    # override webp quality (default 82)
#
#   Workflow for a new batch:
#     1. Drop the raw uploads (any filename) into $SRC_DIR.
#     2. Add one line per file to the RENAME block:  source.jpg => semantic-name
#        (no extension on the target — the script writes .webp)
#     3. If a new photo should replace one already on the page, add a line to
#        the HTML_SWAP block:  old/path.webp => new/path.webp
#     4. Run it. Re-running is safe: conversions overwrite, HTML swaps are
#        literal and no-op once applied.
#
# Requires: bash 4+, and cwebp (libwebp) for conversion. Falls back to a plain
# copy (keeping the original extension) if cwebp is not installed, with a warning.

set -euo pipefail

# ── CONFIG ────────────────────────────────────────────────────────────────
SRC_DIR="${SRC_DIR:-./incoming}"          # where raw uploads land
IMG_DIR="${IMG_DIR:-./images}"            # site images directory (flat)
HTML_FILE="${HTML_FILE:-./index.html}"    # page to rewrite
QUALITY=82                                # webp quality
DRY_RUN=false
DO_HTML=true

# ── RENAME MAP ──  source filename (in $SRC_DIR)  =>  target name (no extension)
# Edit this for each batch. Lines starting with # are ignored.
read -r -d '' RENAME <<'MAP' || true
250A0305.jpg => property-entrance-casa-cactus-sign-stone-wall-lamp-cacti-dusk
250A0303-2.jpg => property-entrance-casa-cactus-sign-lamp-cacti-pots-dusk-vertical
250A0302.jpg => property-entrance-casa-cactus-sign-palms-dusk
250A0301-2.jpg => pool-palapa-bar-string-lights-green-light-dusk-vertical
250A0299.jpg => pool-palapa-bar-kitchen-string-lights-dusk-vertical
250A0297-2.jpg => palapa-dining-wicker-pendants-stone-wall-fire-pit
250A0291.jpg => palapa-bar-counter-wicker-pendants-outdoor-sink
250A0272.jpg => garden-sunset-through-trees-golden
250A0270-2.jpg => apartments-exterior-stone-staircase-cactus-row-palms-dusk
250A0209-3.jpg => bathroom-concrete-sink-oval-mirror-room-reflection
250A0207.jpg => pool-view-from-terrace-hammock-railing-palapa
250A0198-2.jpg => apartment-balcony-corridor-wicker-pendants-potted-palm-golden
250A0193-3.jpg => garden-cactus-top-down-gravel-detail
250A0189-2.jpg => apartments-stone-staircase-cactus-row-flagstone
250A0136-3.jpg => property-entrance-casa-cactus-sign-sunflare-vertical
250A0134-3_-_Copy.jpg => bungalow-terrace-hammock-single-chair-side-table-palapa
250A0125-3.jpg => bedroom-stone-wall-cane-headboard-wicker-pendant-yellow-pillows-vertical
250A0124-2.jpg => bedroom-king-cane-headboard-stone-wall-wicker-pendants
MAP

# ── HTML SWAP MAP ──  old src in index.html  =>  new src
# This batch's placements are ALREADY wired into index.html by hand (surgical,
# single-occurrence), so nothing is active here. Left as a template.
#
# IMPORTANT: this does a GLOBAL literal replace — every occurrence of the old
# string changes. Use it to retire an image everywhere in favour of a new one,
# NOT for per-placement swaps (do those by hand). Format, one per line:
#   /images/old-name.webp => /images/new-name.webp
read -r -d '' HTML_SWAP <<'SWAP' || true
SWAP

# ── ARGS ──────────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --no-html) DO_HTML=false; shift ;;
    --quality) QUALITY="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

run() { if $DRY_RUN; then echo "  [dry-run] $*"; else eval "$*"; fi; }

# ── CONVERT + RENAME ────────────────────────────────────────────────────────
have_cwebp=true
command -v cwebp >/dev/null 2>&1 || have_cwebp=false
$have_cwebp || echo "WARN: cwebp not found — copying originals (.jpg) instead of .webp the page expects. Install: sudo apt install webp" >&2

$DRY_RUN || mkdir -p "$IMG_DIR"
converted=0 missing=0

while IFS= read -r line; do
  [[ -z "$line" || "$line" == \#* ]] && continue
  src="${line%%=>*}"; src="${src#"${src%%[![:space:]]*}"}"; src="${src%"${src##*[![:space:]]}"}"
  name="${line##*=>}"; name="${name#"${name%%[![:space:]]*}"}"; name="${name%"${name##*[![:space:]]}"}"
  in="$SRC_DIR/$src"

  if [[ ! -f "$in" ]]; then
    echo "MISS  $src  (not in $SRC_DIR — skipping)"; missing=$((missing+1)); continue
  fi

  if $have_cwebp; then
    out="$IMG_DIR/$name.webp"
    echo "WEBP  $src  ->  $name.webp"
    run "cwebp -quiet -q $QUALITY -m 6 \"$in\" -o \"$out\""
  else
    ext="${src##*.}"
    out="$IMG_DIR/$name.$ext"
    echo "COPY  $src  ->  $name.$ext"
    run "cp \"$in\" \"$out\""
  fi
  converted=$((converted+1))
done <<< "$RENAME"

# ── REWRITE HTML ────────────────────────────────────────────────────────────
swaps=0
if $DO_HTML && [[ -n "${HTML_SWAP// }" ]]; then
  if [[ ! -f "$HTML_FILE" ]]; then
    echo "WARN: $HTML_FILE not found — skipping HTML rewrite" >&2
  else
    content="$(<"$HTML_FILE")"
    while IFS= read -r line; do
      [[ -z "$line" || "$line" == \#* ]] && continue
      old="${line%%=>*}"; old="${old#"${old%%[![:space:]]*}"}"; old="${old%"${old##*[![:space:]]}"}"
      new="${line##*=>}"; new="${new#"${new%%[![:space:]]*}"}"; new="${new%"${new##*[![:space:]]}"}"
      if [[ "$content" == *"$old"* ]]; then
        echo "HTML  $old  ->  $new"
        content="${content//"$old"/"$new"}"   # pure-bash literal replace
        swaps=$((swaps+1))
      fi
    done <<< "$HTML_SWAP"

    if (( swaps > 0 )) && ! $DRY_RUN; then
      cp "$HTML_FILE" "$HTML_FILE.bak.$(date +%Y%m%d-%H%M%S)"
      printf '%s\n' "$content" > "$HTML_FILE"
    fi
  fi
fi

# ── SUMMARY ─────────────────────────────────────────────────────────────────
echo
echo "Done. $converted image(s) processed, $missing missing, $swaps HTML swap(s)."
$DRY_RUN && echo "(dry run — nothing was written)"