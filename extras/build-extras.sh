#!/usr/bin/env bash
# Build the helper tools Fedora doesn't package (hexagonrpc, qbootctl,
# dummystreamhack) as aarch64 RPMs. mock builds them in a clean Fedora
# aarch64 chroot under qemu, so the result links against the same libraries
# as the phone's system. Needs membership in the "mock" group.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"

require_cmds git curl mock rpmsign gpg sha256sum tar
require_qemu_aarch64

MOCK_CFG="fedora-${FEDORA_RELEASE}-aarch64"
SRC="$WORK_DIR/extras-src"
RES="$WORK_DIR/extras-result"
mkdir -p "$SRC" "$RES" "$RPM_DIR"

# mock_build NAME DEFINES...: build extras/NAME.spec from $SRC/NAME.
mock_build() {
    local name="$1" sources="$SRC/$1" result="$RES/$1"
    shift
    local defs=() d
    for d in "$@"; do defs+=(--define "$d"); done
    rm -rf "$result"
    mkdir -p "$result"
    cp "$KIT_DIR"/extras/*.sysusers "$KIT_DIR"/extras/*.rules "$sources/"
    mock -q -r "$MOCK_CFG" --forcearch aarch64 --buildsrpm \
        --spec "$KIT_DIR/extras/$name.spec" --sources "$sources" \
        "${defs[@]}" --resultdir "$result/srpm"
    mock -q -r "$MOCK_CFG" --forcearch aarch64 --rebuild "$result"/srpm/*.src.rpm \
        "${defs[@]}" --resultdir "$result/rpm"
    rm -f "$RPM_DIR/$name"-[0-9]*.rpm
    find "$result/rpm" -name "$name-*.aarch64.rpm" ! -name '*-debug*' -exec cp -t "$RPM_DIR" {} +
    sign_rpms "$RPM_DIR/$name"-[0-9]*.aarch64.rpm
}

# from_git NAME REPO COMMIT VERSION PREFIX: tarball from a pinned git commit.
from_git() {
    local name="$1" repo="$2" commit="$3" version="$4" pfx="$5"
    local checkout="$WORK_DIR/$name-git"
    msg "Building $name $version (${commit:0:12})"
    git_fetch_commit "$repo" "$checkout" "$commit"
    rm -rf "${SRC:?}/$name"
    mkdir -p "$SRC/$name"
    git -C "$checkout" archive --format=tar.gz --prefix="$name-$version/" \
        -o "$SRC/$name/$name-$version.tar.gz" HEAD
    mock_build "$name" "${pfx}version $version" "${pfx}commit $commit"
}

from_git hexagonrpc "$HEXAGONRPC_REPO" "$HEXAGONRPC_COMMIT" "$HEXAGONRPC_VERSION" hex
from_git qbootctl "$QBOOTCTL_REPO" "$QBOOTCTL_COMMIT" "$QBOOTCTL_VERSION" qb

# dummystreamhack: a Codeberg archive, checked against the pinned SHA-256.
msg "Building dummystreamhack $DUMMYSTREAMHACK_VERSION (${DUMMYSTREAMHACK_COMMIT:0:12})"
rm -rf "${SRC:?}/dummystreamhack"
mkdir -p "$SRC/dummystreamhack"
fetch_verified "$DUMMYSTREAMHACK_URL" \
    "$SRC/dummystreamhack/dummystreamhack-$DUMMYSTREAMHACK_COMMIT.tar.gz" \
    sha256 "$DUMMYSTREAMHACK_SHA256"
tar -tzf "$SRC/dummystreamhack/dummystreamhack-$DUMMYSTREAMHACK_COMMIT.tar.gz" \
    | grep -q '^dummystreamhack/meson.build$' \
    || die "unexpected layout in the dummystreamhack archive"
mock_build dummystreamhack "dshversion $DUMMYSTREAMHACK_VERSION" "dshcommit $DUMMYSTREAMHACK_COMMIT"

msg "Done: $(ls "$RPM_DIR"/hexagonrpc-[0-9]*.rpm "$RPM_DIR"/qbootctl-[0-9]*.rpm "$RPM_DIR"/dummystreamhack-[0-9]*.rpm | tr '\n' ' ')"
