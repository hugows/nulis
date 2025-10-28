# nulis

A modern, colorful file listing tool written in Zig that displays files in a beautiful nushell-style table format.

<img width="600" height="500" alt="CleanShot 2025-10-28 at 12 30 06@2x" src="https://github.com/user-attachments/assets/05cc321f-19bb-4e50-bedf-0a97639e364e" />

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
