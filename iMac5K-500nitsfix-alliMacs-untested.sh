#!/usr/bin/env bash
#
# imac-backlight-fix.sh -- Universal 500-nit backlight override for 5K iMacs
# Supports: iMac17,1 (2015), iMac18,1/18,3 (2017), and iMac19,1 (2019)
#
set -euo pipefail

log_step() {
    printf "\n\033[1;34m[STEP %s]\033[0m \033[1m%s\033[0m\n" "$1" "$2"
}

log_info() {
    printf "  \033[0;32m✓\033[0m %s\n" "$1"
}

log_warn() {
    printf "  \033[0;33m!\033[0m %s\n" "$1"
}

log_error() {
    printf "  \033[0;31m✗\033[0m %s\n" "$1" >&2
}

# 1. Environment & Dependency Validation
log_step "1/6" "Checking permissions and host dependencies"

if [[ $EUID -ne 0 ]]; then
    log_error "This script must be executed as root (e.g. sudo $0)."
    exit 1
fi
log_info "Running with superuser privileges (UID 0)."

for cmd in iasl python3 cpio update-grub; do
    if command -v "$cmd" >/dev/null 2>&1; then
        log_info "Found required tool: $(which $cmd)"
    else
        log_error "Missing dependency: $cmd"
        echo "       Install missing tools via: sudo apt install -y acpica-tools python3 cpio" >&2
        exit 1
    fi
done

PRODUCT_NAME=$(cat /sys/class/dmi/id/product_name 2>/dev/null | tr -d ' ' || echo "Unknown")
log_info "Detected Hardware Model: ${PRODUCT_NAME}"

# 2. Workspace Initialization
log_step "2/6" "Setting up isolated temporary workspace"
W=$(mktemp -d /tmp/acpi_fix.XXXXXX)
trap 'rm -rf "$W"; printf "\n\033[0;32m✓\033[0m Workspace cleaned up: %s\n" "$W"' EXIT INT TERM
log_info "Created scratch directory: $W"
cd "$W"

# 3. Extraction & Strategy Routing
log_step "3/6" "Extracting ACPI tables and determining override strategy"
shopt -s nullglob
raw_tables=(/sys/firmware/acpi/tables/DSDT /sys/firmware/acpi/tables/SSDT*)
shopt -u nullglob

