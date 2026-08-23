@echo off
setlocal enabledelayedexpansion

:: Wan2GP One-Click Installer and Launcher for Windows
:: This script automatically installs and runs Wan2GP with all dependencies
:: Always installs to %userprofile%\Wan2GP regardless of admin rights or script location

title Wan2GP Auto-Installer and Launcher

echo ========================================
echo    Wan2GP One-Click Installer
echo ========================================
echo.

:: Set the installation directory to user's profile, regardless of admin rights or script location
set "INSTALL_DIR=%userprofile%\Wan2GP"
echo Target installation directory: !INSTALL_DIR!
echo.

:: Check if already installed
if exist "!INSTALL_DIR!\wan2gp_installed.flag" (
    echo Installation detected. Launching Wan2GP...
    goto :launch
)

echo Starting fresh installation...
echo.

:: Create installation directory
if not exist "!INSTALL_DIR!" mkdir "!INSTALL_DIR!"
cd /d "!INSTALL_DIR!"

:: Check for Python 3.10
echo [1/8] Checking Python 3.10 installation...
python --version 2>nul | findstr "3.10" >nul
if errorlevel 1 (
    echo Python 3.10 not found. Installing Python 3.10.9...
    
    :: Download Python 3.10.9
    echo Downloading Python 3.10.9...
    powershell -Command "& {Invoke-WebRequest -Uri 'https://www.python.org/ftp/python/3.10.9/python-3.10.9-amd64.exe' -OutFile 'python-installer.exe'}"
    
    :: Install Python silently for current user only
    echo Installing Python 3.10.9 for current user...
    python-installer.exe /quiet InstallAllUsers=0 PrependPath=1 Include_test=0 TargetDir="%userprofile%\AppData\Local\Programs\Python\Python310"
    
    :: Wait for installation to complete
    timeout /t 30 /nobreak >nul
    
    :: Add Python to PATH for current session
    set "PATH=%userprofile%\AppData\Local\Programs\Python\Python310;%userprofile%\AppData\Local\Programs\Python\Python310\Scripts;%PATH%"
    
    :: Refresh environment variables
    call refreshenv.cmd 2>nul || (
        echo Please restart this script after Python installation completes.
        pause
        exit /b 1
    )
    
    del python-installer.exe
) else (
    echo Python 3.10 found!
)

:: Check for Git
echo [2/8] Checking Git installation...
git --version 2>nul >nul
if errorlevel 1 (
    echo Git not found. Installing Git...
    
    :: Download Git
    echo Downloading Git...
    powershell -Command "& {Invoke-WebRequest -Uri 'https://github.com/git-for-windows/git/releases/download/v2.42.0.windows.2/Git-2.42.0.2-64-bit.exe' -OutFile 'git-installer.exe'}"
    
    :: Install Git silently for current user
    echo Installing Git...
    git-installer.exe /VERYSILENT /NORESTART /NOCANCEL /SP- /CLOSEAPPLICATIONS /RESTARTAPPLICATIONS /COMPONENTS="icons,ext\reg\shellhere,assoc,assoc_sh" /DIR="%userprofile%\AppData\Local\Programs\Git"
    
    :: Wait for installation
    timeout /t 60 /nobreak >nul
    
    :: Add Git to PATH for current session
    set "PATH=%PATH%;%userprofile%\AppData\Local\Programs\Git\bin"
    
    del git-installer.exe
) else (
    echo Git found!
)

:: Enhanced GPU detection
echo [3/8] Detecting NVIDIA GPU...

:: First, try to find nvidia-smi in common locations
set "NVIDIA_SMI_FOUND=0"
set "NVIDIA_SMI_PATH="

:: Check if nvidia-smi is already in PATH
nvidia-smi --version >nul 2>&1
if not errorlevel 1 (
    set "NVIDIA_SMI_FOUND=1"
    set "NVIDIA_SMI_PATH=nvidia-smi"
    echo nvidia-smi found in PATH
    goto :gpu_detected
)

:: Check common NVIDIA installation paths
set "COMMON_PATHS="C:\Program Files\NVIDIA Corporation\NVSMI" "C:\Windows\System32" "C:\Program Files (x86)\NVIDIA Corporation\NVSMI""

