#!/data/data/com.termux/files/usr/bin/bash

cd "$(dirname "$0")" || exit 1

mkdir -p iso_in wbfs_out/wbfs

APP_DIR="$(pwd -P)"
ISO_DIR="$APP_DIR/iso_in"
WBFS_OUT_DIR="$APP_DIR/wbfs_out"
WBFS_DIR="$WBFS_OUT_DIR/wbfs"
SPLIT_SIZE="2G"

WIT_BACKEND=""

INFO_DUMP=""
INFO_IS_WII=0
INFO_GAME_ID=""
INFO_TITLE=""
INFO_DISC_NAME=""
INFO_DB_TITLE=""
INFO_ID_REGION=""
INFO_REGION_SETTING=""

OUTPUT_TITLE=""
OUTPUT_REGION_TEXT=""
OUTPUT_FOLDER_NAME=""
OUTPUT_PREFIX=""
FINAL_DIR=""
TMP_DIR=""
OUT=""
TMP_OUT=""

prepare_dirs() {
    cd "$APP_DIR" || return 1
    mkdir -p "$ISO_DIR" "$WBFS_DIR"
}

sanitize_name() {
    local text="$1"

    text="$(printf '%s' "$text" | tr '\r\n\t' '   ')"
    text="$(printf '%s' "$text" | sed -E 's/[^[:alnum:] ]+/ /g')"
    text="$(printf '%s' "$text" | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"

    printf '%s\n' "$text"
}

lower_text() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

build_region_text() {
    local id_region="$1"
    local region_setting="$2"
    local id_lower
    local setting_lower

    id_region="$(sanitize_name "$id_region")"
    region_setting="$(sanitize_name "$region_setting")"

    if [ -z "$id_region" ] && [ -z "$region_setting" ]; then
        return 0
    fi

    if [ -z "$id_region" ]; then
        printf '%s\n' "$region_setting"
        return 0
    fi

    if [ -z "$region_setting" ]; then
        printf '%s\n' "$id_region"
        return 0
    fi

    id_lower="$(lower_text "$id_region")"
    setting_lower="$(lower_text "$region_setting")"

    if [ "$id_lower" = "$setting_lower" ]; then
        printf '%s\n' "$id_region"
        return 0
    fi

    case " $id_lower " in
        *" $setting_lower "*)
            printf '%s\n' "$id_region"
            return 0
            ;;
    esac

    case " $setting_lower " in
        *" $id_lower "*)
            printf '%s\n' "$region_setting"
            return 0
            ;;
    esac

    printf '%s %s\n' "$id_region" "$region_setting"
}

clean_temp_wbfs() {
    find "$WBFS_DIR" -maxdepth 1 -type d -iname "*.iso2wbfs_part_dir" -exec rm -rf {} +
    find "$WBFS_DIR" -maxdepth 1 -type f -iname "*.iso2wbfs_part.wbfs" -exec rm -f {} +
    find "$WBFS_DIR" -maxdepth 1 -type f -iname "*.iso2wbfs_part.wbf*" -exec rm -f {} +
}

detect_wit() {
    if command -v wit >/dev/null 2>&1; then
        WIT_BACKEND="termux"
        return 0
    fi

    if command -v proot-distro >/dev/null 2>&1; then
        if proot-distro login debian -- bash -lc 'command -v wit >/dev/null 2>&1' >/dev/null 2>&1; then
            WIT_BACKEND="debian"
            return 0
        fi
    fi

    WIT_BACKEND=""
    return 1
}

run_wit() {
    case "$WIT_BACKEND" in

        termux)
            wit "$@"
            ;;

        debian)
            proot-distro login debian -- wit "$@"
            ;;

        *)
            return 127
            ;;

    esac
}

require_wit() {
    detect_wit >/dev/null 2>&1

    if [ -z "$WIT_BACKEND" ]; then
        echo
        echo "Missing required tool: wit"
        echo
        echo "Run Setup / Update from option 9, then try again."
        echo
        read -p "Press Enter to continue..."
        return 1
    fi

    return 0
}

