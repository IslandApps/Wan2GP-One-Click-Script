# Wan2GP One-Click Automated Installer

A one-click, fully automated script for installing [Wan2GP](https://github.com/deepbeepmeep/Wan2GP), an open-source text-to-video and Lora generation suite for NVIDIA GPUs. Wan2GP is built for the GPU poor, offering low VRAM requirements. The script manages all dependencies, sets up the environment, and launches Wan2GP in your browser.


---

## Features

- Automated installation and launch process
- Detection and installation of Python 3.10 and Git if not present
- NVIDIA GPU detection and selection of compatible CUDA/PyTorch versions
- Setup of all required and optional dependencies (including SageAttention, Triton, and Flash Attention)
- Automatic fallback to compatible attention methods if needed
- No manual setup required

---

## Requirements

- Windows 10/11 (64-bit)
- NVIDIA GPU with CUDA support (GTX 600 series or newer recommended)
- Internet connection

---

## Quick Start

1. Download the `Wan2GP_OneClick_Installer.bat` file from this repository.
2. Right-click the file and select **Run as Administrator**.
3. The script will:
   - Check for Python 3.10 and Git, installing them if needed
   - Detect your NVIDIA GPU and select the appropriate PyTorch and CUDA version
   - Clone the Wan2GP repository
   - Set up a Python virtual environment and install all dependencies
   - Attempt to optimize with SageAttention, Triton, and Flash Attention (if supported)
   - Launch Wan2GP in your browser at [http://localhost:7860](http://localhost:7860)

To relaunch Wan2GP later, run the installer again. It will skip completed installation steps if already set up.

---

## Script Workflow

| Step                  | Action                                                                 |
|-----------------------|------------------------------------------------------------------------|
| Python & Git Check    | Installs Python 3.10.9 and Git if not present                          |
| GPU Detection         | Detects NVIDIA GPU and selects compatible PyTorch/CUDA version         |
| Source Download       | Clones the Wan2GP repository                                           |
| Environment Setup     | Creates and activates a Python virtual environment                     |
| Dependency Install    | Installs PyTorch, Python requirements, and performance enhancements    |
| Launch                | Opens Wan2GP in your browser with the selected attention method        |

If a step fails (such as advanced attention methods), the script will automatically use a compatible alternative.

---

## Troubleshooting

- If no NVIDIA GPU is detected, the script will notify you. Wan2GP requires an NVIDIA GPU for full functionality.
- Ensure the latest NVIDIA drivers are installed.
- A stable internet connection is required for downloading dependencies.

---

## Customization

- The script is designed for automated use, but advanced users can modify it to change Python or CUDA versions, or add custom dependencies.
- All logic is contained in the batch script.

---

## About Wan2GP

Wan2GP is an open-source text-to-video and Lora generation toolkit featuring:
- Video generation with low VRAM requirements
- Web-based user interface
- Support for custom and prebuilt Lora packs
- Optimized for NVIDIA GPUs

See the [Wan2GP GitHub repository](https://github.com/deepbeepmeep/Wan2GP) for more information.

---

## License

This installer script is released under the [MIT License](LICENSE). You are free to use, modify, and distribute this script with proper attribution.
