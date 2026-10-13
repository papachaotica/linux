#!/bin/bash

set -eo pipefail

TMPBASE="/tmp"
DEVICE="pixma:04A91854_13B779"
SOURCE="Automatic Document Feeder"

##############################################################################
##############################################################################

help() {
cat << END
Usage:  $0 [OPTIONS] -o FILE.pdf
  --adf                     Select scanner source feeder
  --altinterleave           Sorting scanned pages in 
                            Run: 1, 3, 5, 6, 4, 2 -> 1, 2, 3, 4, 5, 6
  --button                  Use button on scanner to start scanner run
  --color MODE              Corlormode: auto|[Color]|Gray|Lineart
  -d, --device DEVICE       Select DEVICE for sane
  --duplex                  This scans frontside of pages, than backsides
                            implices --altinterleave
  --force                   Allow overwirte files
  --flat                    Select scanner source flatbet
                            Not implement yet!
  -h, --help                Show this help.
  -i, --import FILE         Imports pdf at end scannes pages
  -n, --number NUMBER       Number of retery scan runs
  -o|--output           
  --reverse                 Sorting mode reverse of scans
  --resolution NUMBER       75|150|[300]|600 dpi
  --split PAGES             Split output in PAGES files
                            Use: %d or %02d
  --sign "NICK" "COMMENT"   Signing pdf with S/MIME
  --tmp                     Override TMP dir, use this to retery broken scan
END
}

##############################################################################
# args
##############################################################################

PID=$$

check_integer() {
    if [[ ! "$2" =~ ^[1-9][0-9+$]*$ ]]; then
        printf "\nError: %s only allows a positive integer; you entered %s.\n" "$1" "$2"
        help ; exit 2
    fi
    return 0
}

allowed() {
    printf "\nError: %s only allowed %s" "$1" "$2"
    printf "\n       you has wrote %s" "$3"
    help; exit 2
}

importfiles=()
while (( $# > 0  )); do
    case "$1" in
        --adf) SOURCEMODE="adf"; shift ;;
        --altinterleave) SORTMODE="altinterleave"; shift ;;
        --button) BUTTONMODE=true; shift ;;
        --color) ALLOWED="auto|Color|Gray|Lineart" COLORMODE="$2"
            case "$COLORMODE" in
                $ALLOWED) ;;
                *)  allowed "$1" "$ALLOWED" "$2";;
            esac; shift 2 ;;
        -d|--device) DEVICE="$2"; shift 2 ;;
        --duplex) SCANMODE="duplex" SORTMODE="altinterleave"; shift ;;
        --flat) SOURCEMODE="flat"; shift ;;
        --force) FORCE=true; shift ;;
        -h|--help) help; exit 0 ;;
        -i|--import) IMPORT=true importfiles+=( "$2"); shift 2 ;;
        -n|--number) N="$2"; check_integer "$1" "$2"; shift 2 ;;
        -o|--output) OUTPUT="$2"; shift 2 ;;
        --ocr-lang) OCRLANG="$2"; shift 2 ;;
        --resolution) ALLOWED="auto|75|150|300|600" DPI="$2"
            case "$DPI" in
                $ALLOWED) ;;
                *)  allowed "$1" "$ALLOWED" "$2" ;;
            esac; shift 2 ;;
        --reverse) SORTMODE="reverse"; shift ;;
        --simplex) SCANMODE="simplex"; shift ;;
        --size) ALLOWED="a4|a5|legal|letter" PAPERSIZE="$2"
            case "$PAPERSIZE" in
                a4) X=210 Y=297 ;;
                a5) X=210 Y=148 ;;
                legal) X=216 Y=356 ;;
                letter) X=216 Y=279 ;;
                *) allowed "$1" "$ALLOWED" "$2" ;;
            esac; shift 2 ;;
        --source) SOURCE="$2"; shift 2 ;;
        --split) SPLIT="$2"; check_integer "$1" "$SPLIT"; shift 2 ;;
        --sign) SIGN=true SIGNICK="$2" COMMENT=("$3"); shift 3 ;;
        --tmp) TMP_GIVEN=true TMPBASE="$2"; shift 2 ;;
        *) printf "Unknown option: %s\n" "$1"; help; exit 2 ;;
    esac
done

##############################################################################
# post args
##############################################################################

# output
file_exist() {
    local file="$1"
    local answer
    if [[ -e "$file" && "${FORCE:-false}" != true ]]; then
        read -rp "File $1 allread exits, for overwriteing write: 'force' : " answer
        if [[ "$answer" != "force" ]]; then
            return 1
        fi
    fi
    return 0
}

