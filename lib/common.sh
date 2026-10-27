# shellcheck shell=bash disable=SC2034
# Shared helpers for the Nothing Phone (1) Fedora kit.

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KIT_DIR

# shellcheck source=../config.env
. "$KIT_DIR/config.env"

# The kernel's release string (uname -r). RPM allows only one "-" in it (it
# also becomes the kernel-uname-r version), so when the kernel version
# already has one (7.3.0-rc4) the kit's suffix is joined with "." instead,
# as in Fedora's own rc kernels: 7.3.0-rc4.1.spacewar.aarch64.
case "$KERNEL_VERSION" in
    *-*) KERNEL_LOCALVERSION=".${KERNEL_PKG_RELEASE}.spacewar.aarch64" ;;
    *)   KERNEL_LOCALVERSION="-${KERNEL_PKG_RELEASE}.spacewar.aarch64" ;;
esac
KERNEL_RELEASE_STRING="${KERNEL_VERSION}${KERNEL_LOCALVERSION}"
# RPM versions can't contain "-"; "~" sorts a release candidate before the
# final release (7.3.0~rc4 < 7.3.0), as in Fedora's own kernel packages.
KERNEL_RPM_VERSION="${KERNEL_VERSION//-/\~}"
RPM_DIR="$OUT_DIR/rpms"
WORK_DIR="$OUT_DIR/work"
SIGN_DIR="$OUT_DIR/signing"
SIGN_KEY_NAME="Nothing Phone 1 local builds"
SIGN_PUBKEY="$SIGN_DIR/RPM-GPG-KEY-nothing-spacewar-local"
SPACEWAR_DTB="qcom/sm7325-nothing-spacewar.dtb"

msg()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
msg2() { printf '\033[1;34m  ->\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

require_cmds() {
    local missing=() c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || missing+=("$c")
    done
    [ ${#missing[@]} -eq 0 ] || die "missing commands: ${missing[*]} (run: ./build.sh deps)"
}

require_root() {
    [ "$(id -u)" -eq 0 ] || die "this step needs root, run it with sudo"
}

require_fedora_host() {
    [ -r /etc/os-release ] || die "cannot read /etc/os-release"
    # shellcheck disable=SC1091
    . /etc/os-release
    [ "${ID:-}" = "fedora" ] || die "run this on Fedora; found ${ID:-unknown}"
}

require_qemu_aarch64() {
    if [ ! -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ]; then
        sudo systemctl restart systemd-binfmt 2>/dev/null || true
    fi
    [ -e /proc/sys/fs/binfmt_misc/qemu-aarch64 ] \
        || die "qemu-aarch64 binfmt handler not registered (install qemu-user-static-aarch64)"
}

# fetch_verified URL DEST ALGO SUM   (ALGO: sha256 or sha512)
fetch_verified() {
    local url="$1" dest="$2" algo="$3" sum="$4"
    if [ ! -f "$dest" ]; then
        msg2 "downloading $(basename "$dest")"
        curl -fL --retry 3 -o "$dest.part" "$url"
        mv "$dest.part" "$dest"
    fi
    echo "$sum  $dest" | "${algo}sum" -c --quiet - || die "checksum mismatch for $dest"
}

# git_fetch_commit REPO_URL DIR COMMIT: shallow checkout of one commit.
git_fetch_commit() {
    local repo="$1" dir="$2" commit="$3"
    if [ ! -d "$dir/.git" ]; then
        git init -q "$dir"
        git -C "$dir" remote add origin "$repo"
    fi
    if ! git -C "$dir" cat-file -e "$commit^{commit}" 2>/dev/null; then
        git -C "$dir" fetch -q --depth 1 origin "$commit"
    fi
    git -C "$dir" checkout -q --force --detach "$commit"
    git -C "$dir" clean -q -fdx
}

# Create a passwordless local signing key on first use, so dnf can install
# the kit's packages with GPG checking left on.
ensure_signing_key() {
    export GNUPGHOME="$SIGN_DIR/gnupg"
    if [ ! -d "$GNUPGHOME" ]; then
        msg2 "creating local RPM signing key"
        mkdir -p "$GNUPGHOME"
        chmod 700 "$GNUPGHOME"
        gpg --batch --passphrase '' --quick-gen-key \
            "$SIGN_KEY_NAME <spacewar@localhost>" rsa4096 sign never
    fi
    [ -f "$SIGN_PUBKEY" ] || gpg --armor --export "$SIGN_KEY_NAME" > "$SIGN_PUBKEY"
}

sign_rpms() {
    ensure_signing_key
    rpmsign --define "_gpg_name $SIGN_KEY_NAME" --define "_gpg_path $GNUPGHOME" \
        --addsign "$@" >/dev/null
}
