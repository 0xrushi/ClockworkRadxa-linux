#!/bin/bash

# deploy_kernel_headers.sh
#
# Installs kernel headers on the uConsole so out-of-tree kernel modules
# (e.g. USB WiFi drivers like rtl8831, rtl8812au) can be compiled directly
# on the device.
#
# After modules_install, the /lib/modules/<version>/build symlink points
# back to the build machine's source tree, which doesn't exist on the
# device. This script copies the minimal set of files needed to compile
# kernel modules on the device itself.
#
# Run this from the kernel source root after a successful build.
#
# Usage: ./deploy-scripts/deploy_kernel_headers.sh

set -e

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REMOTE_USER="clockwork"
REMOTE_HOST="192.168.1.174"
KERNEL_SRC="$(pwd)"

# ---------------------------------------------------------------------------
# Detect kernel version from the build
# ---------------------------------------------------------------------------
KRELEASE=$(make -s ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- kernelrelease 2>/dev/null)
if [[ -z "$KRELEASE" ]]; then
    echo "ERROR: Could not determine kernel version. Are you in the kernel source root?"
    exit 1
fi

REMOTE_HEADERS_DIR="/lib/modules/${KRELEASE}/build"
LOCAL_STAGING="/tmp/kernel-headers-staging"

echo "--------------------------------------------------------"
echo "Kernel Headers Deploy  ->  $REMOTE_USER@$REMOTE_HOST"
echo "Kernel version: $KRELEASE"
echo "Remote target:  $REMOTE_HEADERS_DIR"
echo "--------------------------------------------------------"

# ---------------------------------------------------------------------------
# Stage the minimum set of files needed to build out-of-tree modules
# ---------------------------------------------------------------------------
echo "[1/4] Staging kernel headers..."

rm -rf "$LOCAL_STAGING"
mkdir -p "$LOCAL_STAGING"

# Kbuild system files
cp "$KERNEL_SRC/Makefile" "$LOCAL_STAGING/"
cp "$KERNEL_SRC/Module.symvers" "$LOCAL_STAGING/"
cp "$KERNEL_SRC/.config" "$LOCAL_STAGING/"

# Scripts directory (needed by Kbuild)
rsync -a --include='*/' \
    --include='*.sh' --include='Makefile*' --include='Kbuild*' \
    --include='*.pl' --include='*.awk' --include='*.py' \
    --include='recordmcount' --include='sorttable' \
    --include='sign-file' --include='extract-cert' \
    --include='module.lds' --include='modules-check.sh' \
    --include='check-local-export' \
    --include='gcc-goto.sh' --include='gcc-x86_*' \
    --include='basic/**' --include='genksyms/**' --include='mod/**' \
    --include='kconfig/**' \
    --exclude='*' \
    "$KERNEL_SRC/scripts/" "$LOCAL_STAGING/scripts/"

# Also copy compiled host tools from scripts/
find "$KERNEL_SRC/scripts" -maxdepth 3 -type f -executable -print0 2>/dev/null | \
    while IFS= read -r -d '' f; do
        rel="${f#$KERNEL_SRC/}"
        mkdir -p "$LOCAL_STAGING/$(dirname "$rel")"
        cp "$f" "$LOCAL_STAGING/$rel"
    done

# Arch-specific headers and Makefiles
mkdir -p "$LOCAL_STAGING/arch/arm64"
cp -a "$KERNEL_SRC/arch/arm64/Makefile" "$LOCAL_STAGING/arch/arm64/"
cp -a "$KERNEL_SRC/arch/arm64/Makefile.postlink" "$LOCAL_STAGING/arch/arm64/" 2>/dev/null || true
rsync -a "$KERNEL_SRC/arch/arm64/include/" "$LOCAL_STAGING/arch/arm64/include/"
if [ -d "$KERNEL_SRC/arch/arm64/kernel/vdso" ]; then
    mkdir -p "$LOCAL_STAGING/arch/arm64/kernel"
    cp -a "$KERNEL_SRC/arch/arm64/kernel/vdso" "$LOCAL_STAGING/arch/arm64/kernel/" 2>/dev/null || true
fi

# Include directories
rsync -a "$KERNEL_SRC/include/" "$LOCAL_STAGING/include/"

# Kbuild files from the source tree (all Kbuild and Makefile files)
find "$KERNEL_SRC" -maxdepth 1 -name 'Kbuild*' -exec cp {} "$LOCAL_STAGING/" \;

# Generated files needed for module builds
if [ -d "$KERNEL_SRC/tools/objtool" ]; then
    mkdir -p "$LOCAL_STAGING/tools/objtool"
    cp "$KERNEL_SRC/tools/objtool/objtool" "$LOCAL_STAGING/tools/objtool/" 2>/dev/null || true
fi

echo "   Staged $(du -sh "$LOCAL_STAGING" | cut -f1) of headers"

# ---------------------------------------------------------------------------
# Transfer to device
# ---------------------------------------------------------------------------
read -s -p "Enter password for $REMOTE_USER@$REMOTE_HOST: " SSHPASS
export SSHPASS
echo ""

echo "[2/4] Removing old build/source symlinks on device..."
sshpass -e ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "
echo '$SSHPASS' | sudo -S -p '' rm -rf /lib/modules/${KRELEASE}/build /lib/modules/${KRELEASE}/source
"

echo "[3/4] Copying headers to device (this may take a minute)..."
sshpass -e rsync -aq \
    "$LOCAL_STAGING/" "$REMOTE_USER@$REMOTE_HOST:~/kernel-headers-tmp/"

echo "[4/4] Installing headers to $REMOTE_HEADERS_DIR..."
sshpass -e ssh -o StrictHostKeyChecking=no "$REMOTE_USER@$REMOTE_HOST" "
echo '$SSHPASS' | sudo -S -p '' mkdir -p $REMOTE_HEADERS_DIR
echo '$SSHPASS' | sudo -S -p '' cp -a ~/kernel-headers-tmp/* $REMOTE_HEADERS_DIR/
echo '$SSHPASS' | sudo -S -p '' ln -sf build /lib/modules/${KRELEASE}/source
rm -rf ~/kernel-headers-tmp
echo '-> Headers installed to $REMOTE_HEADERS_DIR'
"

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
rm -rf "$LOCAL_STAGING"
unset SSHPASS

echo "--------------------------------------------------------"
echo "Kernel headers installed for $KRELEASE"
echo ""
echo "On the device, out-of-tree modules can now be built with:"
echo "  make -C /lib/modules/$KRELEASE/build M=\$(pwd) modules"
echo "--------------------------------------------------------"
