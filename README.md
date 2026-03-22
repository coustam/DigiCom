# Digital Comms Lab Platform (Raspberry Pi 5 + GNU Radio + PlutoSDR)

This platform standardizes the student environment on a Raspberry Pi 5 (SD-card based):
- GNU Radio built from source (default tag: v3.10.9.2) installed to `/usr/local`
- PlutoSDR support via libiio + libad9361 + udev rules (no sudo needed for USB after reboot)
- VS Code on the Pi + mandatory extensions (Python + Jupyter)
- Shared Python environment + Jupyter kernel that can `import gnuradio`
- Detailed installation logs and built-in validation steps

---

## Requirements

Hardware:
- Raspberry Pi 5 (4GB or 8GB recommended)
- SD card: 64GB recommended (source builds are disk-heavy)
- Stable power supply
- Network access during installation (apt + GitHub + VS Code extension downloads)

OS:
- Raspberry Pi OS Bookworm, 64-bit Desktop

---

## Install (one-time)

1) Copy `digicom_setup_pi5.sh` to the Pi
2) Run:

```bash
chmod +x digicom_setup_pi5.sh
sudo ./digicom_setup_pi5.sh
sudo reboot