load_iso_info() {
    local iso="$1"

    INFO_DUMP=""
    INFO_IS_WII=0
    INFO_GAME_ID=""
    INFO_TITLE=""
    INFO_DISC_NAME=""
    INFO_DB_TITLE=""
    INFO_ID_REGION=""
    INFO_REGION_SETTING=""

    INFO_DUMP="$(run_wit dump "$iso" 2>/dev/null)" || return 1

    if printf '%s\n' "$INFO_DUMP" | grep -Eiq 'File & disc type:[[:space:]]+.*WII[[:space:]]+&[[:space:]]+Wii'; then
        INFO_IS_WII=1
    else
        INFO_IS_WII=0
    fi

    INFO_GAME_ID="$(printf '%s\n' "$INFO_DUMP" \
        | sed -nE 's/.*Disc & part IDs:[[:space:]]+disc=([A-Za-z0-9]{6}).*/\1/p' \
        | head -n 1 \
        | tr '[:lower:]' '[:upper:]')"

    if [ -z "$INFO_GAME_ID" ]; then
        INFO_GAME_ID="$(printf '%s\n' "$INFO_DUMP" \
            | sed -nE 's/.*Disc & part IDs:.*boot=([A-Za-z0-9]{6}).*/\1/p' \
            | head -n 1 \
            | tr '[:lower:]' '[:upper:]')"
    fi

    INFO_DB_TITLE="$(printf '%s\n' "$INFO_DUMP" \
        | sed -nE 's/^[[:space:]]*DB title:[[:space:]]*(.*)$/\1/p' \
        | head -n 1 \
        | sed -E 's/[[:space:]]+$//')"

    INFO_DISC_NAME="$(printf '%s\n' "$INFO_DUMP" \
        | sed -nE 's/^[[:space:]]*Disc name:[[:space:]]*(.*)$/\1/p' \
        | head -n 1 \
        | sed -E 's/[[:space:]]+$//')"

    INFO_ID_REGION="$(printf '%s\n' "$INFO_DUMP" \
        | sed -nE 's/^[[:space:]]*ID Region:[[:space:]]*([^[]*).*/\1/p' \
        | head -n 1 \
        | sed -E 's/[[:space:]]+$//')"

    INFO_REGION_SETTING="$(printf '%s\n' "$INFO_DUMP" \
        | sed -nE 's/^[[:space:]]*Region setting:[[:space:]]*[0-9]+[[:space:]]*\[([^]]+)\].*/\1/p' \
        | head -n 1 \
        | sed -E 's/[[:space:]]+$//')"

    if [ -n "$INFO_DB_TITLE" ]; then
        INFO_TITLE="$INFO_DB_TITLE"
    elif [ -n "$INFO_DISC_NAME" ]; then
        INFO_TITLE="$INFO_DISC_NAME"
    else
        INFO_TITLE=""
    fi

    return 0
}

make_output_names_from_info() {
    local iso="$1"
    local file_name
    local base
    local title
    local region_text
    local folder_base

    file_name="$(basename "$iso")"
    base="${file_name%.*}"

    if [ -n "$INFO_TITLE" ]; then
        title="$INFO_TITLE"
    else
        title="$base"
    fi

    title="$(sanitize_name "$title")"
    [ -z "$title" ] && title="Unknown"

    region_text="$(build_region_text "$INFO_ID_REGION" "$INFO_REGION_SETTING")"
    region_text="$(sanitize_name "$region_text")"

    OUTPUT_TITLE="$title"
    OUTPUT_REGION_TEXT="$region_text"

    folder_base="$title"

    if [ -n "$region_text" ]; then
        folder_base="$folder_base $region_text"
    fi

    folder_base="$(sanitize_name "$folder_base")"
    [ -z "$folder_base" ] && folder_base="Unknown"

    if [ -n "$INFO_GAME_ID" ]; then
        OUTPUT_PREFIX="$INFO_GAME_ID"
        OUTPUT_FOLDER_NAME="$folder_base [$INFO_GAME_ID]"
    else
        OUTPUT_PREFIX="$(sanitize_name "$base")"
        [ -z "$OUTPUT_PREFIX" ] && OUTPUT_PREFIX="Unknown"
        OUTPUT_FOLDER_NAME="$folder_base"
    fi

    FINAL_DIR="$WBFS_DIR/$OUTPUT_FOLDER_NAME"
    TMP_DIR="$WBFS_DIR/$OUTPUT_FOLDER_NAME.iso2wbfs_part_dir"

    OUT="$FINAL_DIR/$OUTPUT_PREFIX.wbfs"
    TMP_OUT="$TMP_DIR/$OUTPUT_PREFIX.wbfs"
}

