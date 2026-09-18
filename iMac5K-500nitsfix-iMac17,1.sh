#!/usr/bin/env bash
#
# imac-backlight-fix.sh -- 500-nit backlight override for iMac 5K on Linux
#
# Generates a patched SSDT with brightness levels 4..100 and packages it
# directly into /boot/custom_acpi.cpio for early initrd loading.
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

# 2. Workspace Initialization
log_step "2/6" "Setting up isolated temporary workspace"
W=$(mktemp -d /tmp/acpi_fix.XXXXXX)
trap 'rm -rf "$W"; printf "\n\033[0;32m✓\033[0m Workspace cleaned up: %s\n" "$W"' EXIT INT TERM
log_info "Created scratch directory: $W"
cd "$W"

# 3. Extraction & Discovery
log_step "3/6" "Extracting ACPI tables and locating target SSDT"
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
log_info "Dumped ${#raw_tables[@]} ACPI binary tables to scratch directory."

# Locate the SSDT defining Method (ABCL)
T=$(grep -l 'Method (ABCL' SSDT*.dat 2>/dev/null || grep -l 'ABCL' SSDT*.dat | head -1 || true)
if [[ -z "$T" ]]; then
    log_error "Could not find an SSDT declaring 'Method (ABCL)'."
    echo "       Verify GPU configuration and ensure ACPI sysfs tables are exposed." >&2
    exit 1
fi

log_info "Identified target backlight control table: $T"

# 4. Decompilation & ASL AST Patching
log_step "4/6" "Decompiling ACPI Source Language (ASL) and patching levels"

iasl_peer_args=()
for ssdt in SSDT*.dat; do
    [[ "$ssdt" != "$T" ]] && iasl_peer_args+=("$ssdt")
done

printf "  Decompiling %s against DSDT and peer SSDTs...\n" "$T"
iasl -e DSDT.dat "${iasl_peer_args[@]}" -d "$T" >/dev/null 2>&1
log_info "Decompiled to ${T%.dat}.dsl successfully."

dsl_file="${T%.dat}.dsl"
rc=0
python3 - "$dsl_file" <<'PY' || rc=$?
import re, sys

path = sys.argv[1]
with open(path, 'r') as f:
    s = f.read()

# 1. Bump OEM revision in DefinitionBlock
def bump_rev(m):
    current_rev = int(m.group(2), 16)
    new_rev = current_rev + 1
    print(f"  [Python] DefinitionBlock revision: 0x{current_rev:08X} -> 0x{new_rev:08X}")
    return f'{m.group(1)}0x{new_rev:08X})'

s, n = re.subn(r'(DefinitionBlock\s*\([^)]+,\s*)0x([0-9A-Fa-f]{8})\)', bump_rev, s, count=1)
assert n == 1, "Failed to locate and increment DefinitionBlock revision"

# 2. Locate Method (ABCL)
target = "Method (ABCL, 0, NotSerialized)"
idx = s.find(target)
assert idx != -1, "Method (ABCL, 0, NotSerialized) declaration not found"

open_brace_idx = s.find('{', idx)
assert open_brace_idx != -1, "Opening brace for Method (ABCL) not found"

depth = 0
close_brace_idx = -1
for i in range(open_brace_idx, len(s)):
    if s[i] == '{':
        depth += 1
    elif s[i] == '}':
        depth -= 1
        if depth == 0:
            close_brace_idx = i
            break

assert close_brace_idx != -1, "Matching closing brace for Method (ABCL) not found"

# Check if table is already running levels 4..100
if "Package (0x63)" in s[open_brace_idx:close_brace_idx]:
    print("  [Python] Table already reflects 99 brightness entries (levels 4..100).")
    sys.exit(3)

# 3. Construct 4..100 table (97 levels + 2 defaults = 99 items = 0x63)
levels = list(range(4, 101))
formatted_levels = ['0x64', '0x32'] + [f'0x{lvl:02X}' for lvl in levels]
body = ",\n                        ".join(formatted_levels)

replacement = f"""Method (ABCL, 0, NotSerialized)
            {{
                If ((OSYS < 0x07DC))
                {{
                    BRTN [Zero] = DerefOf (BRTN [0x0F])
                    BRTN [One] = DerefOf (BRTN [0x0A])
                    Return (BRTN) /* \\_SB_.PCI0.PEG0.GFX0.BRTN */
                }}
                Else
                {{
                    Return (Package (0x63)
                    {{
                        {body}
                    }})
                }}
            }}"""

s = s[:idx] + replacement + s[close_brace_idx + 1:]
print(f"  [Python] Replaced ABCL return package: injected levels 4..100 (99 values).")

with open(path, 'w') as f:
    f.write(s)
PY

if ((rc == 3)); then
    log_warn "Host table is already running modified brightness levels. Using existing table."
    cp "$T" out.aml
elif ((rc != 0)); then
    log_error "Python AST replacement failed with exit code $rc."
    exit "$rc"
else
    log_info "Source patched. Recompiling modified ASL code with iasl..."
    iasl -p out "$dsl_file" >iasl.log 2>&1 || {
        log_error "AML compilation failed."
        grep -E "^Error" iasl.log >&2 || cat iasl.log >&2
        exit 1
    }
    log_info "Compiled out.aml ($(stat -c %s out.aml) bytes)."
fi

# 5. CPIO Packaging
log_step "5/6" "Packaging early-initrd CPIO archive"
mkdir -p kernel/firmware/acpi
cp out.aml kernel/firmware/acpi/imac-bcl100.aml

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
