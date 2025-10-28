# nulis

A modern, colorful file listing tool written in Zig that displays files in a beautiful nushell-style table format.

<img width="1634" height="1236" alt="CleanShot 2025-10-28 at 12 32 26@2x" src="https://github.com/user-attachments/assets/d6de2402-a2ed-4708-ae75-e4a1e2a313b7" />

## Features

- 🎨 **Colored output** - Directories in cyan, executables in red, symlinks in magenta
- 📊 **Nushell-style table** - Beautiful Unicode box-drawing characters
- ⏰ **Sorted by time** - Most recently modified files appear first
- 🙈 **Hide hidden files** - By default (use `-a` to show all)
- 📏 **Human-readable sizes** - KB, MB, GB formatting
- ⏱️ **Relative timestamps** - "5 minutes ago", "2 days ago", etc.
- 🔧 **Dynamic column widths** - Adapts to your file names

## Installation

### Prerequisites

- [Zig 0.15.1](https://ziglang.org/download/) or later

### Build from source

```bash
git clone https://github.com/hugows/nulis.git
cd nulis
./build.sh
```

This will compile `nulis` and install it to `~/bin/nulis`. Make sure `~/bin` is in your PATH.

## Usage

```bash
# List files in current directory (hides hidden files by default)
nulis

# Show all files including hidden ones
nulis -a
nulis --all

# Output as CSV (great for data processing)
nulis --csv
nulis -c

# Plain text output (auto-enabled when piped)
nulis --plain
nulis -p

# Combine options
nulis -ac        # Show all files in CSV format

# Show help
nulis -h
nulis --help
```

## Set as default `ls` command

You probably want to use `nulis` as your default file listing command. Add this to your shell config:

**For Zsh** (`~/.zshrc`):
```bash
alias ls=nulis
```

**For Bash** (`~/.bashrc`):
```bash
alias ls=nulis
```

**For Fish** (`~/.config/fish/config.fish`):
```fish
alias ls=nulis
```

Then reload your shell or run `source ~/.zshrc` (or equivalent for your shell).

## Examples

```bash
# Basic listing
$ nulis
╭───┬──────────┬──────┬────────┬────────────────╮
│ # │ name     │ type │  size  │    modified    │
├───┼──────────┼──────┼────────┼────────────────┤
│ 0 │ build.sh │ file │  214 B │ 5 minutes ago  │
│ 1 │ nulis    │ file │ 1.4 MB │ 2 minutes ago  │
│ 2 │ nulis.zig│ file │ 8.1 kB │ 1 minute ago   │
╰───┴──────────┴──────┴────────┴────────────────╯

# Show all files including hidden ones
$ nulis -a
╭───┬──────────┬──────┬────────┬────────────────╮
│ # │ name     │ type │  size  │    modified    │
├───┼──────────┼──────┼────────┼────────────────┤
│ 0 │ .git     │ dir  │  160 B │ 10 minutes ago │
│ 1 │ .gitignore│ file │   89 B │ 15 minutes ago │
│ 2 │ build.sh │ file │  214 B │ 5 minutes ago  │
│ 3 │ nulis    │ file │ 1.4 MB │ 2 minutes ago  │
│ 4 │ nulis.zig│ file │ 8.1 kB │ 1 minute ago   │
╰───┴──────────┴──────┴────────┴────────────────╯

# CSV output for data processing
$ nulis --csv
type,name,size,modified
file,nulis,1462232,1761674006599309545
file,nulis.zig,10318,1761673980964378600
file,README.md,3691,1761668703022624416
file,build.sh,214,1761662902741192631

# Pipe to grep (automatically uses plain text)
$ nulis | grep README
README.md

# CSV with grep to filter by type
$ nulis --csv | grep "^dir"
dir,.git,448,1761673898588605893
dir,.claude,96,1761673630279137747

# Save CSV to file for spreadsheet
$ nulis --csv > files.csv
```

## Color Scheme

- **Directories**: Cyan (bright blue)
- **Executables**: Light red
- **Symlinks**: Magenta
- **Regular files**: Default terminal color
- **Headers & indices**: Green

## License

MIT License - feel free to use and modify as you wish!

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

---

🤖 Built with [Claude Code](https://claude.com/claude-code)