make_output_names_fallback() {
    local iso="$1"
    local file_name
    local base
    local clean_base

    file_name="$(basename "$iso")"
    base="${file_name%.*}"
    clean_base="$(sanitize_name "$base")"
    [ -z "$clean_base" ] && clean_base="Unknown"

    INFO_IS_WII=0
    INFO_GAME_ID=""
    INFO_TITLE="$clean_base"
    INFO_ID_REGION=""
    INFO_REGION_SETTING=""

    OUTPUT_TITLE="$clean_base"
    OUTPUT_REGION_TEXT=""
    OUTPUT_PREFIX="$clean_base"
    OUTPUT_FOLDER_NAME="$clean_base"

    FINAL_DIR="$WBFS_DIR/$OUTPUT_FOLDER_NAME"
    TMP_DIR="$WBFS_DIR/$OUTPUT_FOLDER_NAME.iso2wbfs_part_dir"

    OUT="$FINAL_DIR/$OUTPUT_PREFIX.wbfs"
    TMP_OUT="$TMP_DIR/$OUTPUT_PREFIX.wbfs"
}

convert_wii_iso_recommended() {
    clear

    if ! require_wit; then
        return
    fi

    prepare_dirs || return

    clean_temp_wbfs

    echo
    echo "Convert Wii ISO to WBFS (recommended)"
    echo
    echo "Split size:"
    echo "$SPLIT_SIZE"
    echo
    echo "Source folder:"
    echo "$ISO_DIR"
    echo
    echo "Output folder:"
    echo "$WBFS_DIR"
    echo
    echo "To use on SD/USB:"
    echo "Copy this folder to the root of your SD/USB:"
    echo "$WBFS_DIR"
    echo

    found=0
    converted=0
    skipped=0
    not_wii=0
    deleted_iso=0
    errors=0

    while IFS= read -r -d '' iso; do
        found=1

        echo
        echo "----------------------------------------"
        echo "ISO:"
        echo "$iso"
        echo "----------------------------------------"
        echo

        echo "Reading ISO info..."
        echo

        if ! load_iso_info "$iso"; then
            echo "Skipped: ISO info could not be read."
            echo "The ISO may be unknown, corrupted, or unsupported."
            not_wii=$((not_wii + 1))
            skipped=$((skipped + 1))
            continue
        fi

        if [ "$INFO_IS_WII" -ne 1 ]; then
            echo "Skipped: ISO is not detected as a Wii game."
            echo "This may be GameCube, unknown, corrupted, or unsupported."
            not_wii=$((not_wii + 1))
            skipped=$((skipped + 1))
            continue
        fi

        if [ -z "$INFO_GAME_ID" ]; then
            echo "Skipped: Wii game ID could not be read."
            echo "Source ISO was kept for safety."
            not_wii=$((not_wii + 1))
            skipped=$((skipped + 1))
            continue
        fi

        make_output_names_from_info "$iso"

        echo "Game title:"
        echo "$OUTPUT_TITLE"
        echo
        echo "Game ID:"
        echo "$INFO_GAME_ID"
        echo
        echo "Region info:"
        if [ -n "$OUTPUT_REGION_TEXT" ]; then
            echo "$OUTPUT_REGION_TEXT"
        else
            echo "Unknown"
        fi
        echo
        echo "WBFS folder:"
        echo "$FINAL_DIR"
        echo
        echo "Main WBFS:"
        echo "$OUT"
        echo

        if [ -f "$OUT" ]; then
            echo "WBFS already exists. Checking it..."
            echo

            if run_wit verify "$OUT"; then
                echo
                echo "Existing WBFS is valid. Skipping conversion:"
                echo "$OUT"

                if [ -f "$iso" ]; then
                    if rm -f "$iso"; then
                        echo
                        echo "Source ISO deleted:"
                        echo "$iso"
                        deleted_iso=$((deleted_iso + 1))
                    else
                        echo
                        echo "Error: conversion skipped but source ISO could not be deleted:"
                        echo "$iso"
                        errors=$((errors + 1))
                    fi
                fi

                skipped=$((skipped + 1))
                continue
            else
                echo
                echo "Existing WBFS is invalid. Removing game folder and converting again:"
                echo "$FINAL_DIR"
                rm -rf "$FINAL_DIR"
            fi
        elif [ -e "$FINAL_DIR" ]; then
            echo "Existing game folder is incomplete or invalid. Removing it:"
            echo "$FINAL_DIR"
            rm -rf "$FINAL_DIR"
        fi

        rm -rf "$TMP_DIR"
        mkdir -p "$TMP_DIR"

        if run_wit copy --wbfs --split-size "$SPLIT_SIZE" "$iso" "$TMP_OUT"; then
            echo
            echo "Verifying temporary WBFS..."
            echo

            if run_wit verify "$TMP_OUT"; then
                rm -rf "$FINAL_DIR"

                if mv -f "$TMP_DIR" "$FINAL_DIR" && [ -s "$OUT" ]; then
                    echo
                    echo "Conversion completed:"
                    echo "$FINAL_DIR"
                    echo
                    echo "Created files:"
                    find "$FINAL_DIR" -maxdepth 1 -type f \( -iname "*.wbfs" -o -iname "*.wbf*" \) -print | sort

                    converted=$((converted + 1))

                    if [ -f "$iso" ]; then
                        if rm -f "$iso"; then
                            echo
                            echo "Source ISO deleted:"
                            echo "$iso"
                            deleted_iso=$((deleted_iso + 1))
                        else
                            echo
                            echo "Error: WBFS is valid but source ISO could not be deleted:"
                            echo "$iso"
                            errors=$((errors + 1))
                        fi
                    fi
                else
                    rm -rf "$TMP_DIR"

                    echo
                    echo "Error: final WBFS folder could not be created:"
                    echo "$FINAL_DIR"

                    errors=$((errors + 1))
                fi
            else
                rm -rf "$TMP_DIR"

                echo
                echo "Error: invalid WBFS after conversion:"
                echo "$iso"

                errors=$((errors + 1))
            fi
        else
            rm -rf "$TMP_DIR"

            echo
            echo "Error: conversion failed:"
            echo "$iso"

            errors=$((errors + 1))
        fi

    done < <(find "$ISO_DIR" -maxdepth 1 -type f -iname "*.iso" -print0)

    clean_temp_wbfs

    echo
    echo "========================================"
    echo "Summary"
    echo "========================================"
    echo
    echo "Converted:          $converted"
    echo "Skipped:            $skipped"
    echo "Not Wii / Unknown:  $not_wii"
    echo "Deleted ISO:        $deleted_iso"
    echo "Errors:             $errors"
    echo

    if [ "$found" -eq 0 ]; then
        echo "No ISO file found in:"
        echo "$ISO_DIR"
        echo
    fi

    read -p "Press Enter to continue..."
}