for %%p in (!COMMON_PATHS!) do (
    if exist "%%~p\nvidia-smi.exe" (
        set "NVIDIA_SMI_FOUND=1"
        set "NVIDIA_SMI_PATH=%%~p\nvidia-smi.exe"
        echo nvidia-smi found at: %%~p
        :: Add to PATH for current session
        set "PATH=!PATH!;%%~p"
        goto :gpu_detected
    )
)

:: PowerShell fallback to detect NVIDIA GPU
echo Trying PowerShell GPU detection...
powershell -Command "Get-WmiObject -Class Win32_VideoController | Where-Object {$_.Name -like '*NVIDIA*'} | Select-Object -First 1 -ExpandProperty Name" >nul 2>&1
if not errorlevel 1 (
    echo NVIDIA GPU detected via PowerShell, but nvidia-smi not found.
    echo.
    echo IMPORTANT: nvidia-smi is required but not found in common locations.
    echo This usually means:
    echo 1. NVIDIA drivers are not installed
    echo 2. NVIDIA drivers are outdated
    echo 3. nvidia-smi is in an unusual location
    echo.
    echo Please:
    echo 1. Download and install the latest NVIDIA drivers from nvidia.com
    echo 2. Restart your computer
    echo 3. Run this script again
    echo.
    choice /C YN /M "Continue anyway (may cause issues later)? (Y/N)"
    if errorlevel 2 (
        pause
        exit /b 1
    )
    echo Continuing without nvidia-smi verification...
    set "GPU_NAME=NVIDIA GPU (detected via PowerShell)"
    set "PYTORCH_VERSION=2.6.0"
    set "CUDA_VERSION=cu124"
    goto :continue_installation
)

:: Final check - no NVIDIA GPU found
echo.
echo ========================================
echo    ERROR: No NVIDIA GPU Detected
echo ========================================
echo.
echo This application requires an NVIDIA GPU with CUDA support.
echo.
echo Troubleshooting steps:
echo 1. Ensure you have an NVIDIA GeForce/RTX/Quadro/Tesla GPU
echo 2. Download and install latest drivers from nvidia.com/drivers
echo 3. Restart your computer after driver installation
echo 4. Make sure your GPU supports CUDA (GTX 600 series or newer)
echo.
echo If you believe this is an error, you can:
echo - Check Device Manager for your GPU
echo - Run 'dxdiag' to see your graphics hardware
echo.
choice /C YN /M "Continue anyway (not recommended)? (Y/N)"
if errorlevel 2 (
    pause
    exit /b 1
)
echo Continuing at your own risk...
set "GPU_NAME=Unknown GPU"
set "PYTORCH_VERSION=2.6.0"
set "CUDA_VERSION=cu124"
goto :continue_installation

:gpu_detected
:: Get GPU info using maximum compatibility methods for old nvidia-smi versions
echo Getting GPU information...

:: Method 1: Use nvidia-smi -L (most compatible, works with very old versions)
for /f "tokens=3*" %%i in ('!NVIDIA_SMI_PATH! -L 2^>nul ^| findstr "GPU 0"') do (
    set GPU_NAME=%%j
    :: Remove "GeForce " prefix if present for cleaner output
    set GPU_NAME=!GPU_NAME:GeForce =!
    goto :gpu_name_found
)

