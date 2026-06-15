#!/data/data/com.termux/files/usr/bin/bash

cd "$(dirname "$0")" || exit 1

mkdir -p iso_in wbfs_out

APP_DIR="$(pwd -P)"
ISO_DIR="$APP_DIR/iso_in"
WBFS_DIR="$APP_DIR/wbfs_out"

WIT_BACKEND=""

prepare_dirs() {
    cd "$APP_DIR" || return 1
    mkdir -p "$ISO_DIR" "$WBFS_DIR"
}

clean_temp_wbfs() {
    find "$WBFS_DIR" -maxdepth 1 -type f -iname "*.iso2wbfs_part.wbfs" -exec rm -f {} +
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

is_wii_iso() {
    local dump_output

    dump_output="$(run_wit dump "$1" 2>/dev/null)" || return 1

    printf '%s\n' "$dump_output" | grep -Eiq 'File & disc type:[[:space:]]+.*WII[[:space:]]+&[[:space:]]+Wii'
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
    echo "Source folder:"
    echo "$ISO_DIR"
    echo
    echo "Output folder:"
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

        file_name="$(basename "$iso")"
        base="${file_name%.*}"

        out="$WBFS_DIR/$base.wbfs"
        tmp_out="$WBFS_DIR/$base.iso2wbfs_part.wbfs"

        echo
        echo "----------------------------------------"
        echo "ISO:"
        echo "$iso"
        echo
        echo "WBFS:"
        echo "$out"
        echo "----------------------------------------"
        echo

        echo "Checking ISO type..."
        echo

        if ! is_wii_iso "$iso"; then
            echo "Skipped: ISO is not detected as a Wii game."
            echo "This may be GameCube, unknown, corrupted, or unsupported."
            not_wii=$((not_wii + 1))
            skipped=$((skipped + 1))
            continue
        fi

        if [ -e "$out" ]; then
            echo "WBFS already exists. Checking it..."
            echo

            if run_wit verify "$out"; then
                echo
                echo "Existing WBFS is valid. Skipping conversion:"
                echo "$out"

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
                echo "Existing WBFS is invalid. Removing it and converting again:"
                echo "$out"
                rm -f "$out"
            fi
        fi

        rm -f "$tmp_out"

        if run_wit copy --wbfs "$iso" "$tmp_out"; then
            echo
            echo "Verifying temporary WBFS..."
            echo

            if run_wit verify "$tmp_out"; then
                if mv -f "$tmp_out" "$out" && [ -s "$out" ]; then
                    echo
                    echo "Conversion completed:"
                    echo "$out"

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
                    rm -f "$tmp_out"

                    echo
                    echo "Error: final WBFS could not be created:"
                    echo "$out"

                    errors=$((errors + 1))
                fi
            else
                rm -f "$tmp_out"

                echo
                echo "Error: invalid WBFS after conversion:"
                echo "$iso"

                errors=$((errors + 1))
            fi
        else
            rm -f "$tmp_out"

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

    found=0
    converted=0
    skipped=0
    errors=0

    while IFS= read -r -d '' iso; do
        found=1

        file_name="$(basename "$iso")"
        base="${file_name%.*}"

        out="$WBFS_DIR/$base.wbfs"
        tmp_out="$WBFS_DIR/$base.iso2wbfs_part.wbfs"

        echo
        echo "----------------------------------------"
        echo "ISO:"
        echo "$iso"
        echo
        echo "WBFS:"
        echo "$out"
        echo "----------------------------------------"
        echo

        if [ -e "$out" ]; then
            echo "WBFS already exists. Checking it..."
            echo

            if run_wit verify "$out"; then
                echo
                echo "Existing WBFS is valid. Skipping conversion:"
                echo "$out"

                skipped=$((skipped + 1))
                continue
            else
                echo
                echo "Existing WBFS is invalid. Removing it and converting again:"
                echo "$out"
                rm -f "$out"
            fi
        fi

        rm -f "$tmp_out"

        if run_wit copy --wbfs "$iso" "$tmp_out"; then
            echo
            echo "Verifying temporary WBFS..."
            echo

            if run_wit verify "$tmp_out"; then
                if mv -f "$tmp_out" "$out" && [ -s "$out" ]; then
                    echo
                    echo "Conversion completed:"
                    echo "$out"

                    converted=$((converted + 1))
                else
                    rm -f "$tmp_out"

                    echo
                    echo "Error: final WBFS could not be created:"
                    echo "$out"

                    errors=$((errors + 1))
                fi
            else
                rm -f "$tmp_out"

                echo
                echo "Error: invalid WBFS after conversion:"
                echo "$iso"

                errors=$((errors + 1))
            fi
        else
            rm -f "$tmp_out"

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

    done < <(find "$WBFS_DIR" -maxdepth 1 -type f \
        -iname "*.wbfs" \
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
    echo "1) Convert Wii ISO to WBFS (recommended)"
    echo
    echo "2) Force convert ISO to WBFS (expert mode)"
    echo
    echo "3) Dump all ISO info from iso_in"
    echo
    echo "4) Verify all WBFS from wbfs_out"
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