force_convert_all_iso() {
    clear

    if ! require_wit; then
        return
    fi

    prepare_dirs || return

    clean_temp_wbfs

    echo
    echo "Force convert ISO to WBFS (expert mode)"
    echo
    echo "Warning:"
    echo "This mode does not check if the ISO is a Wii game."
    echo "GameCube or unknown ISO files may produce WBFS files that are not usable."
    echo
    echo "Split size:"
    echo "$SPLIT_SIZE"
    echo
    read -p "Continue? Type y to confirm: " confirm

    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo
        echo "Cancelled."
        echo
        read -p "Press Enter to continue..."
        return
    fi

    echo
    echo "Source folder:"
    echo "$ISO_DIR"
    echo
    echo "Output folder:"
    echo "$WBFS_DIR"
    echo
    echo "To use on SD/USB:"
    echo "Copy this folder to the root of your SD/USB:"
    echo "$WBFS_DIR"
    echo

    found=0
    converted=0
    skipped=0
    errors=0

    while IFS= read -r -d '' iso; do
        found=1

        echo
        echo "----------------------------------------"
        echo "ISO:"
        echo "$iso"
        echo "----------------------------------------"
        echo

        if load_iso_info "$iso"; then
            make_output_names_from_info "$iso"
        else
            echo "Warning: ISO info could not be read."
            echo "Output will use the cleaned ISO file name."
            make_output_names_fallback "$iso"
        fi

        echo
        echo "WBFS folder:"
        echo "$FINAL_DIR"
        echo
        echo "Main WBFS:"
        echo "$OUT"
        echo

        if [ -z "$INFO_GAME_ID" ]; then
            echo "Warning: no game ID was found."
            echo "USB Loader GX compatibility may be reduced."
            echo
        fi

        if [ -f "$OUT" ]; then
            echo "WBFS already exists. Checking it..."
            echo

            if run_wit verify "$OUT"; then
                echo
                echo "Existing WBFS is valid. Skipping conversion:"
                echo "$OUT"

                skipped=$((skipped + 1))
                continue
            else
                echo
                echo "Existing WBFS is invalid. Removing game folder and converting again:"
                echo "$FINAL_DIR"
                rm -rf "$FINAL_DIR"
            fi
        elif [ -e "$FINAL_DIR" ]; then
            echo "Existing game folder is incomplete or invalid. Removing it:"
            echo "$FINAL_DIR"
            rm -rf "$FINAL_DIR"
        fi

        rm -rf "$TMP_DIR"
        mkdir -p "$TMP_DIR"

        if run_wit copy --wbfs --split-size "$SPLIT_SIZE" "$iso" "$TMP_OUT"; then
            echo
            echo "Verifying temporary WBFS..."
            echo

            if run_wit verify "$TMP_OUT"; then
                rm -rf "$FINAL_DIR"

                if mv -f "$TMP_DIR" "$FINAL_DIR" && [ -s "$OUT" ]; then
                    echo
                    echo "Conversion completed:"
                    echo "$FINAL_DIR"
                    echo
                    echo "Created files:"
                    find "$FINAL_DIR" -maxdepth 1 -type f \( -iname "*.wbfs" -o -iname "*.wbf*" \) -print | sort

                    converted=$((converted + 1))
                else
                    rm -rf "$TMP_DIR"

                    echo
                    echo "Error: final WBFS folder could not be created:"
                    echo "$FINAL_DIR"

                    errors=$((errors + 1))
                fi
            else
                rm -rf "$TMP_DIR"

                echo
                echo "Error: invalid WBFS after conversion:"
                echo "$iso"

                errors=$((errors + 1))
            fi
        else
            rm -rf "$TMP_DIR"

            echo
            echo "Error: conversion failed:"
            echo "$iso"

            errors=$((errors + 1))
        fi

    done < <(find "$ISO_DIR" -maxdepth 1 -type f -iname "*.iso" -print0)

    clean_temp_wbfs

    echo
    echo "========================================"
    echo "Summary"
    echo "========================================"
    echo
    echo "Converted: $converted"
    echo "Skipped:   $skipped"
    echo "Errors:    $errors"
    echo
    echo "Expert mode does not delete source ISO files."
    echo

    if [ "$found" -eq 0 ]; then
        echo "No ISO file found in:"
        echo "$ISO_DIR"
        echo
    fi

    read -p "Press Enter to continue..."
}