if [[ ${#raw_tables[@]} -eq 0 ]]; then
    log_error "No ACPI tables found under /sys/firmware/acpi/tables/."
    exit 1
fi

for t in "${raw_tables[@]}"; do
    cat "$t" > "$(basename "$t").dat"
done
log_info "Dumped ${#raw_tables[@]} ACPI binary tables."

# Check if target is an SSDT or lives in DSDT (iMac19,1 pattern)
T=$(grep -l 'Method (ABCL' SSDT*.dat 2>/dev/null || grep -l 'ABCL' SSDT*.dat | head -1 || true)

if [[ -z "$T" ]] && grep -q 'Method (ABCL' DSDT.dat 2>/dev/null; then
    MODE="COMPANION_SSDT"
    log_info "ABCL resides in DSDT (2019+ structure). Using standalone companion SSDT override."
elif [[ -n "$T" ]]; then
    MODE="PATCH_SSDT"
    log_info "Identified target vendor backlight SSDT: $T"
else
    log_error "Could not locate 'Method (ABCL)' in SSDTs or DSDT."
    exit 1
fi

# 4. Generate Patched AML Table
log_step "4/6" "Generating 1..101 brightness levels (Package 0x67)"

if [[ "$MODE" == "COMPANION_SSDT" ]]; then
    # Generate companion SSDT that defines _BCL directly on the PEG0.GFX0 scope
    cat <<'EOF' > companion.dsl
DefinitionBlock ("out.aml", "SSDT", 2, "APPLE ", "BacklOvr", 0x00002000)
{
    External (_SB_.PCI0.PEG0.GFX0, DeviceObj)
    External (_SB_.PCI0.PEG0.GFX0.LCD, DeviceObj)
    External (_SB_.PCI0.PEG0.GFX0.ABCM, MethodObj)
    External (BRTL, FieldUnitObj)

    Scope (\_SB.PCI0.PEG0.GFX0.LCD)
    {
        Method (_BCL, 0, NotSerialized)
        {
            Return (Package (0x67)
            {
                0x64, 
                0x32, 
                0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 
                0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13, 0x14, 
                0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 
                0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28, 
                0x29, 0x2A, 0x2B, 0x2C, 0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x32, 
                0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x3A, 0x3B, 0x3C, 
                0x3D, 0x3E, 0x3F, 0x40, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 
                0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x50, 
                0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 
                0x5B, 0x5C, 0x5D, 0x5E, 0x5F, 0x60, 0x61, 0x62, 0x63, 0x64,
                0x65
            })
        }
    }
}
EOF
    iasl -p out companion.dsl >iasl.log 2>&1 || {
        log_error "AML compilation failed for companion SSDT."
        cat iasl.log >&2
        exit 1
    }
    log_info "Compiled companion out.aml ($(stat -c %s out.aml) bytes)."

else
    # Dynamic patch of host vendor SSDT
    iasl_peer_args=()
    for ssdt in SSDT*.dat; do
        [[ "$ssdt" != "$T" ]] && iasl_peer_args+=("$ssdt")
    done

    iasl -e DSDT.dat "${iasl_peer_args[@]}" -d "$T" >/dev/null 2>&1
    log_info "Decompiled $T to ${T%.dat}.dsl successfully."

    dsl_file="${T%.dat}.dsl"
    rc=0
    python3 - "$dsl_file" <<'PY' || rc=$?
import re, sys

path = sys.argv[1]
with open(path, 'r') as f:
    s = f.read()

# 1. Bump OEM revision dynamically
def bump_rev(m):
    current_rev = int(m.group(2), 16)
    new_rev = current_rev + 1
    print(f"  [Python] DefinitionBlock revision: 0x{current_rev:08X} -> 0x{new_rev:08X}")
    return f'{m.group(1)}0x{new_rev:08X})'

s, n = re.subn(r'(DefinitionBlock\s*\([^)]+,\s*)0x([0-9A-Fa-f]{8})\)', bump_rev, s, count=1)
assert n == 1, "Failed to locate and increment DefinitionBlock revision"

# 2. Locate Method (ABCL)
idx = s.find("Method (ABCL,")
assert idx != -1, "Method (ABCL) declaration not found"

open_brace = s.find('{', idx)
assert open_brace != -1, "Opening brace for Method (ABCL) not found"

depth, close_brace = 0, -1
for i in range(open_brace, len(s)):
    if s[i] == '{':
        depth += 1
    elif s[i] == '}':
        depth -= 1
        if depth == 0:
            close_brace = i
            break

assert close_brace != -1, "Matching closing brace for Method (ABCL) not found"
method_body = s[open_brace:close_brace+1]

# Check if already patched (103 entries = 0x67)
if "Package (0x67)" in method_body:
    print("  [Python] Table already reflects 103 brightness entries (levels 1..101).")
    sys.exit(3)

# 3. Locate and replace only the Return (Package (...)) inside Method (ABCL)
pkg_match = re.search(r'(Return\s*\(\s*Package\s*\()\s*0x[0-9A-Fa-f]+(\s*\)\s*\{)(.*?)(\}\s*\))', method_body, re.DOTALL)
assert pkg_match, "Could not locate Return (Package (...)) inside Method (ABCL)"

levels = list(range(1, 102))
formatted = ['0x64', '0x32'] + [f'0x{lvl:02X}' for lvl in levels]
new_levels_str = ",\n                        ".join(formatted)

new_pkg = (
    pkg_match.group(1) + "0x67" + pkg_match.group(2) +
    "\n                        " + new_levels_str + "\n                    " +
    pkg_match.group(4)
)

patched_method = method_body[:pkg_match.start()] + new_pkg + method_body[pkg_match.end():]
s = s[:open_brace] + patched_method + s[close_brace+1:]
print("  [Python] Replaced ABCL return package: injected levels 1..101 (103 values).")

with open(path, 'w') as f:
    f.write(s)
PY

    if ((rc == 3)); then
        log_warn "Host table is already running modified brightness levels (1..101). Using existing table."
        cp "$T" out.aml
    elif ((rc != 0)); then
        log_error "Python AST replacement failed with exit code $rc."
        exit "$rc"
    else
        log_info "Source patched. Recompiling with iasl..."
        iasl -p out "$dsl_file" >iasl.log 2>&1 || {
            log_error "AML compilation failed."
            cat iasl.log >&2
            exit 1
        }
        log_info "Compiled out.aml ($(stat -c %s out.aml) bytes)."
    fi
fi

# 5. CPIO Packaging
log_step "5/6" "Packaging early-initrd CPIO archive"
mkdir -p kernel/firmware/acpi
cp out.aml kernel/firmware/acpi/imac-bcl101.aml

find kernel | cpio -H newc --create > /boot/custom_acpi.cpio 2>/dev/null
chmod 600 /boot/custom_acpi.cpio
log_info "Generated /boot/custom_acpi.cpio ($(stat -c %s /boot/custom_acpi.cpio) bytes)."
log_info "Archive contents verified:"
cpio -it < /boot/custom_acpi.cpio 2>/dev/null | sed 's/^/       /'

# 6. Bootloader Configuration
log_step "6/6" "Configuring GRUB early initrd parameters"
GRUB_FILE="/etc/default/grub"

if [[ -f "$GRUB_FILE" ]]; then
    if grep -q 'GRUB_EARLY_INITRD_LINUX_CUSTOM="custom_acpi.cpio"' "$GRUB_FILE"; then
        log_info "GRUB_EARLY_INITRD_LINUX_CUSTOM already present in $GRUB_FILE."
    else
        echo 'GRUB_EARLY_INITRD_LINUX_CUSTOM="custom_acpi.cpio"' >> "$GRUB_FILE"
        log_info "Added GRUB_EARLY_INITRD_LINUX_CUSTOM=\"custom_acpi.cpio\" to $GRUB_FILE."
    fi

    printf "  Regenerating GRUB configuration (/boot/grub/grub.cfg)...\n"
    update-grub >/dev/null
    log_info "GRUB bootloader updated successfully."
else
    log_warn "$GRUB_FILE not found. Ensure your bootloader passes /boot/custom_acpi.cpio ahead of initrd."
fi

printf "\n\033[1;32m[COMPLETE]\033[0m 500-nit backlight override is installed.\n"
printf "Reboot the system to let the kernel load the upgraded ACPI table.\n\n"
