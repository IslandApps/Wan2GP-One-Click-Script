# Wan2GP One-Click Automated Installer

A one-click, fully automated script for installing [Wan2GP](https://github.com/deepbeepmeep/Wan2GP), an open-source text-to-video and Lora generation suite for NVIDIA GPUs. Wan2GP is built for the NVIDIA CUDA ecosystem and runs entirely locally on your graphics card.

---

## About v2: A Complete Rewrite

If you're reading this for the first time, **use v2.** It's a ground-up rewrite that fixes years of edge cases in the original batch-only approach.

### What Was Wrong with v1?

The original installer was pure batch script — clever, but fragile. Batch is designed for simple system tasks, not complex dependency orchestration. Here's what kept breaking:

- **Virtual environment activation** was a mess. Batch's `call activate.bat` sets environment variables in a subprocess, which often didn't persist or got lost mid-script. This caused "Python not found" errors that went away on the second run.
- **PATH management** was a constant struggle. Batch has no good way to merge environment variables; we kept resorting to timeouts and crossed fingers.
- **Error recovery was invisible.** When something failed silently (like an old Triton version), the script would cascade through half a dozen fallback methods, printing confusing messages and leaving you wondering what actually happened.
- **Triton detection was brittle.** We checked for a symbol (`AttrsDescriptor`) that got *removed* in newer Triton versions — so correct installs would fail the check and downgrade themselves.
- **GPU detection worked, but GPU version matching was hardcoded.** Adding support for a new RTX 50-series meant scattered changes in three different places.

### What v2 Does Differently

v2 is a **polyglot batch/PowerShell hybrid**: the file is named `.bat` so Windows runs it with cmd.exe, but the batch part is tiny — just a launcher that extracts and executes PowerShell code embedded in the same file.

**Why PowerShell?**

- PowerShell is guaranteed on Windows 10/11. No external dependencies.
- It has real exception handling (`try/finally`), proper object data structures, and native command invocation that respects exit codes.
- It can manage paths, downloads, and environment variables *reliably.*

**The actual improvements:**

1. **No activation state guessing:** After creating the venv, v2 just calls `$VenvDir\Scripts\python.exe` directly with absolute paths. No `activate.bat`, no subprocess environment variables, no mysteries.

2. **GPU matrix:** A single data structure at the top of the script maps GPU compute capability → PyTorch version, CUDA tag, Triton version, and SageAttention wheel URL. When new GPUs ship, you add one row. That's it. No scattered hardcoding.

3. **Live pip progress:** When downloading 2–3 GB of PyTorch, the old script printed nothing for 10+ minutes. v2 shows real-time progress: package name, download %, bytes downloaded, ETA. You can actually see that it's not hung.

4. **Comprehensive logging:** Every run saves a full PowerShell transcript (`wan2gp-YYYYMMDD-HHMMSS.log`) and separate pip logs. When something fails, the script prints the last 30 lines of the relevant log inline, plus a path to the full logs. You don't have to guess where to look.

5. **Triton fixed.** We removed the brittle `AttrsDescriptor` check (that symbol no longer exists). Instead, we just try to import `triton`. If it works, we use `--compile`. If not, no big deal — the app runs fine without it.

6. **Smart recovery options:** Instead of "delete everything and start over," v2 offers a menu when you run it again:
   - Launch (default)
   - Update (git pull + refresh dependencies)
   - Repair (rebuild the venv, keep your model weights)
   - Exit

7. **Better UX:** A welcome screen explains what's about to happen. If Windows needs to elevate (for Git or Python), the script warns you *before* the UAC prompt appears, so you know to look in the taskbar for a minimized dialog.

### v1 Still Works

v1 is archived in the `Archive/` folder and will work in most cases. But we're not fixing bugs in it anymore. If you run into the activation or PATH issues, the solution is to use v2.

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

## Requirements

- **Windows 10/11** (64-bit)
- **NVIDIA GPU** with CUDA support (RTX 20-series or newer; RTX 50-series fully supported)
- **Up-to-date NVIDIA drivers**
- **50 GB+ free disk space** (for model weights)
- **Stable internet connection**

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
