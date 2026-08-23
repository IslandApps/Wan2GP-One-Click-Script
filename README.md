# Wan2GP One-Click Automated Installer

A one-click, fully automated script for installing [Wan2GP](https://github.com/deepbeepmeep/Wan2GP), an open-source text-to-video and Lora generation suite for NVIDIA GPUs. Wan2GP is built for the NVIDIA CUDA ecosystem and runs entirely locally on your graphics card.

> **Heads up:** Choose **v2** for new installations. It's a complete rewrite with better reliability and user experience.

---

## Version Comparison: v1 vs v2

### v2 (Recommended) ⭐

**A complete rewrite as a polyglot batch/PowerShell hybrid.**

#### What's Improved

| Feature | v1 | v2 |
|---------|----|----|
| **Language** | Pure Batch | Batch launcher + PowerShell engine |
| **Reliability** | Fragile PATH and activation workarounds | Solid, no activation state guessing |
| **Error Handling** | Broad catch-all fallbacks | Specific diagnostics and targeted fixes |
| **User Feedback** | Minimal (freezes without `SageAttention 2`) | Live pip progress with ETA and % complete |
| **Triton Detection** | Brittle AttrsDescriptor check | Removed (no longer needed in Triton 3.1+) |
| **PyTorch Versions** | Hardcoded for specific GPUs | Automatic matrix lookup by compute capability |
| **Virtual Environment** | Activation-based (error-prone) | Direct invocation with absolute paths (safe) |
| **Git Installation** | Curl-based (fragile) | Windows native: winget first, then fallback |
| **Disk Space Check** | None | Warns if <50 GB free (model weights are big) |
| **Logging** | Stdout only | Transcript + pip logs in `%INSTALL_DIR%/logs/` |
| **Recovery Options** | Delete and restart | Launch menu: Update, Repair, or Exit |
| **Attention Methods** | Aggressive cascade (noisy output) | Probed once, built into startup args |
| **Performance Tools** | All optional, mixed success | Strategic: Triton + SageAttention only |
| **First-Run UX** | No handholding | Welcome screen, UAC notices, inline help |

#### Key Technical Improvements

- **Polyglot Design:** Batch launcher extracts and runs embedded PowerShell. Never re-executed after the first line. Safe to modify.
- **GPU Matrix:** A single data structure lists torch/cuda/triton/wheel versions. Add a row when new GPU generations ship; no cascading changes elsewhere.
- **Immediate Venv Access:** Python/pip calls use absolute venv paths (`$VenvDir\Scripts\python.exe`) instead of activation. Eliminates the biggest class of state-related bugs.
- **Live Pip Progress:** Tracks downloads and resolves in real time without blocking for 10+ minutes.
- **Comprehensive Logging:** Full transcript + per-run pip logs. Failures show the tail of relevant logs inline, plus paths to full logs.
- **Zero AttrsDescriptor Checks:** That symbol was removed in Triton 3.1+. Older code that tests for it triggers false negatives and downgrades working installs.
- **Proper Exception Handling:** PowerShell's `try/finally` and `$ErrorActionPreference` are used correctly. Native commands go through `Invoke-Native` which respects exit codes.

---

### v1 (Legacy / Archive)

The original batch-only installer. Functional but prone to:
- Virtual environment activation edge cases
- Path refresh issues
- Cryptic Triton state problems
- Silent cascading fallbacks that mask issues

**When to use v1:**
- You're on a system that can't run PowerShell.
- You prefer pure batch code without external engines.

**Status:** Archived in the `Archive/` folder for reference. Bug fixes will not be backported.

---

## Requirements

- **Windows 10/11** (64-bit)
- **NVIDIA GPU** with CUDA support (RTX 20-series or newer; RTX 50-series fully supported)
- **Up-to-date NVIDIA drivers**
- **50 GB+ free disk space** (for model weights)
- **Stable internet connection**

---

## Quick Start

### For Most Users (v2)

1. **Download** `Wan2GP_OneClick_Installer_v2.bat` from this repository.
2. **Double-click** it (no admin elevation required initially; script will ask when needed).
3. **Follow the on-screen prompts:**
   - You'll see a welcome screen explaining what will be installed.
   - If Git needs installing, the script will warn you to look for a UAC prompt in your taskbar.
   - A live progress bar will track the PyTorch download (biggest step).
4. **Wait for launch:** The script opens Wan2GP in your browser at [http://localhost:7860](http://localhost:7860).

**To run again:**
- Double-click the script. You'll see a menu:
  - `1` → Launch (default)
  - `2` → Update (git pull + refresh dependencies)
  - `3` → Repair (rebuild the venv)
  - `4` → Exit

---

## Installation Locations

Both versions install to the same place for consistency:

```
%USERPROFILE%\Wan2GP\
├── source/                 # Wan2GP repo (wgp.py lives here)
│   └── wan2gp_env/        # Python venv for v1
├── venv/                   # Python venv for v2 (sibling, not nested)
├── logs/                   # Transcripts and pip logs (v2 only)
├── .installed              # Marker flag with install metadata (v2 only)
└── wan2gp_installed.flag   # Marker flag (v1 only)
```

To **uninstall,** delete `%USERPROFILE%\Wan2GP\`.

---

## What Gets Installed

- **Python 3.10** (if not present)
- **Git** (if not present)
- **PyTorch + torchvision + torchaudio** (version auto-selected by GPU)
- **Wan2GP source code** from its official GitHub repository
- **Project dependencies** (from `requirements.txt`)
- **Performance enhancements** (Triton for `torch.compile`, SageAttention for faster attention)

---

## How v2 Works

### Startup Flow

1. **Polyglot check:** Batch launcher detects if PowerShell is available and invokes the embedded script.
2. **Pre-flight checks:** Disk space, Python 3.10 detection, Git check.
3. **GPU detection:** Queries `nvidia-smi` for compute capability; looks up the matching PyTorch/CUDA pair in a matrix.
4. **Fresh install or menu:** If already installed, shows a menu. Otherwise, proceeds to install.
5. **Dependency installation:**
   - Python/Git as needed
   - PyTorch stack (with live download progress)
   - Project requirements
   - Triton (optional, enables `torch.compile`)
   - SageAttention (optional, faster attention)
6. **Startup:**
   - Probes once for `triton` and `sageattention` availability.
   - Builds the launch command line from what's available.
   - Runs `python wgp.py --open-browser [--compile] [--attention sage2|sage]`.
   - Logs the full session (transcript + diagnostics).

### Triton / SageAttention Strategy

Unlike v1's aggressive cascade ("try this, if it breaks try that"), v2 probes once:

- If **Triton** imports OK → add `--compile`.
- If **SageAttention 2** is installed → add `--attention sage2`.
- If **SageAttention 1** is installed → add `--attention sage`.
- If neither is available → no attention flags; runs with defaults.

The app itself handles what it supports. No silent cascading retries.

---

## Troubleshooting

### "No NVIDIA GPU detected"

1. Ensure you have an NVIDIA (not AMD, not Intel) graphics card.
2. Download the latest drivers from [nvidia.com/drivers](https://nvidia.com/drivers).
3. Reboot and re-run the script.

If you see "NVIDIA GPU present but nvidia-smi not found," your drivers are outdated or corrupted. Reinstall them.

### "torch.cuda.is_available() returned False"

Your NVIDIA driver is older than the CUDA runtime bundled with PyTorch. Update your driver and re-run the script.

### "OSError: WinError 127 — The specified procedure could not be found"

A **torch / torchvision / torchaudio ABI mismatch.** This usually means they were installed at different times and pip resolved incompatible versions.

**Fix:** Run the script and choose **Repair** (v2) or delete `%USERPROFILE%\Wan2GP\venv` (or `source/wan2gp_env` in v1) and re-run.

### Port 7860 Already in Use

Another instance of Wan2GP is running, or something else is on that port. Either:
- Close the other Wan2GP window, or
- Edit `wgp.py` to use a different port (search for `7860`).

### Git Installation Hangs / UAC Prompt Not Visible (v2)

The UAC consent dialog opens on a separate desktop, often minimized. **Watch your taskbar for a flashing blue-and-yellow shield icon** and click it to bring the prompt to the foreground. The script will wait and tell you when it's ready.

### Script Hung on "Resolving dependencies" or "Downloading"

The pip progress bar is working; it's just a multi-GB download. On a slow connection, this can take 10–20 minutes. Check the log file:

```
%USERPROFILE%\Wan2GP\logs\pip-*.out.log
```

to see what's actually downloading.

---

## Customization

### v2 (Recommended)

The script is split clearly:

- **Top section (batch launcher):** Only change the `set "W2G_SELF=..."` line if you're testing.
- **`# Configuration` block:** Adjust paths, Python version, Git URL, or GPU matrix here.
- **Functions below:** Safe to read and modify if you understand PowerShell.

Common changes:

```powershell
# Use Python 3.11 instead of 3.10
$PythonVersion = '3.11.0'

# Add a new GPU generation to the matrix
$Matrix += [pscustomobject]@{
    Name        = 'My Future GPU'
    MinComputeCap = [version]'15.0'
    Torch       = '2.99.0'
    ...
}

# Adjust minimum free disk space
$MinFreeGB = 100
```

### v1 (Legacy)

Pure batch; edit with Notepad. Configuration is near the top (Python URL, Git URL, etc.). Not recommended for changes; use v2 instead.

---

## Advanced

### Manually Starting Wan2GP (v2)

```powershell
$python = "C:\Users\YourName\Wan2GP\venv\Scripts\python.exe"
& $python C:\Users\YourName\Wan2GP\source\wgp.py --open-browser
```

### Checking Installed Metadata (v2)

After a successful install, `%USERPROFILE%\Wan2GP\.installed` contains:

```
installed=2024-01-15T14:30:45.1234567+00:00
gpu=NVIDIA GeForce RTX 4090
profile=Ada / Ampere / Turing and older
torch=2.6.0
cuda=cu126
```

### Viewing Logs (v2)

All logs are saved to `%USERPROFILE%\Wan2GP\logs/`:

- `wan2gp-YYYYMMDD-HHMMSS.log` — Full transcript of the entire run.
- `pip-YYYYMMDD-HHMMSS.{out,err}.log` — pip's detailed output and errors.

---

## About Wan2GP

[Wan2GP](https://github.com/deepbeepmeep/Wan2GP) is an open-source text-to-video and image generation toolkit featuring:

- **Video generation** with low VRAM requirements
- **Web-based UI** for easy model experimentation
- **Custom and prebuilt LoRA packs**
- **Optimized for NVIDIA GPUs** with CUDA

See the [Wan2GP GitHub repository](https://github.com/deepbeepmeep/Wan2GP) for details on models, features, and usage.

---

## License

This installer script is released under the [MIT License](LICENSE). You are free to use, modify, and distribute this script with proper attribution.

---

## Contributing

Found a bug or have an idea for v2? Please open an [issue](https://github.com/TechMitten/Wan2GP-One-Click-Script/issues) with:

- Your Windows version and GPU model
- The full error message from the log file (`%USERPROFILE%\Wan2GP\logs/`)
- Steps to reproduce

Thanks for helping make this better! 🚀
