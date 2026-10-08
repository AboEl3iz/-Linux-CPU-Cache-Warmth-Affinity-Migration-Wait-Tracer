#!/usr/bin/env bash
#
# build_packages.sh - Packaging script for Linux CPU Cache-Warmth & Affinity Wait Tracer
#

set -e

RAW_VERSION="${1:-1.0.0}"
VERSION="${RAW_VERSION#v}"

# Debian and RPM package specs require version to start with a digit
if [[ ! "${VERSION}" =~ ^[0-9] ]]; then
    VERSION="1.0.0-${VERSION}"
fi

RPM_VERSION="${VERSION//-/.}"

ARCH="${2:-all}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${PROJECT_ROOT}/dist"
BUILD_DIR="${PROJECT_ROOT}/build"

echo "=================================================================="
echo " Building Packages for cpu-cache-affinity-wait v${VERSION}"
echo "=================================================================="

# Ensure output directories exist
rm -rf "${BUILD_DIR}" "${DIST_DIR}"
mkdir -p "${DIST_DIR}"

# ------------------------------------------------------------------
# 1. Build Tarball (.tar.gz)
# ------------------------------------------------------------------
echo "[1/3] Building Tarball package..."
TAR_DIR="${BUILD_DIR}/cpu-cache-affinity-wait-${VERSION}-linux-x86_64"
mkdir -p "${TAR_DIR}"

cp "${PROJECT_ROOT}/cpu_cache_affinity_wait.sh" "${TAR_DIR}/"
cp "${PROJECT_ROOT}/cpu_cache_affinity_wait.bt" "${TAR_DIR}/"
[[ -f "${PROJECT_ROOT}/README.md" ]] && cp "${PROJECT_ROOT}/README.md" "${TAR_DIR}/"
[[ -f "${PROJECT_ROOT}/LICENSE" ]] && cp "${PROJECT_ROOT}/LICENSE" "${TAR_DIR}/"

# Create install script for tarball
cat << 'EOF' > "${TAR_DIR}/install.sh"
#!/usr/bin/env bash
set -e

PREFIX="${PREFIX:-/usr/local}"
BIN_DIR="${PREFIX}/bin"
SHARE_DIR="${PREFIX}/share/cpu-cache-affinity-wait"

echo "Installing cpu-cache-affinity-wait to ${PREFIX}..."
mkdir -p "${BIN_DIR}" "${SHARE_DIR}"

install -m 755 cpu_cache_affinity_wait.sh "${BIN_DIR}/cpu_cache_affinity_wait.sh"
ln -sf "${BIN_DIR}/cpu_cache_affinity_wait.sh" "${BIN_DIR}/cpu_cache_affinity_wait"
install -m 644 cpu_cache_affinity_wait.bt "${SHARE_DIR}/cpu_cache_affinity_wait.bt"

echo "Installation complete!"
echo "Run 'sudo cpu_cache_affinity_wait' or 'sudo cpu_cache_affinity_wait.sh -h'."
EOF
chmod +x "${TAR_DIR}/install.sh"

tar -czf "${DIST_DIR}/cpu-cache-affinity-wait-${VERSION}-linux-x86_64.tar.gz" -C "${BUILD_DIR}" "cpu-cache-affinity-wait-${VERSION}-linux-x86_64"
echo "  -> Created ${DIST_DIR}/cpu-cache-affinity-wait-${VERSION}-linux-x86_64.tar.gz"

# ------------------------------------------------------------------
# 2. Build Debian Package (.deb)
# ------------------------------------------------------------------
echo "[2/3] Building Debian (.deb) package..."
DEB_PACKAGE_NAME="cpu-cache-affinity-wait_${VERSION}_${ARCH}"
DEB_ROOT="${BUILD_DIR}/${DEB_PACKAGE_NAME}"

mkdir -p "${DEB_ROOT}/DEBIAN"
mkdir -p "${DEB_ROOT}/usr/bin"
mkdir -p "${DEB_ROOT}/usr/share/cpu-cache-affinity-wait"
mkdir -p "${DEB_ROOT}/usr/share/doc/cpu-cache-affinity-wait"

# Control file
cat << EOF > "${DEB_ROOT}/DEBIAN/control"
Package: cpu-cache-affinity-wait
Version: ${VERSION}
Section: admin
Priority: optional
Architecture: ${ARCH}
Depends: bpftrace (>= 0.12.0), bash (>= 4.0)
Maintainer: Senior Kernel & eBPF Engineering Team <devops@local>
Description: Trace CPU affinity wait and cache-warmth migration latency
 cpu-cache-affinity-wait is an eBPF/bpftrace performance engineering tool
 designed to measure task delays in the RUNNABLE state when kernel migration
 to idle CPUs is prevented by cache warmth (task_hot) or CPU affinity masks.