:: Method 2: Fallback to basic nvidia-smi output parsing
if "!GPU_NAME!"=="" (
    echo Trying basic nvidia-smi parsing...
    for /f "tokens=*" %%i in ('!NVIDIA_SMI_PATH! 2^>nul ^| findstr /i "GeForce\|RTX\|GTX\|Quadro\|Tesla"') do (
        set GPU_LINE=%%i
        :: Extract GPU name from the line - look for common GPU identifiers
        echo !GPU_LINE! | findstr /i "RTX.*50" >nul && (
            set GPU_NAME=RTX 50 Series
            goto :gpu_name_found
        )
        echo !GPU_LINE! | findstr /i "RTX.*40" >nul && (
            set GPU_NAME=RTX 40 Series
            goto :gpu_name_found
        )
        echo !GPU_LINE! | findstr /i "RTX.*30" >nul && (
            set GPU_NAME=RTX 30 Series
            goto :gpu_name_found
        )
        echo !GPU_LINE! | findstr /i "RTX.*20" >nul && (
            set GPU_NAME=RTX 20 Series
            goto :gpu_name_found
        )
        echo !GPU_LINE! | findstr /i "GTX.*16" >nul && (
            set GPU_NAME=GTX 16 Series
            goto :gpu_name_found
        )
        echo !GPU_LINE! | findstr /i "GTX.*10" >nul && (
            set GPU_NAME=GTX 10 Series
            goto :gpu_name_found
        )
        echo !GPU_LINE! | findstr /i "GTX" >nul && (
            set GPU_NAME=GTX Series
            goto :gpu_name_found
        )
        echo !GPU_LINE! | findstr /i "RTX" >nul && (
            set GPU_NAME=RTX Series
            goto :gpu_name_found
        )
    )
)

:: Method 3: Last resort - just verify GPU exists
if "!GPU_NAME!"=="" (
    echo Warning: Advanced GPU detection failed, using basic detection...
    !NVIDIA_SMI_PATH! >nul 2>&1
    if not errorlevel 1 (
        set "GPU_NAME=NVIDIA GPU (basic detection)"
    )
)

:gpu_name_found
:: Check if we got GPU name
if "!GPU_NAME!"=="" (
    echo Warning: Could not retrieve GPU name, using default settings
    set "GPU_NAME=NVIDIA GPU (detection failed)"
    set "PYTORCH_VERSION=2.6.0"
    set "CUDA_VERSION=cu124"
    goto :continue_installation
)

:: Clean up GPU name - remove quotes, extra spaces, and parentheses
set "GPU_NAME=!GPU_NAME:"=!"
set "GPU_NAME=!GPU_NAME:(=!"
set "GPU_NAME=!GPU_NAME:)=!"
set "GPU_NAME=!GPU_NAME:  = !"

echo Detected GPU: !GPU_NAME!

:: Determine if RTX 50xx series
echo !GPU_NAME! | findstr /i "RTX.*50\|50.*Series" >nul
if not errorlevel 1 (
    set PYTORCH_VERSION=2.7.0
    set CUDA_VERSION=cu128
    echo RTX 50xx series detected - using PyTorch 2.7.0
) else (
    set PYTORCH_VERSION=2.6.0
    set CUDA_VERSION=cu124
    echo RTX 40xx or older detected - using PyTorch 2.6.0
)

:continue_installation
:: Clone repository to 'source' subfolder to prevent nesting issues
echo [4/8] Downloading Wan2GP source code...
if not exist "source" (
    git clone https://github.com/deepbeepmeep/Wan2GP.git source
    if errorlevel 1 (
        echo Failed to clone repository. Check your internet connection.
        pause
        exit /b 1
    )
)

:: Navigate to source directory before creating virtual environment
cd /d "!INSTALL_DIR!\source"

:: Create virtual environment using absolute path
echo [5/8] Creating Python virtual environment...
set "VENV_PATH=!INSTALL_DIR!\source\wan2gp_env"
echo Creating virtual environment at: !VENV_PATH!

python -m venv "!VENV_PATH!"
if errorlevel 1 (
    echo Failed to create virtual environment.
    pause
    exit /b 1
)

:: Activate virtual environment using absolute path
echo Activating virtual environment...
call "!VENV_PATH!\Scripts\activate.bat"

:: Verify activation worked
if not defined VIRTUAL_ENV (
    echo Error: Virtual environment activation failed
    pause
    exit /b 1
)

echo Virtual environment successfully activated: %VIRTUAL_ENV%

:: Upgrade pip
python -m pip install --upgrade pip

:: Install PyTorch
echo [6/8] Installing PyTorch !PYTORCH_VERSION! with !CUDA_VERSION!...
pip install torch==!PYTORCH_VERSION! torchvision torchaudio --index-url https://download.pytorch.org/whl/test/!CUDA_VERSION!
if errorlevel 1 (
    echo Failed to install PyTorch. Please check your internet connection.
    pause
    exit /b 1
)

:: Install requirements
echo [7/8] Installing Python dependencies...
pip install -r requirements.txt
if errorlevel 1 (
    echo Failed to install requirements. Continuing anyway...
)

