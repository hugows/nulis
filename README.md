# nulis

A modern, colorful file listing tool written in Zig that displays files in a beautiful nushell-style table format.

```
~/vibe/nulis ls
╭───┬───────────┬──────┬──────────┬────────────────╮
│ # │ name      │ type │   size   │    modified    │
├───┼───────────┼──────┼──────────┼────────────────┤
│ 0 │ nulis     │ file │   1.4 MB │ 2 minutes ago  │
│ 1 │ nulis.zig │ file │  11.4 kB │ 3 minutes ago  │
│ 2 │ README.md │ file │   4.5 kB │ 4 minutes ago  │
│ 3 │ build.sh  │ file │    214 B │ 6 hours ago    │
╰───┴───────────┴──────┴──────────┴────────────────╯
```

## Features

- 🎨 **Colored output** - Directories in cyan, executables in red, symlinks in magenta
- 📊 **Nushell-style table** - Beautiful Unicode box-drawing characters
- ⏰ **Sorted by time** - Most recently modified files appear first
- 🙈 **Hide hidden files** - By default (use `-a` to show all)
- 📏 **Human-readable sizes** - KB, MB, GB formatting
- ⏱️ **Relative timestamps** - "5 minutes ago", "2 days ago", etc.
- 🔧 **Dynamic column widths** - Adapts to your file names

## Installation

### Homebrew (recommended)

```bash
brew tap hugows/tap
brew install nulis
```

Or install directly without tapping:

```bash
brew install hugows/tap/nulis
```

### Build from source

**Prerequisites:** [Zig 0.15.1](https://ziglang.org/download/) or later

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

# List a specific directory
nulis /tmp
nulis ~/Documents
nulis /var/log

# Show all files including hidden ones
nulis -a
nulis --all

# Output as CSV (great for data processing)
nulis --csv
nulis -c

# Plain text output (auto-enabled when piped)
nulis --plain
nulis -p

# Customize colors with theme
nulis --theme=34,31,95,92

# Combine options with paths
nulis -a /etc           # Show all files in /etc
nulis --csv ~/Projects  # List ~/Projects in CSV format
nulis -ac /var/log      # All files in /var/log as CSV
nulis --theme=96,91,95,92 ~/Documents  # Custom colors for ~/Documents

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

### Default Colors

- **Directories**: Cyan (bright blue)
- **Executables**: Light red
- **Symlinks**: Magenta
- **Regular files**: Default terminal color
- **Headers & indices**: Green

### Customizing Colors

You can customize the color scheme using the `--theme` flag with comma-separated ANSI color codes:

```bash
# Custom theme: directory, executable, symlink, header
nulis --theme=34,31,35,33
```

Common ANSI color codes:
- `30`-`37`: black, red, green, yellow, blue, magenta, cyan, white
- `90`-`97`: bright versions (e.g., `96`=bright cyan, `91`=bright red)

**Examples:**
```bash
# Default theme (cyan dirs, bright red executables, magenta links, green headers)
nulis --theme=96,91,95,92

# Blue directories, red executables
nulis --theme=34,31,95,92

# All bright colors
nulis --theme=94,91,95,93
```

## License

MIT License - feel free to use and modify as you wish!

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

---

🤖 Built with [Claude Code](https://claude.com/claude-code)
