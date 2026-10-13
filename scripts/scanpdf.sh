#!/usr/bin/env bash
set -eo pipefail

OUT="${1:?Bitte Zieldatei angeben, z.B. ./scan.pdf}"
BASE="$HOME/Dokumente/000_EINGANG/.tmp"
TMP="$BASE/scan_$$"
DEVICE="pixma:04A91854_13B779"

mkdir -p "$TMP/lauf1" "$TMP/lauf2"
#trap 'rm -rf "$TMP"' EXIT

echo
echo "Start Scan  ..."
echo

scanadf \
    --device "$DEVICE" \
    --source "Automatic Document Feeder" \
    --resolution 150 \
    --mode Color \
    -x 210 -y 297 \
    -o "$TMP/lauf1/page_%03d.png"

shopt -s nullglob
seiten1=( "$TMP/lauf1"/page_* )

if (( ${#seiten1[@]} == 0 )); then
    echo "Fehler: Keine Seiten im ersten Durchlauf gefunden."
    exit 1
fi

echo
read -rp "Stapeln umdrehen und Enter für Scan 2 drücken – oder [s] zum Überspringen: " ANTWORT

if [[ ! "$ANTWORT" =~ ^[sS]$ ]]; then
    echo
    echo "Start der Rückseiten ..."
    echo
    # Ein leerer zweiter Durchlauf ist erlaubt, etwa bei einem einseitigen Dokument.
    scanadf \
        --device "$DEVICE" \
        --source "Automatic Document Feeder" \
        --resolution 150 \
        --mode Color \
        -x 210 -y 297 \
        -o "$TMP/lauf2/page_%03d.png"

    seiten2=( "$TMP/lauf2"/page_* )
fi

echo "Dateien Lauf 1:"
printf '  %s\n' "${seiten1[@]}"

echo "Dateien Lauf 2:"
printf '  %s\n' "${seiten2[@]}"

echo
echo "OCR läuft ..."
echo

for f in "${seiten1[@]}" "${seiten2[@]}"; do
    pdf="${f%.*}.pdf"
    tesseract "$f" "${pdf%.pdf}" -l deu pdf
done

echo
echo "PDF wird zusammengeführt ..."
echo

# Beispiel:
# Lauf 1: 1, 3, 5, 7
# Lauf 2: 8, 6, 4, 2
# Ergebnis: 1, 2, 3, 4, 5, 6, 7, 8
#
# Der zweite Lauf wird rückwärts verwendet. Hat Lauf 1 eine Seite mehr,
# wird diese letzte, ungerade Seite einfach zuletzt angehängt.
pdfs=()

for ((i=0, j=${#seiten2[@]}-1; j>=0; i++, j--)); do
    pdfs+=( "${seiten1[i]%.*}.pdf" )
    pdfs+=( "${seiten2[j]%.*}.pdf" )
done

for ((; i<${#seiten1[@]}; i++)); do
    pdfs+=( "${seiten1[i]%.*}.pdf" )
done

mkdir -p "$(dirname "$OUT")"
pdfunite "${pdfs[@]}" "$OUT"
if [ $? -eq 0 ]; then
    rm -r $TMP
else
    echo "Es ist ein Fehler aufgetreten"
    exit 1
fi


echo
echo "PDF fertiggestellt: $OUT"
