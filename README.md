# Wan2GP One-Click Automated Installer

An automated setup script to install and run [Wan2GP](https://github.com/deepbeepmeep/Wan2GP) locally on Windows. Generate AI videos directly on your NVIDIA GPU without manual command-line configuration.

> **🎉 Welcome to v2:** This release is a complete, ground-up rewrite that replaces silent command-line hangs with a clean, resilient setup experience. v2 introduces real-time download progress for multi-gigabyte files, automatic GPU-to-CUDA hardware matching, comprehensive session logging, and an interactive launcher menu to easily **Update** or **Repair** your setup without redownloading model weights.

---

## ⚡ Quick Start (Recommended)

1. **Download:** Grab the latest `Wan2GP_OneClick_Installer_v2.bat` from this repository.
2. **Run:** Double-click the `.bat` file (no admin rights needed to start).
3. **Follow the On-Screen Prompts:**
* Keep an eye on your taskbar—if Git or Python needs to install, Windows will ask for permission (UAC prompt).
* A live progress bar will show the status while downloading PyTorch and dependencies.


4. **Create:** Once setup completes, Wan2GP will open automatically in your browser at `http://localhost:7860`.

> **Re-opening the app later:** Double-click the `.bat` file anytime. A menu will appear with options to **Launch**, **Update**, or **Repair** your setup.

---

## 💻 System Requirements

| Component | Minimum Requirement | Notes |
| --- | --- | --- |
| **Operating System** | Windows 10 / 11 (64-bit) |  |
| **Graphics Card (GPU)** | NVIDIA RTX 20-series or newer | RTX 30, 40, and 50-series fully supported |
| **Drivers** | Latest NVIDIA Drivers | [Download from NVIDIA](https://nvidia.com/drivers) |
| **Storage** | 50 GB+ free disk space | Required for AI video model weights |
| **Internet** | Stable broadband | Downloads large model packages |

---

## 📦 What the Installer Does Automatically

You do not need to install Python, Git, or CUDA libraries beforehand. The script automatically handles:

* Installing **Python 3.10** and **Git** (if not already found).
* Detecting your specific GPU and matching the optimal **PyTorch + CUDA** version.
* Downloading the latest **Wan2GP** source code and libraries.
* Enabling speed optimizations (**SageAttention** and **Triton**) if your card supports them.

---

## 🛠️ Common Fixes & Troubleshooting

* Ensure you have an NVIDIA card installed (AMD and Intel GPUs are not supported).
* Update your GPU drivers from [nvidia.com/drivers](https://nvidia.com/drivers), reboot your PC, and launch the installer again.

* Check your Windows taskbar for a **flashing blue-and-yellow shield icon**.
* Windows often opens permission (UAC) prompts minimized in the background. Click it and select **Yes** to continue.

* An instance of Wan2GP (or another local tool like Stable Diffusion) is already running.
* Close existing browser and terminal windows, or terminate background Python processes in Task Manager.

* Run the `.bat` file again and choose **Option 3: Repair**. This rebuilds your virtual environment cleanly without deleting your downloaded model weights.

Everything installs to your user folder:

* **App files:** `%USERPROFILE%\Wan2GP\`
* **Error & Run Logs:** `%USERPROFILE%\Wan2GP\logs\`
* **To completely uninstall:** Delete the `%USERPROFILE%\Wan2GP\` folder.

---

## 🔧 Technical Details & Customization (For Advanced Users)

### Architecture (v2 Hybrid)

The installer uses a hybrid `.bat` launcher wrapping embedded PowerShell execution:

* **Absolute Path Execution:** Avoids PATH conflicts by invoking `$VenvDir\Scripts\python.exe` directly rather than relying on `activate.bat`.
* **Dynamic GPU Matrix:** Maps compute capability directly to compatible PyTorch, CUDA, Triton, and SageAttention binaries.
* **Deterministic Flags:** Probes once for optional dependencies to avoid cascading crash loops.

### Directory Layout

```text
%USERPROFILE%\Wan2GP\
├── source/          # Wan2GP repository clone
├── venv/            # Python virtual environment
├── logs/            # Transcript and pip logs
└── .installed       # Installation metadata flag

```

### Manual Launch via PowerShell

```powershell
$python = "$env:USERPROFILE\Wan2GP\venv\Scripts\python.exe"
& $python "$env:USERPROFILE\Wan2GP\source\wgp.py" --open-browser

```

### Custom Configuration

Edit the `# Configuration` block at the top of the script to adjust parameters:

```powershell
$PythonVersion = '3.11.0'  # Change Python version
$MinFreeGB = 100           # Change minimum disk space check

```

---

## 📄 License & Credits

* **Installer:** Released under the [MIT License](https://www.google.com/search?q=LICENSE).
* **Core Application:** See the original [Wan2GP Repository](https://github.com/deepbeepmeep/Wan2GP) for upstream model licenses and codebase documentation.
