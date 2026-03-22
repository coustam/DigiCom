#!/usr/bin/env bash
set -euo pipefail
umask 022

# =========================
# Course baseline settings
# =========================
GR_TAG="${GR_TAG:-v3.10.9.2}"              # GNU Radio tag/branch
JOBS="${JOBS:-2}"                          # SD-card friendly
MIN_FREE_GB="${MIN_FREE_GB:-18}"           # fail early if space too low
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"
KEEP_BUILD="${KEEP_BUILD:-0}"              # 0=remove build/tmp dirs after install, 1=keep

export DEBIAN_FRONTEND=noninteractive

# Build locations (keep under home; avoid /tmp filling root unexpectedly)
BUILD_USER="${SUDO_USER:-}"
if [[ -z "$BUILD_USER" ]]; then
  echo "ERROR: run via sudo from a normal user (SUDO_USER empty)."
  exit 1
fi

HOME_DIR="$(eval echo "~$BUILD_USER")"
BUILD_ROOT="${BUILD_ROOT:-$HOME_DIR/prj}"
SRC_DIR="${SRC_DIR:-$BUILD_ROOT/gnuradio}"
BUILD_DIR="${BUILD_DIR:-$SRC_DIR/build}"
TMP_DIR="${TMP_DIR:-$BUILD_ROOT/tmp}"

# Python / Jupyter
COURSE_VENV="${COURSE_VENV:-/opt/digicom-venv}"
KERNEL_NAME="${KERNEL_NAME:-digicom}"
KERNEL_DISPLAY="${KERNEL_DISPLAY:-Python (digicom)}"

# VS Code (mandatory)
VSCODE_EXTENSIONS=(
  "ms-python.python"
  "ms-toolsai.jupyter"
)

# Pluto udev rule path
UDEV_RULE="/etc/udev/rules.d/53-adi-plutosdr-usb.rules"

# Logging
LOG_DIR="/var/log/digicom"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/setup_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

trap 'echo "ERROR on line $LINENO: $BASH_COMMAND" >&2' ERR

# -------------------------
# Helpers
# -------------------------
step() { echo; echo "==> $1"; }

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run as root: sudo $0"
    exit 1
  fi
}

require_bookworm() {
  source /etc/os-release
  if [[ "${VERSION_CODENAME:-}" != "bookworm" ]]; then
    echo "ERROR: expected Raspberry Pi OS / Debian Bookworm; got: ${VERSION_CODENAME:-unknown}"
    exit 1
  fi
}

ensure_free_space_gb() {
  local path="$1"
  local need="$2"
  local avail
  avail="$(df -PBG "$path" | awk 'NR==2{gsub(/G/,"",$4); print $4}')"
  echo "Free space on $(df -P "$path" | awk 'NR==2{print $6}') : ${avail}G (need >= ${need}G)"
  if [[ -z "$avail" || "$avail" -lt "$need" ]]; then
    echo "ERROR: not enough free space. Need >= ${need}G at $path."
    echo "Tips: fresh OS image, larger SD card (64GB+), reduce MIN_FREE_GB only if you accept risk."
    exit 1
  fi
}

apt_update() {
  apt-get -o Dpkg::Lock::Timeout=60 -o Acquire::Retries=3 update
}

apt_install() {
  apt-get -o Dpkg::Lock::Timeout=60 -o Acquire::Retries=3 install -y "$@"
}

# -------------------------
# Preflight
# -------------------------
require_root
step "Log file: $LOG_FILE"
step "Preflight: OS check (expecting Bookworm)"
require_bookworm

step "Preflight: build dirs + free space checks"
mkdir -p "$BUILD_ROOT" "$TMP_DIR"
chown -R "$BUILD_USER:$BUILD_USER" "$BUILD_ROOT"

# Check both build location and root filesystem
ensure_free_space_gb "$BUILD_ROOT" "$MIN_FREE_GB"
ensure_free_space_gb "/" "$MIN_FREE_GB"

# Redirect temp files away from /tmp
export TMPDIR="$TMP_DIR"
echo "TMPDIR=$TMPDIR"
echo "JOBS=$JOBS"
echo "INSTALL_PREFIX=$INSTALL_PREFIX"
echo "KEEP_BUILD=$KEEP_BUILD"
echo "GR_TAG=$GR_TAG"

# -------------------------
# APT repair + clean
# -------------------------
step "Repair dpkg/apt state (handles interrupted installs)"
dpkg --configure -a || true