:: Install performance enhancements with comprehensive Triton compatibility handling
echo [8/8] Installing performance enhancements with Triton compatibility...

:: Function to install compatible Triton based on PyTorch version
call :install_triton_windows

:: Install SageAttention
echo Installing SageAttention...
pip install sageattention==1.0.6

:: Try to install SageAttention 2 (40% faster)
echo Installing SageAttention 2...
if "!PYTORCH_VERSION!"=="2.7.0" (
    pip install https://github.com/woct0rdho/SageAttention/releases/download/v2.1.1-windows/sageattention-2.1.1+cu128torch2.7.0-cp310-cp310-win_amd64.whl 2>nul || (
        echo SageAttention 2 for PyTorch 2.7.0 failed, using SageAttention 1.0.6
    )
) else (
    pip install https://github.com/woct0rdho/SageAttention/releases/download/v2.1.1-windows/sageattention-2.1.1+cu126torch2.6.0-cp310-cp310-win_amd64.whl 2>nul || (
        echo SageAttention 2 for PyTorch 2.6.0 failed, using SageAttention 1.0.6
    )
)

:: Try to install Flash Attention (may fail on some systems)
echo Installing Flash Attention (optional)...
pip install flash-attn==2.7.2.post1 2>nul || echo Flash Attention installation failed - continuing without it.

:: Create installation flag
echo Installation completed successfully! > "!INSTALL_DIR!\wan2gp_installed.flag"

echo.
echo ========================================
echo    Installation Complete!
echo ========================================
echo.

goto :launch

:: Function to install compatible Triton for Windows
:install_triton_windows
echo Installing Triton for Windows with compatibility handling...

:: Remove any existing Triton installations first
pip uninstall triton triton-windows -y 2>nul

:: Determine compatible Triton version based on PyTorch version
if "!PYTORCH_VERSION!"=="2.7.0" (
    set "TRITON_VERSION=3.3"
    set "TRITON_CONSTRAINT=triton-windows<3.4"
    echo Using Triton 3.3.x for PyTorch 2.7.0
) else (
    set "TRITON_VERSION=3.2"
    set "TRITON_CONSTRAINT=triton-windows<3.3"
    echo Using Triton 3.2.x for PyTorch 2.6.0
)

:: Install triton-windows with version constraint
echo Installing !TRITON_CONSTRAINT!...
pip install "!TRITON_CONSTRAINT!" 2>nul || (
    echo Primary triton-windows installation failed, trying alternatives...
    
    :: Try specific working versions
    if "!PYTORCH_VERSION!"=="2.7.0" (
        pip install triton-windows==3.3.1.post19 2>nul || (
            pip install triton-windows==3.3.0 2>nul || (
                echo Triton 3.3.x failed, falling back to 3.2.x...
                pip install "triton-windows<3.3" 2>nul
            )
        )
    ) else (
        pip install triton-windows==3.2.0.post11 2>nul || (
            pip install triton-windows==3.2.0 2>nul || (
                echo Triton 3.2.x failed, trying 3.1.x...
                pip install triton-windows==3.1.0 2>nul
            )
        )
    )
)

:: Verify Triton installation and test AttrsDescriptor import
echo Verifying Triton installation...
python -c "import triton; print('Triton version:', triton.__version__)" 2>nul || (
    echo Triton import failed, attempting manual installation...
    goto :manual_triton_install
)

:: Test for AttrsDescriptor compatibility
python -c "from triton.backends.compiler import AttrsDescriptor; print('AttrsDescriptor found in backends.compiler')" 2>nul && (
    echo Triton compatibility verified successfully!
    goto :triton_success
)

python -c "from triton.compiler.compiler import AttrsDescriptor; print('AttrsDescriptor found in compiler.compiler')" 2>nul && (
    echo Triton compatibility verified successfully!
    goto :triton_success
)

echo AttrsDescriptor not found, attempting compatibility fix...

:manual_triton_install
:: Manual installation of known working versions
echo Attempting manual Triton installation with known working versions...

