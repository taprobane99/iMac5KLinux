#!/usr/bin/env bash
#
# imac-backlight-fix.sh -- 500-nit Backlight Override for iMac 5K (17,1 / 18,3 / 19,1)
#
# Targets:
#   - iMac 2015 (17,1): SSDT6.dat
#   - iMac 2017 (18,3): SSDT2.dat
#   - iMac 2019 (19,1): DSDT.dat
#
set -euo pipefail

log_step() { printf "\n\033[1;34m[STEP %s]\033[0m \033[1m%s\033[0m\n" "$1" "$2"; }
log_info() { printf "  \033[0;32m✓\033[0m %s\n" "$1"; }
log_warn() { printf "  \033[0;33m!\033[0m %s\n" "$1"; }
log_error() { printf "  \033[0;31m✗\033[0m %s\n" "$1" >&2; }

# 1. Dependency and Privilege Validation
log_step "1/5" "Checking prerequisites"
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be executed as root (e.g., sudo $0)."
    exit 1
fi

for cmd in iasl python3 cpio; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Missing required tool: $cmd"
        echo "       Install via: sudo apt install -y acpica-tools python3 cpio" >&2
        exit 1
    fi
done
log_info "All required tools are installed."

# 2. Workspace Setup & Direct Table Extraction
log_step "2/5" "Extracting relevant ACPI tables"
W=$(mktemp -d /tmp/acpi_imac.XXXXXX)
trap 'rm -rf "$W"' EXIT INT TERM
cd "$W"

ACPI_DIR="/sys/firmware/acpi/tables"
if [[ ! -d "$ACPI_DIR" ]]; then
    log_error "ACPI sysfs tables not found at $ACPI_DIR."
    exit 1
fi

# Always copy DSDT since it is required for iMac19,1 or as external reference for SSDTs
if [[ -f "$ACPI_DIR/DSDT" ]]; then
    cat "$ACPI_DIR/DSDT" > DSDT.dat
else
    log_error "DSDT table not found."
    exit 1
fi

# Copy candidate SSDTs if present
[[ -f "$ACPI_DIR/SSDT6" ]] && cat "$ACPI_DIR/SSDT6" > SSDT6.dat
[[ -f "$ACPI_DIR/SSDT2" ]] && cat "$ACPI_DIR/SSDT2" > SSDT2.dat

# Determine which table exists and holds Method (ABCL)
TARGET_BASE=""

# Check SSDT6 (2015 iMac17,1)
if [[ -f SSDT6.dat ]]; then
    iasl -e DSDT.dat -d SSDT6.dat >/dev/null 2>&1 || true
    if [[ -f SSDT6.dsl ]] && grep -q "Method (ABCL" SSDT6.dsl; then
        TARGET_BASE="SSDT6"
    fi
fi

# Check SSDT2 (2017 iMac18,3)
if [[ -z "$TARGET_BASE" && -f SSDT2.dat ]]; then
    iasl -e DSDT.dat -d SSDT2.dat >/dev/null 2>&1 || true
    if [[ -f SSDT2.dsl ]] && grep -q "Method (ABCL" SSDT2.dsl; then
        TARGET_BASE="SSDT2"
    fi
fi

# Check DSDT (2019 iMac19,1)
if [[ -z "$TARGET_BASE" ]]; then
    iasl -d DSDT.dat >/dev/null 2>&1 || true
    if [[ -f DSDT.dsl ]] && grep -q "Method (ABCL" DSDT.dsl; then
        TARGET_BASE="DSDT"
    fi
fi

if [[ -z "$TARGET_BASE" ]]; then
    log_error "Could not find Method (ABCL) in SSDT6, SSDT2, or DSDT."
    exit 1
fi

log_info "Identified active backlight table: ${TARGET_BASE}.dsl"

# 3. Patching DefinitionBlock Revision & ABCL Package
log_step "3/5" "Patching table to expand brightness levels to 1..100"
TARGET_DSL="${TARGET_BASE}.dsl"

python3 - "$TARGET_DSL" <<'PY'
import re, sys

path = sys.argv[1]
with open(path, 'r') as f:
    s = f.read()