step "apt update"
apt_update

step "Clean apt caches to save space"
apt-get clean
apt-get autoremove -y || true

ensure_free_space_gb "$BUILD_ROOT" "$MIN_FREE_GB"

# -------------------------
# Base tools
# -------------------------
step "Install base tools (git, build tools, python tooling)"
apt_install \
  ca-certificates curl wget gnupg \
  git git-lfs \
  build-essential pkg-config \
  cmake ninja-build \
  python3 python3-dev python3-venv python3-pip \
  usbutils

git lfs install --system >/dev/null 2>&1 || true
git config --system init.defaultBranch main

# -------------------------
# GNU Radio build deps (core + QtGUI)
# -------------------------
step "Install GNU Radio build dependencies (QtGUI enabled; docs/tests disabled)"
# Docs tooling intentionally not installed (we disable docs in CMake)
apt_install \
  python3-mako python3-numpy python3-yaml \
  python3-click python3-click-plugins python3-zmq \
  python3-pyqt5 python3-packaging python3-jsonschema \
  pybind11-dev \
  qtbase5-dev qtbase5-dev-tools qtchooser qt5-qmake \
  libboost-date-time-dev libboost-program-options-dev \
  libboost-filesystem-dev libboost-system-dev \
  libboost-thread-dev libboost-serialization-dev \
  libboost-regex-dev \
  libgmp-dev swig \
  libspdlog-dev liblog4cpp5-dev \
  libfftw3-dev libgsl-dev \
  libqwt-qt5-dev libqt5opengl5-dev libqt5svg5-dev \
  libeigen3-dev libvolk2-dev \
  libsndfile1-dev libzmq3-dev \
  liborc-0.4-dev \
  libusb-1.0-0-dev

# Pluto / IIO deps (gr-iio + AD9361)
step "Install Pluto/IIO dependencies"
apt_install \
  libiio-utils libiio-dev iiod python3-libiio \
  libad9361-0 libad9361-dev

ensure_free_space_gb "$BUILD_ROOT" "$MIN_FREE_GB"

# -------------------------
# Fetch + build GNU Radio
# -------------------------
step "Fetch GNU Radio source ($GR_TAG) without re-downloading unnecessarily"
sudo -u "$BUILD_USER" mkdir -p "$SRC_DIR"

if [[ ! -d "$SRC_DIR/.git" ]]; then
  sudo -u "$BUILD_USER" git clone --recursive https://github.com/gnuradio/gnuradio.git "$SRC_DIR"
fi

pushd "$SRC_DIR" >/dev/null
sudo -u "$BUILD_USER" git fetch --tags --prune
sudo -u "$BUILD_USER" git checkout "$GR_TAG"
sudo -u "$BUILD_USER" git submodule update --init --recursive
popd >/dev/null