:: Try pre-built wheels from HuggingFace for specific PyTorch versions
if "!PYTORCH_VERSION!"=="2.6.0" (
    echo Trying pre-built Triton wheel for PyTorch 2.6.0...
    pip install https://huggingface.co/r4ziel/xformers_pre_built/resolve/main/triton-2.0.0-cp310-cp310-win_amd64.whl 2>nul || (
        echo Pre-built wheel failed, trying triton-windows 3.1.x...
        pip install triton-windows==3.1.0 2>nul
    )
) else (
    echo Trying triton-windows 3.2.x for PyTorch 2.7.0...
    pip install triton-windows==3.2.0.post11 2>nul
)

:: Final verification
python -c "import triton; print('Triton manually installed, version:', triton.__version__)" 2>nul || (
    echo Warning: All Triton installation attempts failed.
    echo The application will run without Triton optimizations.
    goto :triton_failed
)

:: Test AttrsDescriptor one more time
python -c "from triton.backends.compiler import AttrsDescriptor" 2>nul || (
    python -c "from triton.compiler.compiler import AttrsDescriptor" 2>nul || (
        echo Warning: AttrsDescriptor still not found after manual installation.
        echo This may cause compilation issues but basic functionality should work.
        goto :triton_failed
    )
)

:triton_success
echo Triton installation and compatibility verification successful!
goto :eof

:triton_failed
echo Triton installation completed with warnings.
echo The application will function but may have reduced performance.
goto :eof

:launch
:: Always use the user profile directory for launch, regardless of script location
set "INSTALL_DIR=%userprofile%\Wan2GP"
set "SOURCE_DIR=%INSTALL_DIR%\source"
set "VENV_PATH=%INSTALL_DIR%\source\wan2gp_env"

:: Check if installation exists
if not exist "!SOURCE_DIR!" (
    echo Error: Wan2GP installation not found at !SOURCE_DIR!
    echo Please delete !INSTALL_DIR! and run this script as administrator to reinstall.
    pause
    exit /b 1
)

:: Check if virtual environment exists USING ABSOLUTE PATH
if not exist "!VENV_PATH!\Scripts\activate.bat" (
    echo Error: Virtual environment not found at !VENV_PATH!
    echo The installation appears corrupted.
    echo Please delete !INSTALL_DIR! and run this script as administrator to reinstall.
    pause
    exit /b 1
)

echo Starting Wan2GP from: !SOURCE_DIR!
echo Using virtual environment: !VENV_PATH!
echo.

:: Navigate to source directory
cd /d "!SOURCE_DIR!" || (
    echo Error: Could not navigate to !SOURCE_DIR!
    pause
    exit /b 1
)

echo Activating virtual environment...

:: Activate using absolute path and verify it worked correctly
call "!VENV_PATH!\Scripts\activate.bat"

:: Verify the environment is activated and using the correct path
if not defined VIRTUAL_ENV (
    echo Error: Failed to activate virtual environment.
    echo Expected path: !VENV_PATH!
    pause
    exit /b 1
)

:: Additional verification - check if paths match (normalize paths for comparison)
set "EXPECTED_NORM=!VENV_PATH!"
set "ACTUAL_NORM=%VIRTUAL_ENV%"
:: Convert to lowercase for comparison
for %%i in ("!EXPECTED_NORM!") do set "EXPECTED_NORM=%%~fi"
for %%i in ("!ACTUAL_NORM!") do set "ACTUAL_NORM=%%~fi"

if not "!EXPECTED_NORM!"=="!ACTUAL_NORM!" (
    echo Warning: Virtual environment path mismatch!
    echo Expected: !EXPECTED_NORM!
    echo Actual:   !ACTUAL_NORM!
    echo.
    echo This suggests the virtual environment was created in the wrong location.
    echo Please delete !INSTALL_DIR! and reinstall as administrator.
    pause
    exit /b 1
)

echo Virtual environment activated: %VIRTUAL_ENV%
echo Current directory: %CD%
echo.

:: Perform comprehensive runtime Triton compatibility check and fix
call :runtime_triton_check

echo The application will open in your web browser at http://localhost:7860
echo Close this window to stop the application.
echo.