if [ ! "$OUTPUT"  ]; then
    printf "Output are required"; help; exit 2
fi
if [[ "$OUTPUT" != *.pdf ]]; then
    printf "\nError: %s ist not .pdf\n" "$OUTPUT"
    exit 2
fi
if ! file_exist "$OUTPUT"; then
    printf "\nVorgang abgebrochen\n"; help; exit 2
fi
if [ ! $SPLIT ]; then
    SPLIT=0
elif (( SPLIT > 0 )) && [[ ! "$OUTPUT" =~ ^[^%]*%0?[0-9]*d[^%]*$ ]]; then
    printf "Error: --split have to placeholder like '%%d' or '%%02d'"
    help; exit 2
fi

# import
if [[ "${IMPORT:-false}" == true ]]; then
    for importfile in "${importfiles[@]}"; do
        if [[ ! -f "$importfile" ]] || [[ ! "$importfile" = *.pdf ]]; then
            printf "Error: %s can not import\n" "$importfile"
            exit 2
        fi
    done
fi

# papersize
if [ ! $PAPERSIZE  ]; then
    X=210 Y=297
fi

# scanner
if [ ! "$DEVICE" ] || [ ! "$SOURCE" ]; then
    printf "Error: --device and --source have to given"
    help; exit 2
fi

##############################################################################
# scanning
##############################################################################

scanner_run() {
    local count=$(printf "%03d" $(( $(find "$TMPDIR" -maxdepth 1 -type f -name "page_*.png" | wc -l) + 1 )) )
    local ref="$TMPDIR/timestamp.ref"
    if ! touch "$ref"; then
        printf "Error: timestamp.ref could not be created.\n"
        exit 2
    fi
    if [ ${SOURCEMODE:-false} == "adf" ]; then
        scancommand=(
            scanadf
            --device "$DEVICE"
            --source "$SOURCE"
            --verbose
            -x "$X"
            -y "$Y"
            -s "$count"
            -o "$TMPDIR/page_%03d.png"
        )
    elif [ ${SOURCEMODE:-false} == "flat"  ]; then
        scancommand=( 
            scanimage
            --device-name=$DEVICE
            -x "$X"
            -y "$Y"
            --verbose
            --progress
            --batch="$TMPDIR/page_%03d.png"
            --batch-count=1
            --batch-start=$count
        )
    else
        printf "\n--adf or --flat have to use\n\n"; help; exit 2
    fi
    if [[ -n "$COLORMODE" ]]; then
        scancommand+=( --mode "$COLORMODE" )
    fi
    if [[ -n "$DPI"  ]]; then
        scancommand+=( --resolution "$DPI" )
    else
        scancommand+=( --resolution 300 )
    fi
    if [ "${BUTTONMODE:-false}" == true ]; then
        scancommand+=( --button-controlled yes )
    fi
echo "${scancommand[@]}"
    if "${scancommand[@]}"; then
        :
    else
        printf "There was a problem with the scanner, exitcode %s" "$?"
        exit 2
    fi
    newfiles=( $(find "$TMPDIR" -maxdepth 1 -type f -newer "$ref" -name "page_*.png" | sort) )
    scans+=( "${newfiles[@]}" )
    return 0
}

scans=()
# retery brocken scan's
if [[ "${TMP_GIVEN:-false}" == true ]]; then
    TMPDIR="$TMPBASE"
    oldfiles=( $(find "$TMPDIR" -maxdepth 1 -type f -name "page_*.png" | sort) )
    scans+=( "${oldfiles[@]}" )
else
    TMPDIR="$TMPBASE/scanpdf_$PID"
fi

if ! mkdir -p "$TMPDIR"; then
    printf "Error: %s Directory could not be created.\n" "$TMPDIR"
    exit 2
fi

printf "\n\nStarting with scanning\n\n"

if [ ! $N ]; then
    N=1
fi

for (( run = 1; run <= N; run++  )); do
    if (( run == 1 && run < N  )); then
        printf "\nRun 1 of %d\n\n" "$N"
    fi
    scanner_run
    if [ "${SCANMODE:-false}" == "duplex" ]; then
        scanner_run
    fi
    if (( run < N )); then
        printf "\nNext run %d of %d\n\n" "$(( run + 1 ))" "$N"
        if [ ${BUTTONMODE:-false} != true ]; then
            read -rp "Please insert next block of papers und press ENTER"
            echo
        fi
    fi
done