step "Configure GNU Radio (Release; docs/tests OFF; GRC + QtGUI ON; IIO ON)"
mkdir -p "$BUILD_DIR"
rm -rf "$BUILD_DIR"/*
chown -R "$BUILD_USER:$BUILD_USER" "$BUILD_DIR"

pushd "$BUILD_DIR" >/dev/null
sudo -u "$BUILD_USER" cmake -G Ninja .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$INSTALL_PREFIX" \
  -DPYTHON_EXECUTABLE=/usr/bin/python3 \
  -DENABLE_TESTING=OFF \
  -DENABLE_DOXYGEN=OFF \
  -DENABLE_SPHINX=OFF \
  -DENABLE_GRC=ON \
  -DENABLE_GR_QTGUI=ON \
  -DENABLE_GR_IIO=ON

step "Build GNU Radio (Ninja, -j$JOBS)"
ensure_free_space_gb "$BUILD_ROOT" "$MIN_FREE_GB"
sudo -u "$BUILD_USER" cmake --build . -j"$JOBS"

step "Install GNU Radio"
cmake --install .
ldconfig
popd >/dev/null

# -------------------------
# Pluto udev rule
# -------------------------
step "Install Pluto udev rules (USB access without sudo after reboot)"
if ! curl -fsSL \
  https://raw.githubusercontent.com/analogdevicesinc/plutosdr-fw/master/scripts/53-adi-plutosdr-usb.rules \
  -o "$UDEV_RULE"; then
  echo "WARN: Could not download ADI udev rule; using fallback rule."
  cat > "$UDEV_RULE" <<'EOF'
SUBSYSTEM=="usb", ATTRS{idVendor}=="0456", ATTRS{idProduct}=="b674", MODE="0664", GROUP="plugdev", ENV{ID_MM_DEVICE_IGNORE}="1"
SUBSYSTEM=="usb", ATTRS{idVendor}=="0456", ATTRS{idProduct}=="b673", MODE="0664", GROUP="plugdev", ENV{ID_MM_DEVICE_IGNORE}="1"
EOF
fi

chmod 0644 "$UDEV_RULE"
getent group plugdev >/dev/null || groupadd plugdev
usermod -aG plugdev "$BUILD_USER"
udevadm control --reload-rules
udevadm trigger

# -------------------------
# VS Code + mandatory extensions
# -------------------------
step "Install VS Code"
if ! apt-cache show code >/dev/null 2>&1; then
  echo "ERROR: APT package 'code' not found."
  echo "Make sure you're using Raspberry Pi OS Bookworm (Desktop) repositories."
  exit 1
fi
apt_install code

step "Install mandatory VS Code extensions for $BUILD_USER (deterministic dirs)"
USER_DATA_DIR="$HOME_DIR/.vscode-user-data"
EXT_DIR="$HOME_DIR/.vscode/extensions"
install -d -m 0755 -o "$BUILD_USER" -g "$BUILD_USER" "$USER_DATA_DIR" "$EXT_DIR"

for ext in "${VSCODE_EXTENSIONS[@]}"; do
  echo "  -> Installing $ext"
  sudo -u "$BUILD_USER" env \
    HOME="$HOME_DIR" \
    XDG_CONFIG_HOME="$HOME_DIR/.config" \
    XDG_DATA_HOME="$HOME_DIR/.local/share" \
    code --user-data-dir "$USER_DATA_DIR" --extensions-dir "$EXT_DIR" \
         --install-extension "$ext" --force
done

# -------------------------
# Course venv + Jupyter kernel (can import gnuradio)
# -------------------------
step "Create course venv (system-site-packages so GNU Radio python is visible)"
if [[ ! -d "$COURSE_VENV" ]]; then
  python3 -m venv --system-site-packages "$COURSE_VENV"
fi

"$COURSE_VENV/bin/pip" install -U pip wheel setuptools
"$COURSE_VENV/bin/pip" install -U \
  jupyterlab ipykernel numpy scipy matplotlib \
  pyadi-iio

step "Register Jupyter kernel '$KERNEL_NAME' system-wide"
"$COURSE_VENV/bin/python" -m ipykernel install \
  --prefix=/usr/local \
  --name "$KERNEL_NAME" \
  --display-name "$KERNEL_DISPLAY"

cat > /etc/profile.d/digicom-env.sh <<'EOF'
alias digicom-venv='source /opt/digicom-venv/bin/activate'
EOF
chmod 0644 /etc/profile.d/digicom-env.sh

# -------------------------
# Validation (non-interactive)
# -------------------------
step "Validate GNU Radio install (CLI + python import)"
command -v gnuradio-config-info >/dev/null
echo "GNU Radio version: $(gnuradio-config-info --version)"
echo "Enabled components:"
gnuradio-config-info --enabled-components || true

python3 - <<'PY'
from gnuradio import gr, blocks
print("OK: system python can import gnuradio")
PY

"$COURSE_VENV/bin/python" - <<'PY'
from gnuradio import gr
print("OK: venv python can import gnuradio")
PY

# -------------------------
# Cleanup to save SD space
# -------------------------
if [[ "$KEEP_BUILD" != "1" ]]; then
  step "Cleanup: removing build/tmp dirs to save SD space (KEEP_BUILD=0)"
  rm -rf "$BUILD_DIR" || true
  rm -rf "$TMP_DIR" || true
  echo "Cleanup done. Source tree remains at: $SRC_DIR"
else
  step "Cleanup skipped (KEEP_BUILD=1)"
fi

step "Final notes + next steps"
echo "Setup complete. Full log: $LOG_FILE"
echo
echo "NEXT: reboot so group membership (plugdev) applies:"
echo "  sudo reboot"
echo
echo "After reboot, plug Pluto and run:"
echo "  iio_info -s"
echo
echo "Launch GNU Radio:"
echo "  gnuradio-companion"
echo
echo "Launch VS Code:"
echo "  code"
echo "In VS Code notebooks select kernel: $KERNEL_DISPLAY"
