#!/usr/bin/env bash
##
##  Script for compiling bootstrap packages from source.
##

set -e

# Import properties to get TERMUX_APP_PACKAGE
export TERMUX_SCRIPTDIR=$(realpath "$(dirname "$(realpath "$0")")/../")

# Set Custom SDK/NDK Paths if they exist locally
if [ -z "${ANDROID_HOME:-}" ] && [ -d "/mnt/d/newcompany/xpmall/termux/toolchain/android-sdk" ]; then
    export ANDROID_HOME="/mnt/d/newcompany/xpmall/termux/toolchain/android-sdk"
fi
if [ -z "${NDK:-}" ] && [ -d "/mnt/d/newcompany/xpmall/termux/toolchain/android-sdk/ndk/23.2.8568313" ]; then
    export NDK="/mnt/d/newcompany/xpmall/termux/toolchain/android-sdk/ndk/23.2.8568313"
fi
export TERMUX_NDK_VERSION_NUM="${TERMUX_NDK_VERSION_NUM:-23}"
export TERMUX_NDK_REVISION="${TERMUX_NDK_REVISION:-c}"
export TERMUX_ANDROID_BUILD_TOOLS_VERSION="${TERMUX_ANDROID_BUILD_TOOLS_VERSION:-34.0.0}"

. $(dirname "$(realpath "$0")")/properties.sh

# List of packages to build (matching those in generate-bootstraps.sh)
# Dependencies are listed first to ensure proper build order
BOOTSTRAP_PACKAGES=(
    "postgresql"
    "pgvector"
)

# Function to build a package
build_package() {
    local pkg_name=$1
    if [ -f "packages/$pkg_name/build.sh" ]; then
        echo "========================================"
        echo "Building package: $pkg_name"
        echo "========================================"
        ./build-package.sh -a aarch64 "$pkg_name"
    else
        echo "========================================"
        echo "Skipping build for: $pkg_name (subpackage or dependency)"
        echo "========================================"
    fi
}

# 1. Update project-wide paths if not already done (Safety measure)
# Though we did this globally, we ensure it here implicitly by relying on properties.sh
if [ "$TERMUX_APP_PACKAGE" != "com.xpmall" ]; then
    echo "Error: TERMUX_APP_PACKAGE is not set to com.xpmall in properties.sh"
    exit 1
fi

echo "Starting build process for com.xpmall..."
echo "Target Architecture: aarch64"
echo "Package List: ${BOOTSTRAP_PACKAGES[*]}"

# 2. Build loop
for pkg in "${BOOTSTRAP_PACKAGES[@]}"; do
    build_package "$pkg"
done

echo "========================================"
echo "All packages built successfully!"
echo "========================================"

# 3. Create Bootstrap Archive from Local Debs
create_local_bootstrap_archive() {
    local arch="aarch64"
    local output_dir="bootstrap-rootfs-$arch"
    local deploy_dir="deploy-output"

    echo "Creating bootstrap archive from local builds..."

    rm -rf "$output_dir" "$deploy_dir"
    mkdir -p "$output_dir" "$deploy_dir"

    # Define the termux prefix based on the customized package
    local termux_prefix="/data/data/${TERMUX_APP_PACKAGE}/files/usr"

    for pkg in "${BOOTSTRAP_PACKAGES[@]}"; do
        # Find the deb file. build-package.sh usually outputs to 'debs' or 'output'
        # We search in 'debs' first as that's standard for build-package.sh
set -x
        local deb_file=$(find output \( -name "${pkg}_*_${arch}.deb" -o -name "${pkg}_*_all.deb" \) 2>/dev/null | head -n 1)
set +x

        if [ -z "$deb_file" ]; then
            echo "Warning: Could not find built deb for $pkg. Skipping..."
            continue
        fi

        echo "Extracting $deb_file..."
        ar x "$deb_file" --output "$deploy_dir"

        # Extract data.tar.*
        if [ -f "$deploy_dir/data.tar.xz" ]; then
            tar xf "$deploy_dir/data.tar.xz" -C "$output_dir"
        elif [ -f "$deploy_dir/data.tar.gz" ]; then
            tar xf "$deploy_dir/data.tar.gz" -C "$output_dir"
        fi

        # Determine package name and maintainer scripts path
        local dpkg_info_dir="${output_dir}${termux_prefix}/var/lib/dpkg/info"
        mkdir -p "$dpkg_info_dir"

        # Clean up temp extraction
        rm -f "$deploy_dir"/*
    done

    # Final Patching: Ensure com.xpmall is used everywhere
    if [ "${TERMUX_APP_PACKAGE}" != "com.termux" ]; then
        echo "[*] Ensuring paths point to ${TERMUX_APP_PACKAGE}..."
        grep -rl "com.termux" "$output_dir" | xargs -r perl -pi -e "s|com\.termux|${TERMUX_APP_PACKAGE}|g"
    fi

    # Create SYMLINKS.txt and remove symlinks
    echo "Generating SYMLINKS.txt..."
    (cd "${output_dir}/${termux_prefix}"
        while read -r -d '' link; do
            echo "$(readlink "$link")←${link}" | sed "s|com.termux|${TERMUX_APP_PACKAGE}|g" >> SYMLINKS.txt
            rm -f "$link"
        done < <(find . -type l -print0)

        # Create Zip
        echo "Zipping bootstrap archive..."
        zip -r9 "$TERMUX_SCRIPTDIR/bootstrap-${arch}-custom.zip" ./*
    )

    echo "Bootstrap created: bootstrap-${arch}-custom.zip"
}

# Run the packaging step
create_local_bootstrap_archive
