#!/usr/bin/env bash
set -Eeuo pipefail

LOG_DIR="${HOME}/prj/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/digicom_setup_$(date +%Y%m%d_%H%M%S).log"
exec > >(tee -a "${LOG_FILE}") 2>&1

trap 'rc=$?; echo; echo "[ERROR] line ${LINENO}: ${BASH_COMMAND}"; echo "[ERROR] exit code: ${rc}"; echo "[ERROR] log: ${LOG_FILE}"; exit ${rc}' ERR

GR_VERSION="v3.10.9.2"
SRC_DIR="${HOME}/prj/gnuradio"
BUILD_DIR="${SRC_DIR}/build"
TMP_DIR="${HOME}/prj/tmp"
LORA_DIR="${HOME}/prj/gr-lora_sdr"
JOBS="2"

echo "[INFO] log: ${LOG_FILE}"

echo "[1/9] Checking free space..."
df -h /

echo "[2/9] Repairing package manager state..."
sudo dpkg --configure -a || true
sudo apt update

echo "[3/9] Cleaning package cache..."
sudo apt clean
sudo apt autoremove -y || true

echo "[4/9] Detecting VOLK package name..."
VOLK_PKG="libvolk-dev"
if apt-cache show libvolk-dev >/dev/null 2>&1; then
  VOLK_PKG="libvolk-dev"
elif apt-cache show libvolk2-dev >/dev/null 2>&1; then
  VOLK_PKG="libvolk2-dev"
else
  echo "[ERROR] Could not find libvolk-dev or libvolk2-dev"
  exit 1
fi
echo "[INFO] Using VOLK package: ${VOLK_PKG}"

echo "[5/9] Installing GNU Radio build dependencies..."
sudo apt install -y \
  git cmake g++ pkg-config \
  python3-dev python3-pip python3-mako python3-numpy python3-yaml \
  python3-click python3-click-plugins python3-zmq python3-pyqt5 \
  python3-sphinx python3-packaging python3-jsonschema \
  python3-gi python3-cairo \
  pybind11-dev \
  libboost-date-time-dev libboost-program-options-dev \
  libboost-filesystem-dev libboost-system-dev libboost-thread-dev \
  libboost-serialization-dev libboost-regex-dev \
  libgmp-dev swig liblog4cpp5-dev libspdlog-dev \
  libfftw3-dev libcomedi-dev libsdl1.2-dev libgsl-dev \
  libqwt-qt5-dev libqt5opengl5-dev libqt5svg5-dev \
  libxi-dev \
  libeigen3-dev "${VOLK_PKG}" \
  libsndfile1-dev libzmq3-dev libiio-dev libad9361-dev \
  libuhd-dev

echo "[6/9] Preparing directories..."
mkdir -p "${HOME}/prj" "${TMP_DIR}"
export TMPDIR="${TMP_DIR}"

if [ ! -d "${SRC_DIR}/.git" ]; then
  echo "[7/9] Cloning GNU Radio source..."
  git clone --branch "${GR_VERSION}" https://github.com/gnuradio/gnuradio.git "${SRC_DIR}"
else
  echo "[7/9] GNU Radio source already present, not cloning again..."
fi

echo "[8/9] Configuring GNU Radio..."
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"
rm -rf ./*

cmake .. \
  -DENABLE_DOXYGEN=OFF \
  -DENABLE_HTML=OFF \
  -DENABLE_PDF=OFF

echo "[9/9] Building GNU Radio with ${JOBS} jobs..."
make -j"${JOBS}"
sudo make install
sudo ldconfig

echo
echo "[INFO] GNU Radio install finished."
echo "[INFO] Try: gnuradio-companion"

if [ -d "${LORA_DIR}/.git" ] || [ -f "${LORA_DIR}/CMakeLists.txt" ]; then
  echo
  echo "[INFO] Found gr-lora_sdr at ${LORA_DIR}"
  mkdir -p "${LORA_DIR}/build"
  cd "${LORA_DIR}/build"
  rm -rf ./*
  cmake ..
  make -j"${JOBS}"
  sudo make install
  sudo ldconfig
  echo "[INFO] gr-lora_sdr installed."
else
  echo "[INFO] gr-lora_sdr not found at ${LORA_DIR}; skipping."
fi

echo
echo "[INFO] Done."
echo "[INFO] Log saved to: ${LOG_FILE}"