if (( ${#scans[@]} == 0 )); then
    printf "\nError: No scanns can be found!\n\n"
    exit 2
fi

##############################################################################
# ocr
##############################################################################

declare -A language
language=(
    [de]="deu"
    [en]="eng"
)
if [ ! $OCRLANG ]; then
    locale=${LANG:0:2}
    OCRLANG=${language[$locale]}
fi

pdfs=()
printf "OCR is running fr %d papers ..." "${#scans[@]}"
for scan in "${scans[@]}"; do
    if ! tesseract "$scan" "${scan%.*}" -l "$OCRLANG" pdf; then
        printf "Error: Problem with ocr on %s" "$scan"
        exit 2
    fi
    pdfs+=( "${scan%.*}.pdf" )
done

##############################################################################
# import
##############################################################################

output=()
if [[ "${IMPORT:-false}" == true ]]; then
    printf "\n\nImporting files ...\n\n"
    import_number=1
    for importfile in "${importfiles[@]}"; do
        printf "Importing %s" "$importfile"
        printf -v importcopy '%s/import_%03d.pdf' "$TMPDIR" "$import_number"
        if ! cp -- "$importfile" "$importcopy"; then
            printf "Error: copy failed with %s" "$importfile"
            exit 2
        fi
        output+=( "$importcopy" )
        (( import_number++ ))
    done
fi

##############################################################################
# sorting pages
##############################################################################

print_array() {
    local array=("$1")
    if (( ${#array[@]} > 0 )); then
        for file in "${array[@]}"; do
            printf "\n%s" "$file"
        done
    fi
    return 0
}
printf "\n\nSorting pages\n\n"

if [[ $SORTMODE == "altinterleave" ]]; then
    printf "\nMode: --altinterleave"
    printf "\nscan: 1, 3, 5, 6, 4, 2 -> 1, 2, 3, 4, 5, 6\n"
    print_array "${output[@]}"
    for ((i=0, j=${#pdfs[@]}-1; i<=j; i++, j--)); do
        file="${pdfs[i]}"
        printf "$file\n"
        output+=( "$file" )
        if (( i != j )); then
            file="${pdfs[j]}"
            printf "$file\n"
            output+=( "$file" )
        fi
    done
fi

if [[ $SORTMODE == "reverse" ]]; then
    printf "\nMode: --reverse\n"
    print_array "${output[@]}"
    for ((i=${#pdfs[@]}-1; i>=0; i--)); do
        file="${pdfs[i]}"
        printf "$file\n"
        output+=( "$file" )
    done
fi

if [ ! $SORTMODE  ]; then
    printf "\nMode: normal forward\n"
    print_array "${output[@]}"
    for file in "${pdfs[@]}"; do
        printf "\n%s""$file"
        output+=( "$file" )
    done
fi

##############################################################################
# output
##############################################################################

pdf_sig() {
    local target="$1"
    local sig_target="${target%.pdf}.sign.pdf"
    if file_exits "$sig_target"; then
        if ! pdfsig "$target" "$sig_target" -add-singnature -nick "$SIGNICK" -reason "${COMMENT[@]}" 2>&1; then
            printf "Signature not succesful created for %s" "$sig_target"
            rm_ok=false
            return 2
        fi
        report=$(pdfsig $sig_target 2>&1)
        printf "%s\n" "$report"
        if   ! grep -Fq 'Signature Validation: Signature is Valid.' <<<"$report"; then
            printf "Error: Signatur is not valid for %s" "$sig_target"
            return 2
        elif ! grep -Fq 'Total document signed' <<<"$report"; then
            printf "Error: Signatur not vaild for full document %s" "$sig_target"
            return 2
        fi
    fi
    return 0
}

printf "\n\nBuild output pdf\n"

number=1
count=0

if (( SPLIT == 0 )); then
    split=${#output[@]}
else
    split="$SPLIT"
fi


while (( count < ${#output[@]}  )); do
    if (( SPLIT == 0 )); then
        target="$OUTPUT"
    else
        printf -v target "$OUTPUT" "$number"
    fi
    pages=( "${output[@]:count:SPLIT}" )
    if file_exist "$target"; then
        if ! pdfunite "${pages[@]}" "$target"; then
            printf "Error: %s can not create" "$target"
            rm_ok=false
        else
            printf "%s succesful created" "$target"
        fi
    fi
    if [ "${SIGN:-false}" == true ]; then
        if ! pdf_sig "$target"; then
            rm_ok=false
        fi
    fi
    (( number++, count += split ))
done

if [ "$rm_ok" == false ]; then
    printf "Error: detect not delete %s" "$TMPDIR"
    exit 2
fi
rm -r "$TMPDIR"
printf "Complete finisched"