# 1. Bump OEM revision dynamically
def bump_rev(m):
    cur = int(m.group(2), 16)
    nxt = cur + 1
    print(f"  [Python] Bumped OEM Revision: 0x{cur:08X} -> 0x{nxt:08X}")
    return f"{m.group(1)}0x{nxt:08X})"

s, count = re.subn(r'(DefinitionBlock\s*\([^)]+,\s*)0x([0-9A-Fa-f]{1,8})\)', bump_rev, s, count=1)
if count != 1:
    sys.exit("Error: Failed to locate and bump DefinitionBlock revision.")

# 2. Locate Method (ABCL)
idx = s.find("Method (ABCL,")
if idx == -1:
    sys.exit("Error: Method (ABCL) not found in table.")

open_brace = s.find('{', idx)
depth, close_brace = 0, -1
for i in range(open_brace, len(s)):
    if s[i] == '{':
        depth += 1
    elif s[i] == '}':
        depth -= 1
        if depth == 0:
            close_brace = i
            break

if close_brace == -1:
    sys.exit("Error: Could not find closing brace for Method (ABCL).")

# 3. Inject full 1..100 ladder (0x66 = 102 items: 100 on AC, 50 on DC, levels 1..100)
levels = list(range(1, 101))
formatted = ['0x64', '0x32'] + [f'0x{lvl:02X}' for lvl in levels]
levels_str = ",\n                        ".join(formatted)

new_method_body = f"""{{
                Return (Package (0x66)
                {{
                        {levels_str}
                }})
            }}"""

s = s[:open_brace] + new_method_body + s[close_brace+1:]
print("  [Python] Successfully injected levels 1..100 (Package 0x66).")

with open(path, 'w') as f:
    f.write(s)
PY

# 4. AML Recompilation
log_step "4/5" "Compiling patched ASL back to AML"
iasl -p out "$TARGET_DSL" >iasl.log 2>&1 || {
    log_error "Compilation failed."
    grep -E "^Error" iasl.log >&2 || cat iasl.log >&2
    exit 1
}
log_info "Compiled out.aml ($(stat -c %s out.aml) bytes)."

# 5. CPIO Staging and Bootloader Update
log_step "5/5" "Creating early-initrd CPIO and updating bootloader"
mkdir -p kernel/firmware/acpi

# Match expected table names in initrd early ACPI override:
# - DSDT must be named dsdt.aml
# - SSDT tables must follow ssdtN.aml naming
table_name_lower=$(echo "$TARGET_BASE" | tr '[:upper:]' '[:lower:]')
cp out.aml "kernel/firmware/acpi/${table_name_lower}.aml"
log_info "Placed table as kernel/firmware/acpi/${table_name_lower}.aml"

find kernel | cpio -H newc --create > /boot/custom_acpi.cpio 2>/dev/null
chmod 600 /boot/custom_acpi.cpio
log_info "Generated /boot/custom_acpi.cpio ($(stat -c %s /boot/custom_acpi.cpio) bytes)."

if [[ -f /etc/default/grub ]]; then
    if ! grep -q 'GRUB_EARLY_INITRD_LINUX_CUSTOM="custom_acpi.cpio"' /etc/default/grub; then
        echo 'GRUB_EARLY_INITRD_LINUX_CUSTOM="custom_acpi.cpio"' >> /etc/default/grub
        log_info "Configured GRUB_EARLY_INITRD_LINUX_CUSTOM in /etc/default/grub."
    fi

    if command -v update-grub >/dev/null 2>&1; then
        update-grub >/dev/null
        log_info "Updated GRUB via update-grub."
    elif command -v grub-mkconfig >/dev/null 2>&1; then
        grub-mkconfig -o /boot/grub/grub.cfg >/dev/null 2>&1 || true
        log_info "Updated GRUB via grub-mkconfig."
    fi
else
    log_warn "/etc/default/grub not detected. Ensure your bootloader loads /boot/custom_acpi.cpio before the main initrd."
fi

printf "\n\033[1;32m[COMPLETE]\033[0m Backlight override installed.\n"
printf "Reboot the system, then verify with: cat /sys/class/backlight/*/max_brightness\n\n"
