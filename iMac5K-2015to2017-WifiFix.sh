#!/usr/bin/env bash
set -euo pipefail

PKG_NAME="brcmfmac-vht80"
PKG_VER="1.0"
SRC_DIR="/usr/src/${PKG_NAME}-${PKG_VER}"
CACHE_DIR="/var/cache/${PKG_NAME}-dkms"

ACTION="install"
CUSTOM_PATCH=""
DO_RELOAD=0

usage() {
    cat <<EOF
Usage: sudo $0 [OPTIONS]

Options:
  --patch FILE   Use an external patch file instead of the embedded patch
  --reload       Unload and reload brcmfmac immediately after install (avoid over Wi-Fi SSH)
  --uninstall    Remove the DKMS module, sources, and cache
  -h, --help     Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --patch)
            [[ $# -ge 2 ]] || { echo "Error: --patch requires a file path" >&2; exit 1; }
            CUSTOM_PATCH="$2"
            shift 2
            ;;
        --reload)
            DO_RELOAD=1
            shift
            ;;
        --uninstall)
            ACTION="uninstall"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "Run this script with sudo." >&2
    exit 1
fi

uninstall_module() {
    echo "Removing ${PKG_NAME}/${PKG_VER} from DKMS..."
    if dkms status -m "${PKG_NAME}" -v "${PKG_VER}" 2>/dev/null \vert{} grep -q "${PKG_NAME}"; then
        dkms remove "${PKG_NAME}/${PKG_VER}" --all || true
    fi
    rm -rf "${SRC_DIR}" "${CACHE_DIR}"
    depmod -a
    echo "Removed. Reboot (or reload brcmfmac) to return to the stock kernel module."
}

if [[ "$ACTION" == "uninstall" ]]; then
    uninstall_module
    exit 0
fi

KVER="$(uname -r)"

# Install build prerequisites only if missing
DEPS=()
for pkg in dkms build-essential git patch curl xz-utils; do
    dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed" || DEPS+=("$pkg")
done
if [[ ! -d "/lib/modules/${KVER}/build" ]]; then
    DEPS+=("linux-headers-${KVER}")
fi

if [[ ${#DEPS[@]} -gt 0 ]]; then
    echo "Installing dependencies: ${DEPS[*]}"
    apt-get update -qq
    apt-get install -y "${DEPS[@]}"
fi

if [[ ! -d "/lib/modules/${KVER}/build" ]]; then
    echo "Error: kernel headers not found at /lib/modules/${KVER}/build" >&2
    exit 1
fi

# Clean any prior registration of the same version
if dkms status -m "${PKG_NAME}" -v "${PKG_VER}" 2>/dev/null \vert{} grep -q "${PKG_NAME}"; then
    dkms remove "${PKG_NAME}/${PKG_VER}" --all || true
fi
rm -rf "${SRC_DIR}"
mkdir -p "${SRC_DIR}"

# Write normalized patch (strip local build paths to a/brcmfmac/... and b/brcmfmac/...)
if [[ -n "$CUSTOM_PATCH" ]]; then
    [[ -r "$CUSTOM_PATCH" ]] || { echo "Error: cannot read patch file: $CUSTOM_PATCH" >&2; exit 1; }
    sed -E \
        -e 's|^--- .*/brcmfmac/|--- a/brcmfmac/|' \
        -e 's|^\+\+\+ .*/brcmfmac/|+++ b/brcmfmac/|' \
        "$CUSTOM_PATCH" > "${SRC_DIR}/brcmfmac-vht80.patch"
else
    cat <<'EOF' > "${SRC_DIR}/brcmfmac-vht80.patch"
--- a/brcmfmac/cfg80211.c
+++ b/brcmfmac/cfg80211.c
@@ -8258,6 +8258,62 @@
 	return err;
 }
 
+static u64 brcmf_chan_mask(struct ieee80211_supported_band *band, u32 reject)
+{
+	u64 mask = 0;
+	int i;
+
+	if (!band)
+		return 0;
+
+	for (i = 0; i < band->n_channels && i < 64; i++) {
+		if (!(band->channels[i].flags & reject))
+			mask |= BIT_ULL(i);
+	}
+	return mask;
+}
+
+static void brcmf_probe_vht80_regrev(struct wiphy *wiphy,
+				     struct brcmf_if *ifp,
+				     struct brcmf_cfg80211_info *cfg,
+				     const struct brcmf_fil_country_le *base_cc)
+{
+	struct ieee80211_supported_band *b2 = wiphy->bands[NL80211_BAND_2GHZ];
+	struct ieee80211_supported_band *b5 = wiphy->bands[NL80211_BAND_5GHZ];
+	const u32 no80 = IEEE80211_CHAN_DISABLED | IEEE80211_CHAN_NO_80MHZ;
+	struct brcmf_fil_country_le probe;
+	u64 base_2g, base_5g;
+	bool dirty = false;
+	int rev;
+
+	if (!b5 || !b5->vht_cap.vht_supported || brcmf_chan_mask(b5, no80))
+		return;
+
+	base_2g = brcmf_chan_mask(b2, IEEE80211_CHAN_DISABLED);
+	base_5g = brcmf_chan_mask(b5, IEEE80211_CHAN_DISABLED);
+
+	for (rev = 1; rev <= 15; rev++) {
+		probe = *base_cc;
+		probe.rev = cpu_to_le32(rev);
+		if (brcmf_fil_iovar_data_set(ifp, "country", &probe,
+					     sizeof(probe)))
+			continue;
+
+		dirty = true;
+		brcmf_setup_wiphybands(cfg);
+		if (brcmf_chan_mask(b5, no80) &&
+		    !(brcmf_chan_mask(b2, IEEE80211_CHAN_DISABLED) & ~base_2g) &&
+		    !(base_5g & ~brcmf_chan_mask(b5, IEEE80211_CHAN_DISABLED)))
+			return;
+	}
+
+	if (dirty) {
+		probe = *base_cc;
+		brcmf_fil_iovar_data_set(ifp, "country", &probe, sizeof(probe));
+		brcmf_setup_wiphybands(cfg);
+	}
+}
+
 static void brcmf_cfg80211_reg_notifier(struct wiphy *wiphy,
 					struct regulatory_request *req)
 {
@@ -8299,6 +8355,9 @@
 		return;
 	}
 	brcmf_setup_wiphybands(cfg);