EOF

# Install files into package layout
install -m 755 "${PROJECT_ROOT}/cpu_cache_affinity_wait.sh" "${DEB_ROOT}/usr/bin/cpu_cache_affinity_wait.sh"
ln -sf cpu_cache_affinity_wait.sh "${DEB_ROOT}/usr/bin/cpu_cache_affinity_wait"
install -m 644 "${PROJECT_ROOT}/cpu_cache_affinity_wait.bt" "${DEB_ROOT}/usr/share/cpu-cache-affinity-wait/cpu_cache_affinity_wait.bt"
[[ -f "${PROJECT_ROOT}/README.md" ]] && install -m 644 "${PROJECT_ROOT}/README.md" "${DEB_ROOT}/usr/share/doc/cpu-cache-affinity-wait/README.md"

if command -v dpkg-deb >/dev/null 2>&1; then
    dpkg-deb --build "${DEB_ROOT}" "${DIST_DIR}/${DEB_PACKAGE_NAME}.deb"
    echo "  -> Created ${DIST_DIR}/${DEB_PACKAGE_NAME}.deb"
else
    echo "  -> Warning: dpkg-deb not found. Skipping .deb file generation."
fi

# ------------------------------------------------------------------
# 3. Build RPM Package (.rpm)
# ------------------------------------------------------------------
echo "[3/3] Building RPM (.rpm) package..."
if command -v rpmbuild >/dev/null 2>&1; then
    RPM_TOPDIR="${BUILD_DIR}/rpmbuild"
    mkdir -p "${RPM_TOPDIR}"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
    
    cat << EOF > "${RPM_TOPDIR}/SPECS/cpu-cache-affinity-wait.spec"
Name:           cpu-cache-affinity-wait
Version:        ${RPM_VERSION}
Release:        1%{?dist}
Summary:        Trace CPU affinity wait and cache-warmth migration latency
License:        MIT
BuildArch:      noarch
Requires:       bpftrace, bash

%description
eBPF/bpftrace tool to analyze CPU cache-warmth & affinity scheduling wait delays.

%prep

%build

%install
mkdir -p %{buildroot}/usr/bin
mkdir -p %{buildroot}/usr/share/cpu-cache-affinity-wait
install -m 755 ${PROJECT_ROOT}/cpu_cache_affinity_wait.sh %{buildroot}/usr/bin/cpu_cache_affinity_wait.sh
ln -sf cpu_cache_affinity_wait.sh %{buildroot}/usr/bin/cpu_cache_affinity_wait
install -m 644 ${PROJECT_ROOT}/cpu_cache_affinity_wait.bt %{buildroot}/usr/share/cpu-cache-affinity-wait/cpu_cache_affinity_wait.bt

%files
/usr/bin/cpu_cache_affinity_wait.sh
/usr/bin/cpu_cache_affinity_wait
/usr/share/cpu-cache-affinity-wait/cpu_cache_affinity_wait.bt

%changelog
* Thu Oct 08 2026 Senior Kernel Engineer - 1.0.0-1
- Initial RPM release
EOF

    rpmbuild --define "_topdir ${RPM_TOPDIR}" -bb "${RPM_TOPDIR}/SPECS/cpu-cache-affinity-wait.spec"
    find "${RPM_TOPDIR}/RPMS" -name "*.rpm" -exec cp {} "${DIST_DIR}/" \; 2>/dev/null || true
    echo "  -> Created RPM package in ${DIST_DIR}"
elif command -v fpm >/dev/null 2>&1; then
    fpm -s dir -t rpm -n cpu-cache-affinity-wait -v "${VERSION}" \
        --prefix / \
        -d "bpftrace" \
        "${PROJECT_ROOT}/cpu_cache_affinity_wait.sh=/usr/bin/cpu_cache_affinity_wait.sh" \
        "${PROJECT_ROOT}/cpu_cache_affinity_wait.bt=/usr/share/cpu-cache-affinity-wait/cpu_cache_affinity_wait.bt"
    find . -maxdepth 1 -name "*.rpm" -exec mv {} "${DIST_DIR}/" \; 2>/dev/null || true
    echo "  -> Created RPM package via fpm in ${DIST_DIR}"
else
    echo "  -> Note: rpmbuild or fpm not found locally. RPM packaging will run in CI."
fi

echo "=================================================================="
echo " Package build completed! Output files in dist/:"
ls -lh "${DIST_DIR}"
echo "=================================================================="
