# Synchronize launcher photos on Windows

`tools/sync-photos.ps1` prepares copies of pictures from a local folder and replaces the launcher's wallpaper collection over ADB. Original files are not modified. Videos and other unsupported files are ignored; supported image extensions are JPEG, PNG, WebP, HEIC and HEIF. Only files directly inside the selected folder are considered.

The script checks the address, ADB authorization, expected model and device, image count, image preparation, free TV storage and the existing theme before transferring. It keeps the existing theme configuration, downloads a local backup of the previous collection and attempts to restore it if the transfer fails. A failed restore still requires manual recovery. Temporary copies and backups are stored under the ignored `work/photo-sync/` directory; they may contain personal photos and should remain private.

## Setup

1. Install Python, Android platform-tools (`adb`) and ensure `adb` is on `PATH`.
2. From the repository root, create the Python environment and install both sets of requirements:

   ```powershell
   python -m venv tools\venv
   tools\venv\Scripts\python.exe -m pip install -r tools\requirements.txt -r tools\requirements-photos.txt
   ```

3. Install this fork's launcher and configure a theme with a `config.json` and at least one wallpaper. The launcher and script require an authorized ADB connection. Enable debugging only when needed, authorize the computer on the TV, and turn debugging off afterwards.
4. Obtain the target TV's `ro.product.model` and `ro.product.device` values over your authorized ADB connection. Supply them explicitly on every run so that the script can refuse a different device. Keep these values and your TV address out of public commits.

## Preview and synchronize

Replace the placeholders with your own values. The preview connects to the TV and prepares local image copies, but does not change the TV.

```powershell
.\tools\sync-photos.ps1 -PhotoDirectory '<photo folder>' -TvAddress '<tv ip>' -ExpectedModel '<model>' -ExpectedDevice '<device>' -Preview
.\tools\sync-photos.ps1 -PhotoDirectory '<photo folder>' -TvAddress '<tv ip>' -ExpectedModel '<model>' -ExpectedDevice '<device>'
```

The script accepts at most 1,000 images. For more than 100, it checks that the installed launcher reports `versionName=3.4-local1000.1`; otherwise it stops before sending photos. Build and install this fork's launcher before synchronizing a larger collection. Up to 100 images are allowed on an older launcher. The script currently expects ADB on port 5555 and a readable launcher theme directory; it may not work on every TV firmware.
