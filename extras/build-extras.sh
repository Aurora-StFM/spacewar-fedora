#!/usr/bin/env bash
# Build the helper tools Fedora doesn't package (hexagonrpc, qbootctl) as
# aarch64 RPMs. mock builds them in a clean Fedora aarch64 chroot under qemu,
# so the result links against the same libraries as the phone's system.
# Needs membership in the "mock" group.
set -euo pipefail
. "$(dirname "$0")/../lib/common.sh"

require_cmds git mock rpmsign gpg
require_qemu_aarch64

MOCK_CFG="fedora-${FEDORA_RELEASE}-aarch64"
SRC="$WORK_DIR/extras-src"
RES="$WORK_DIR/extras-result"
mkdir -p "$SRC" "$RES" "$RPM_DIR"

# build_one NAME REPO COMMIT VERSION DEFINE_PREFIX
build_one() {
    local name="$1" repo="$2" commit="$3" version="$4" pfx="$5"
    local checkout="$WORK_DIR/$name-git" sources="$SRC/$name" result="$RES/$name"
    msg "Building $name $version (${commit:0:12})"
    git_fetch_commit "$repo" "$checkout" "$commit"
    rm -rf "$sources" "$result"
    mkdir -p "$sources" "$result"
    git -C "$checkout" archive --format=tar.gz --prefix="$name-$version/" \
        -o "$sources/$name-$version.tar.gz" HEAD
    cp "$KIT_DIR"/extras/*.sysusers "$KIT_DIR"/extras/*.rules "$sources/"

    mock -q -r "$MOCK_CFG" --forcearch aarch64 --buildsrpm \
        --spec "$KIT_DIR/extras/$name.spec" --sources "$sources" \
        --define "${pfx}version $version" --define "${pfx}commit $commit" \
        --resultdir "$result/srpm"
    mock -q -r "$MOCK_CFG" --forcearch aarch64 --rebuild "$result"/srpm/*.src.rpm \
        --define "${pfx}version $version" --define "${pfx}commit $commit" \
        --resultdir "$result/rpm"
    rm -f "$RPM_DIR/$name"-[0-9]*.rpm
    find "$result/rpm" -name "$name-*.aarch64.rpm" ! -name '*-debug*' -exec cp -t "$RPM_DIR" {} +
    sign_rpms "$RPM_DIR/$name"-[0-9]*.aarch64.rpm
}

build_one hexagonrpc "$HEXAGONRPC_REPO" "$HEXAGONRPC_COMMIT" "$HEXAGONRPC_VERSION" hex
build_one qbootctl "$QBOOTCTL_REPO" "$QBOOTCTL_COMMIT" "$QBOOTCTL_VERSION" qb
msg "Done: $(ls "$RPM_DIR"/hexagonrpc-[0-9]*.rpm "$RPM_DIR"/qbootctl-[0-9]*.rpm | tr '\n' ' ')"
