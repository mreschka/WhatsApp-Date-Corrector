# PowerShell Script to Correct WhatsApp Dates

A PowerShell script to fix the timestamps ("Date created" and "Date modified") of WhatsApp media files, using metadata or, as a fallback, the date from the filename.

## The Problem

Many people know the issue: after a backup or copying WhatsApp images and videos, the file timestamp reflects the time of the copy, not the original date the photo or video was taken. This messes up the sorting in photo galleries. This script solves the problem by restoring the correct timestamps.

## Features

The script uses an intelligent priority system to find the best possible timestamp:

1.  **Priority 1: Metadata**
    * The script first reads the file's metadata, looking for "Date taken" (for photos/videos) or "Media created".
    * If a valid timestamp is found, it is used as the precise source.
    * An update is performed if the file's `CreationTime` or `LastWriteTime` does not exactly match this timestamp.

2.  **Priority 2: Filename (Fallback)**
    * Only if no valid metadata is found, the script analyzes the filename for the typical WhatsApp pattern (`XXX-YYYYMMDD-WAnnnn.zzz`).
    * The time is generated based on the sequence number (e.g., `WA0000` -> `10:00 AM`).
    * An update is only performed if the **day** of the file's timestamp differs from the day in the filename, to avoid overwriting an already correct time.

* **Recursive Search:** Searches all subfolders of the specified start directory.
* **Dry Run:** Enabled by default. It only shows what changes would be made without actually modifying any files.

## How to Use

1.  **Save the script:** Save the `WhatsApp-Date-Corrector.ps1` script to your computer.
2.  **Open PowerShell:** Open PowerShell as an Administrator.
3.  **Adjust Execution Policy (one-time):** To allow local scripts to run, execute the following command:
    ```powershell
    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
    ```
4.  **Navigate to the script:** Use `cd` to navigate to the folder where you saved the script.
    ```powershell
    cd C:\Path\to\your\script
    ```
5.  **Start a Dry Run (recommended):** Run the script with the default `-DryRun` switch, providing the path to your WhatsApp folder.
    ```powershell
    .\WhatsApp-Date-Corrector.ps1 -DirectoryPath "C:\Path\to\your\pictures"
    ```
6.  **Start the Live Run:** If the output from the dry run looks correct, run the command again, setting `-DryRun` to `$false`.
    ```powershell
    .\WhatsApp-Date-Corrector.ps1 -DirectoryPath "C:\Path\to\your\pictures" -DryRun:$false
    ```

---

## Acknowledgements

This script is the result of a productive collaboration between **Markus Reschka**, who provided the idea and thorough testing, and **Gemini**, which assisted in the step-by-step development and debugging of the code.

---

## License

This project is licensed under the MIT License.

**MIT License**

Copyright (c) 2024 Gemini

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