dump_all_iso() {
    clear

    if ! require_wit; then
        return
    fi

    prepare_dirs || return

    echo
    echo "Dump all ISO info from iso_in"
    echo
    echo "Folder:"
    echo "$ISO_DIR"
    echo

    found=0
    errors=0

    while IFS= read -r -d '' iso; do
        found=1

        echo
        echo "========================================"
        echo "ISO:"
        echo "$iso"
        echo "========================================"
        echo

        if ! run_wit dump "$iso"; then
            echo
            echo "Error: dump failed:"
            echo "$iso"

            errors=$((errors + 1))
        fi

    done < <(find "$ISO_DIR" -maxdepth 1 -type f -iname "*.iso" -print0)

    echo
    echo "========================================"
    echo "Summary"
    echo "========================================"
    echo
    echo "Errors: $errors"
    echo

    if [ "$found" -eq 0 ]; then
        echo "No ISO file found in:"
        echo "$ISO_DIR"
        echo
    fi

    read -p "Press Enter to continue..."
}

verify_all_wbfs() {
    clear

    if ! require_wit; then
        return
    fi

    prepare_dirs || return

    clean_temp_wbfs

    echo
    echo "Verify WBFS files"
    echo
    echo "Folder:"
    echo "$WBFS_DIR"
    echo

    found=0
    valid=0
    errors=0

    while IFS= read -r -d '' wbfs; do
        found=1

        echo
        echo "----------------------------------------"
        echo "Checking:"
        echo "$wbfs"
        echo "----------------------------------------"
        echo

        if run_wit verify "$wbfs"; then
            valid=$((valid + 1))
        else
            errors=$((errors + 1))
        fi

    done < <(find "$WBFS_DIR" -type f \
        -iname "*.wbfs" \
        ! -path "*/.iso2wbfs_part_dir/*" \
        ! -iname "*.iso2wbfs_part.wbfs" \
        -print0)

    echo
    echo "========================================"
    echo "Summary"
    echo "========================================"
    echo
    echo "Valid:  $valid"
    echo "Errors: $errors"
    echo

    if [ "$found" -eq 0 ]; then
        echo "No WBFS file found in:"
        echo "$WBFS_DIR"
        echo
    fi

    read -p "Press Enter to continue..."
}