:: Launch with optimal settings and automatic fallback handling
echo Attempting to start with SageAttention 2 and compilation...
python wgp.py --open-browser --compile --attention sage2 2>nul || (
    echo SageAttention 2 failed, trying SageAttention...
    python wgp.py --open-browser --compile --attention sage 2>nul || (
        echo SageAttention failed, trying with compilation only...
        python wgp.py --open-browser --compile 2>nul || (
            echo Compilation failed due to Triton issues, running without optimization...
            python wgp.py --open-browser 2>nul || (
                echo All launch attempts failed. Attempting final Triton fix...
                call :emergency_triton_fix
                
                echo Retrying launch without compilation...
                python wgp.py --open-browser || (
                    echo.
                    echo ========================================
                    echo    Launch Failed - Manual Intervention Required
                    echo ========================================
                    echo.
                    echo The application failed to start. This could be due to:
                    echo 1. Triton compatibility issues
                    echo 2. Missing dependencies
                    echo 3. GPU driver problems
                    echo.
                    echo To troubleshoot:
                    echo 1. Check the error messages above
                    echo 2. Try running: python wgp.py --help
                    echo 3. Check GPU drivers are up to date
                    echo 4. Reinstall by deleting !INSTALL_DIR! and running this script again
                    echo.
                    pause
                    exit /b 1
                )
            )
        )
    )
)

pause
goto :eof

:: Function for runtime Triton compatibility check
:runtime_triton_check
echo Performing comprehensive runtime Triton compatibility check...

:: Check if Triton is installed at all
python -c "import triton" 2>nul || (
    echo Triton not found at runtime. Installing emergency fallback...
    call :emergency_triton_fix
    goto :eof
)

:: Check for AttrsDescriptor in both possible locations
python -c "from triton.backends.compiler import AttrsDescriptor; print('Runtime check: AttrsDescriptor found in backends.compiler')" 2>nul && (
    echo Runtime Triton compatibility verified!
    goto :eof
)

python -c "from triton.compiler.compiler import AttrsDescriptor; print('Runtime check: AttrsDescriptor found in compiler.compiler')" 2>nul && (
    echo Runtime Triton compatibility verified!
    goto :eof
)

echo Runtime Triton compatibility issue detected. Attempting automatic fix...

:: Get current PyTorch version to determine compatible Triton
for /f "tokens=*" %%i in ('python -c "import torch; print(torch.__version__.split('+')[0])" 2^>nul') do set DETECTED_PYTORCH=%%i

echo Detected PyTorch version: !DETECTED_PYTORCH!

:: Install compatible Triton based on detected PyTorch version
if "!DETECTED_PYTORCH!"=="2.7.0" (
    echo Installing Triton 3.3.x for PyTorch 2.7.0...
    pip uninstall triton triton-windows -y 2>nul
    pip install "triton-windows<3.4" 2>nul || pip install triton-windows==3.3.1.post19 2>nul
) else if "!DETECTED_PYTORCH!"=="2.6.0" (
    echo Installing Triton 3.2.x for PyTorch 2.6.0...
    pip uninstall triton triton-windows -y 2>nul
    pip install "triton-windows<3.3" 2>nul || pip install triton-windows==3.2.0.post11 2>nul
) else (
    echo Installing general compatible Triton...
    pip uninstall triton triton-windows -y 2>nul
    pip install triton-windows==3.1.0 2>nul
)

:: Final verification
python -c "from triton.backends.compiler import AttrsDescriptor" 2>nul || (
    python -c "from triton.compiler.compiler import AttrsDescriptor" 2>nul || (
        echo Warning: Runtime Triton fix unsuccessful.
        echo The application may experience compilation issues.
    )
)

goto :eof

:: Emergency Triton fix function
:emergency_triton_fix
echo Performing emergency Triton installation...

:: Remove all Triton installations
pip uninstall triton triton-windows -y 2>nul

:: Try multiple known working versions in order of preference
pip install triton-windows==3.1.0 2>nul || (
    pip install triton-windows==3.0.0 2>nul || (
        pip install https://huggingface.co/r4ziel/xformers_pre_built/resolve/main/triton-2.0.0-cp310-cp310-win_amd64.whl 2>nul || (
            echo Emergency Triton installation failed.
            echo Continuing without Triton optimizations.
        )
    )
)

goto :eof
