# FilteredTreeSync.sh

**Selective Tree-Based File Synchronization Script**

---

## 🌳 Overview

**FilteredTreeSync.sh** is a professional Bash script that:

- Selectively **copies** files matching a specific pattern
- **Preserves** the full **directory tree** structure
- Supports **parallel copying** for high speed
- **Verifies** every copied file for integrity
- Optionally **deletes the source files** only after successful verification
- Has a **dry-run** mode to simulate the entire process without modifying anything
- Supports **auto-confirm** mode to skip manual confirmation prompts
- Automatically **excludes destination directories** from search and deletion to avoid accidental overwrites
- Provides **colorful**, clean console output with real-time progress bars

---

## 🌐 Features

- ✨ File pattern filtering (e.g., `"*.pdf"`, `"*.jpg"`, etc.)
- ✨ Full directory tree preservation
- ✨ Multi-threaded (parallel) copy operations
- ✨ Real-time progress bars for copy and verification
- ✨ Optional source deletion after successful copy and verify
- ✨ Dry-run simulation mode to preview operations safely
- ✨ Auto-confirm mode to skip manual keypress confirmation
- ✨ Automatic exclusion of destination directories
- ✨ Strict bash error handling (`set -euo pipefail`)
- ✨ Clear and colorful terminal output

---

## 🔧 Installation

No installation required. Simply download the script and make it executable:

```bash
chmod +x FilteredTreeSync.sh
```

Place it somewhere in your `PATH` if you want global access, e.g., `/usr/local/bin`.

---

## 📚 Usage

```bash
./FilteredTreeSync.sh <source_directory> <destination_directory> <file_pattern> [--deletesources] [--dry-run] [--autoconfirm]
```

### Parameters:

- `source_directory` : Directory to search for files
- `destination_directory` : Directory where files will be copied
- `file_pattern` : Pattern to match files (e.g., `"*.pdf"`, `"*.docx"`)
- `--deletesources` (optional) : Deletes the source files **after** successful copy and verification
- `--dry-run` (optional) : Simulates the entire operation without actually copying or deleting files
- `--autoconfirm` (optional) : Skips keypress confirmation after summary and proceeds automatically

### Examples:

**Simple copy with structure preservation:**

```bash
./FilteredTreeSync.sh /home/user/docs /backup/docs "*.pdf"
```

**Copy and delete source files after successful verification:**

```bash
./FilteredTreeSync.sh /home/user/docs /backup/docs "*.pdf" --deletesources
```

**Dry-run (simulate operations only):**

```bash
./FilteredTreeSync.sh /home/user/docs /backup/docs "*.pdf" --dry-run
```

**Dry-run with auto-confirm:**

```bash
./FilteredTreeSync.sh /home/user/docs /backup/docs "*.pdf" --dry-run --autoconfirm
```

**Dry-run with delete simulation and auto-confirm:**

```bash
./FilteredTreeSync.sh /home/user/docs /backup/docs "*.pdf" --deletesources --dry-run --autoconfirm
```

---

## 💡 Tips

- Always run a `--dry-run` first if you're unsure about the source files!
- Destination directories are automatically excluded from being copied or deleted.
- You can easily integrate it into cron jobs or backup scripts.
- Customize parallel job count by adjusting the script (currently 4 jobs in parallel).

---

## 🎨 Example Output

```bash
    🌳  FilteredTreeSync
      /\
     /  \    Filter + Copy + Preserve Directory Structure
    /____\

🔹 Searching for files matching pattern "*.pdf" in "/home/user/docs"...
🔹 Found 125 files.

🔹 Starting copy...
[#####################---------] 62% (78/125)
🔹 Copying complete.

🔹 Verifying copied files...
[##############################] 100% (125/125)
🔹 Verification successful: All files copied correctly.

🔹 Would delete the following files after successful verification:
Would delete: /home/user/docs/report1.pdf
Would delete: /home/user/docs/summary2.pdf
Would delete: /home/user/docs/final3.pdf

🔹 ✨ Dry-run completed: no files were copied; source files would have been deleted.

🔹 Done.
```

---

## 👨‍💼 Author

**bitranox**

---

## 🌐 License

This project is licensed under the MIT License.

---

## 🎉 Contributions

Feel free to suggest improvements or submit pull requests!

---

## ✨ Future Ideas

- Add automatic logging to file
- Add email notifications after sync
- Add resume support after interruptions

---

Enjoy using **FilteredTreeSync.sh** and keep your file trees synchronized safely and smartly! 🌳