show_wit_status() {
    clear

    detect_wit >/dev/null 2>&1

    echo
    echo "WIT status"
    echo

    case "$WIT_BACKEND" in

        termux)
            echo "Backend: Termux native"
            echo
            wit --version
            ;;

        debian)
            echo "Backend: Debian via proot-distro"
            echo
            proot-distro login debian -- wit --version
            ;;

        *)
            echo "Backend: not installed"
            echo
            echo "Run Setup / Update from option 9."
            ;;

    esac

    echo
    read -p "Press Enter to continue..."
}

run_setup() {
    clear

    prepare_dirs || return

    if [ -f "$APP_DIR/iso2wbfs_setup.sh" ]; then
        bash "$APP_DIR/iso2wbfs_setup.sh"
        prepare_dirs || return
        detect_wit >/dev/null 2>&1
    else
        echo
        echo "Setup file is missing:"
        echo "$APP_DIR/iso2wbfs_setup.sh"
        echo
        echo "Please reinstall iso2wbfs_android because a required file is missing."
        echo
        read -p "Press Enter to continue..."
    fi
}

detect_wit >/dev/null 2>&1

while true; do
    clear

    echo
    echo "iso2wbfs_android"
    echo
    echo
    echo "1) Convert Wii ISO to /wbfs/ (recommended)"
    echo
    echo "2) Force convert ISO to /wbfs/ (expert mode)"
    echo
    echo "3) Dump all ISO info from iso_in"
    echo
    echo "4) Verify all WBFS from wbfs_out/wbfs"
    echo
    echo "5) Show WIT status"
    echo
    echo
    echo "9) Run Setup / Update (required before first use)"
    echo
    echo "0) Exit"
    echo
    echo

    read -p "Choose what to do: " choice

    case "$choice" in

        1)
            convert_wii_iso_recommended
            ;;

        2)
            force_convert_all_iso
            ;;

        3)
            dump_all_iso
            ;;

        4)
            verify_all_wbfs
            ;;

        5)
            show_wit_status
            ;;

        9)
            run_setup
            ;;

        0)
            clear
            exit 0
            ;;

        *)
            echo
            echo "Invalid choice."
            sleep 1
            ;;

    esac
done
