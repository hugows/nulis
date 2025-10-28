const std = @import("std");

const FileEntry = struct {
    name: []const u8,
    kind: std.fs.File.Kind,
    size: u64,
    modified: i128,
    mode: std.fs.File.Mode,
};

const Options = struct {
    show_hidden: bool = false,
    sort_by_time: bool = true, // true = most recent first
    plain: bool = false, // plain text output (no table, no colors)
    csv: bool = false, // CSV output format
    path: []const u8 = ".", // directory path to list
};

// ANSI color codes
const Color = struct {
    const reset = "\x1b[0m";
};

const ColorConfig = struct {
    directory: []const u8,
    executable: []const u8,
    symlink: []const u8,
    header: []const u8,
    regular: []const u8,

    fn default() ColorConfig {
        return ColorConfig{
            .directory = "\x1b[96m",    // cyan
            .executable = "\x1b[91m",   // light red
            .symlink = "\x1b[95m",      // magenta
            .header = "\x1b[92m",       // green
            .regular = "\x1b[0m",       // reset/default
        };
    }

    fn getConfigPath(allocator: std.mem.Allocator) ![]const u8 {
        const home = std.posix.getenv("HOME") orelse return error.NoHomeDir;
        return std.fs.path.join(allocator, &[_][]const u8{ home, ".config", "nulis", "config" });
    }

    fn fromFile(allocator: std.mem.Allocator) !ColorConfig {
        var config = ColorConfig.default();

        const config_path = getConfigPath(allocator) catch return config;
        defer allocator.free(config_path);

        const file = std.fs.openFileAbsolute(config_path, .{}) catch return config;
        defer file.close();

        const content = file.readToEndAlloc(allocator, 1024 * 1024) catch return config;
        defer allocator.free(content);

        var lines = std.mem.splitScalar(u8, content, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;

            var parts = std.mem.splitScalar(u8, trimmed, '=');
            const key = std.mem.trim(u8, parts.next() orelse continue, " \t");
            const value = std.mem.trim(u8, parts.next() orelse continue, " \t");

            if (value.len == 0) continue;

            var color_buf: [16]u8 = undefined;
            const color_code = std.fmt.bufPrint(&color_buf, "\x1b[{s}m", .{value}) catch continue;

            const color_copy = allocator.dupe(u8, color_code) catch continue;

            if (std.mem.eql(u8, key, "directory")) {
                config.directory = color_copy;
            } else if (std.mem.eql(u8, key, "executable")) {
                config.executable = color_copy;
            } else if (std.mem.eql(u8, key, "symlink")) {
                config.symlink = color_copy;
            } else if (std.mem.eql(u8, key, "header")) {
                config.header = color_copy;
            }
        }

        return config;
    }
};

fn getColorForEntry(entry: FileEntry, config: *const ColorConfig) []const u8 {
    switch (entry.kind) {
        .directory => return config.directory,
        .sym_link => return config.symlink,
        .file => {
            // Check if executable (owner, group, or other has execute permission)
            const is_executable = (entry.mode & 0o111) != 0;
            if (is_executable) {
                return config.executable;
            }
            return config.regular;
        },
        else => return config.regular,
    }
}

fn formatSize(size: u64, buf: []u8) ![]const u8 {
    if (size < 1024) {
        return std.fmt.bufPrint(buf, "{d} B", .{size});
    } else if (size < 1024 * 1024) {
        const kb = @as(f64, @floatFromInt(size)) / 1024.0;
        return std.fmt.bufPrint(buf, "{d:.1} kB", .{kb});
    } else if (size < 1024 * 1024 * 1024) {
        const mb = @as(f64, @floatFromInt(size)) / (1024.0 * 1024.0);
        return std.fmt.bufPrint(buf, "{d:.1} MB", .{mb});
    } else {
        const gb = @as(f64, @floatFromInt(size)) / (1024.0 * 1024.0 * 1024.0);
        return std.fmt.bufPrint(buf, "{d:.1} GB", .{gb});
    }
}

fn formatTime(modified: i128, now: i128, buf: []u8) ![]const u8 {
    const diff_ns = now - modified;
    const diff_sec = @divFloor(diff_ns, std.time.ns_per_s);

    if (diff_sec < 60) {
        return std.fmt.bufPrint(buf, "{d} seconds ago", .{diff_sec});
    } else if (diff_sec < 3600) {
        const mins = @divFloor(diff_sec, 60);
        return std.fmt.bufPrint(buf, "{d} minute{s} ago", .{ mins, if (mins == 1) "" else "s" });
    } else if (diff_sec < 86400) {
        const hours = @divFloor(diff_sec, 3600);
        return std.fmt.bufPrint(buf, "{d} hour{s} ago", .{ hours, if (hours == 1) "" else "s" });
    } else if (diff_sec < 604800) {
        const days = @divFloor(diff_sec, 86400);
        return std.fmt.bufPrint(buf, "{d} day{s} ago", .{ days, if (days == 1) "" else "s" });
    } else if (diff_sec < 2592000) {
        const weeks = @divFloor(diff_sec, 604800);
        return std.fmt.bufPrint(buf, "{d} week{s} ago", .{ weeks, if (weeks == 1) "" else "s" });
    } else if (diff_sec < 31536000) {
        const months = @divFloor(diff_sec, 2592000);
        return std.fmt.bufPrint(buf, "{d} month{s} ago", .{ months, if (months == 1) "" else "s" });
    } else {
        const years = @divFloor(diff_sec, 31536000);
        return std.fmt.bufPrint(buf, "{d} year{s} ago", .{ years, if (years == 1) "" else "s" });
    }
}

fn isHidden(name: []const u8) bool {
    return name.len > 0 and name[0] == '.';
}

fn sortByModifiedDesc(_: void, a: FileEntry, b: FileEntry) bool {
    return a.modified > b.modified;
}

fn openConfigEditor() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config_path = try ColorConfig.getConfigPath(allocator);
    defer allocator.free(config_path);

    // Create config directory if it doesn't exist
    const config_dir = std.fs.path.dirname(config_path) orelse return error.InvalidPath;
    std.fs.makeDirAbsolute(config_dir) catch |err| {
        if (err != error.PathAlreadyExists) return err;
    };

    // Create default config if it doesn't exist
    const file_exists = blk: {
        const file = std.fs.openFileAbsolute(config_path, .{ .mode = .read_only }) catch |err| {
            if (err == error.FileNotFound) {
                break :blk false;
            } else {
                return err;
            }
        };
        file.close();
        break :blk true;
    };

    if (!file_exists) {
        const default_content =
            \\# nulis color configuration
            \\# ANSI color codes: https://en.wikipedia.org/wiki/ANSI_escape_code#Colors
            \\#
            \\# Common colors:
            \\# 30=black, 31=red, 32=green, 33=yellow, 34=blue, 35=magenta, 36=cyan, 37=white
            \\# 90=bright black, 91=bright red, 92=bright green, 93=bright yellow
            \\# 94=bright blue, 95=bright magenta, 96=bright cyan, 97=bright white
            \\
            \\directory=96
            \\executable=91
            \\symlink=95
            \\header=92
            \\
        ;

        const new_file = try std.fs.createFileAbsolute(config_path, .{});
        defer new_file.close();
        try new_file.writeAll(default_content);
    }

    // Open in editor
    const editor = std.posix.getenv("EDITOR") orelse std.posix.getenv("VISUAL") orelse "vi";

    var child = std.process.Child.init(&[_][]const u8{ editor, config_path }, allocator);
    _ = try child.spawnAndWait();

    std.debug.print("Config saved to: {s}\n", .{config_path});
}

fn parseArgs() !Options {
    var opts = Options{};
    var args = std.process.args();

    // Skip program name
    _ = args.skip();

    while (args.next()) |arg| {
        if (arg.len == 0) continue;

        // Long form flags
        if (std.mem.eql(u8, arg, "--all")) {
            opts.show_hidden = true;
        } else if (std.mem.eql(u8, arg, "--plain")) {
            opts.plain = true;
        } else if (std.mem.eql(u8, arg, "--csv")) {
            opts.csv = true;
        } else if (std.mem.eql(u8, arg, "--config")) {
            try openConfigEditor();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "--help")) {
            std.debug.print("Usage: nulis [OPTIONS] [PATH]\n", .{});
            std.debug.print("Options:\n", .{});
            std.debug.print("  -a, --all       Show hidden files (files starting with .)\n", .{});
            std.debug.print("  -p, --plain     Plain text output (no table, no colors)\n", .{});
            std.debug.print("  -c, --csv       CSV output format\n", .{});
            std.debug.print("      --config    Edit color configuration file\n", .{});
            std.debug.print("  -h, --help      Show this help message\n", .{});
            std.debug.print("\nArguments:\n", .{});
            std.debug.print("  PATH            Directory to list (default: current directory)\n", .{});
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "-h")) {
            // Show help only for standalone -h
            std.debug.print("Usage: nulis [OPTIONS] [PATH]\n", .{});
            std.debug.print("Options:\n", .{});
            std.debug.print("  -a, --all       Show hidden files (files starting with .)\n", .{});
            std.debug.print("  -p, --plain     Plain text output (no table, no colors)\n", .{});
            std.debug.print("  -c, --csv       CSV output format\n", .{});
            std.debug.print("      --config    Edit color configuration file\n", .{});
            std.debug.print("  -h, --help      Show this help message\n", .{});
            std.debug.print("\nArguments:\n", .{});
            std.debug.print("  PATH            Directory to list (default: current directory)\n", .{});
            std.process.exit(0);
        } else if (arg[0] == '-' and arg.len > 1 and arg[1] != '-') {
            // Short form flags (can be grouped like -lah)
            for (arg[1..]) |flag_char| {
                switch (flag_char) {
                    'a' => opts.show_hidden = true,
                    'p' => opts.plain = true,
                    'c' => opts.csv = true,
                    // Silently ignore unknown flags including 'h' in groups (like ls does)
                    else => {},
                }
            }
        } else if (arg[0] != '-') {
            // Non-flag argument is treated as path
            opts.path = arg;
        }
        // Silently ignore unknown long flags
    }

    return opts;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) {
        std.debug.print("> [error] memory leaked\n", .{});
    };

    const allocator = gpa.allocator();
    const opts = try parseArgs();

    // Load color configuration
    const color_config = try ColorConfig.fromFile(allocator);

    // Detect if output is to a terminal (for colors and table formatting)
    // Check stdout since that's what gets piped
    const stdout_is_tty = std.posix.isatty(std.posix.STDOUT_FILENO);
    const use_plain = opts.plain or !stdout_is_tty;

    var dir = try std.fs.cwd().openDir(opts.path, .{ .iterate = true });
    defer dir.close();

    var entries: std.ArrayList(FileEntry) = .{};
    defer {
        for (entries.items) |entry| {
            allocator.free(entry.name);
        }
        entries.deinit(allocator);
    }

    var iter = dir.iterate();
    const now = std.time.nanoTimestamp();

    while (try iter.next()) |entry| {
        // Skip hidden files unless --all flag is set
        if (!opts.show_hidden and isHidden(entry.name)) {
            continue;
        }

        const stat = dir.statFile(entry.name) catch continue;
        const name_copy = try allocator.dupe(u8, entry.name);
        try entries.append(allocator, .{
            .name = name_copy,
            .kind = entry.kind,
            .size = stat.size,
            .modified = stat.mtime,
            .mode = stat.mode,
        });
    }

    if (entries.items.len == 0) return;

    // Sort by modification time (most recent first)
    if (opts.sort_by_time) {
        std.mem.sort(FileEntry, entries.items, {}, sortByModifiedDesc);
    }

    // CSV output format
    if (opts.csv) {
        var buf: [4096]u8 = undefined;
        // CSV header
        const header = "type,name,size,modified\n";
        _ = try std.posix.write(std.posix.STDOUT_FILENO, header);

        for (entries.items) |entry| {
            const type_str = switch (entry.kind) {
                .directory => "dir",
                .sym_link => "link",
                .file => "file",
                else => "other",
            };

            const line = try std.fmt.bufPrint(&buf, "{s},{s},{d},{d}\n", .{
                type_str,
                entry.name,
                entry.size,
                entry.modified
            });
            _ = try std.posix.write(std.posix.STDOUT_FILENO, line);
        }
        return;
    }

    // Simple plain text output when piped or --plain flag
    if (use_plain) {
        var buf: [4096]u8 = undefined;
        for (entries.items) |entry| {
            const line = try std.fmt.bufPrint(&buf, "{s}\n", .{entry.name});
            _ = try std.posix.write(std.posix.STDOUT_FILENO, line);
        }
        return;
    }

    // Calculate column widths
    var max_name_len: usize = 4; // "name"
    for (entries.items) |entry| {
        if (entry.name.len > max_name_len) {
            max_name_len = entry.name.len;
        }
    }

    // Calculate index column width
    const max_index = entries.items.len - 1;
    var index_width: usize = 1;
    var temp = max_index;
    while (temp >= 10) : (temp /= 10) {
        index_width += 1;
    }
    if (index_width < 1) index_width = 1;

    // Print header
    std.debug.print("╭─", .{});
    for (0..index_width) |_| std.debug.print("─", .{});
    std.debug.print("─┬─", .{});
    for (0..max_name_len) |_| std.debug.print("─", .{});
    std.debug.print("─┬──────┬──────────┬────────────────╮\n", .{});

    std.debug.print("│ ", .{});
    for (0..index_width - 1) |_| std.debug.print(" ", .{});
    std.debug.print("{s}#{s} │ {s}name{s}", .{ color_config.header, Color.reset, color_config.header, Color.reset });
    for (0..max_name_len - 4) |_| std.debug.print(" ", .{});
    std.debug.print(" │ {s}type{s} │ {s}  size{s}   │ {s}   modified{s}    │\n", .{ color_config.header, Color.reset, color_config.header, Color.reset, color_config.header, Color.reset });

    std.debug.print("├─", .{});
    for (0..index_width) |_| std.debug.print("─", .{});
    std.debug.print("─┼─", .{});
    for (0..max_name_len) |_| std.debug.print("─", .{});
    std.debug.print("─┼──────┼──────────┼────────────────┤\n", .{});

    // Print entries
    for (entries.items, 0..) |entry, i| {
        var size_buf: [32]u8 = undefined;
        var time_buf: [64]u8 = undefined;
        const size_str = try formatSize(entry.size, &size_buf);
        const time_str = try formatTime(entry.modified, now, &time_buf);

        const type_str = switch (entry.kind) {
            .file => "file",
            .directory => "dir ",
            .sym_link => "link",
            else => "????",
        };

        const color = getColorForEntry(entry, &color_config);

        // Print index with padding
        var idx_buf: [32]u8 = undefined;
        const idx_str = try std.fmt.bufPrint(&idx_buf, "{d}", .{i});
        std.debug.print("│ ", .{});
        for (0..index_width - idx_str.len) |_| std.debug.print(" ", .{});
        std.debug.print("{s}{s}{s} │ {s}{s}{s}", .{ color_config.header, idx_str, Color.reset, color, entry.name, Color.reset });
        for (0..max_name_len - entry.name.len) |_| std.debug.print(" ", .{});
        std.debug.print(" │ {s} │ {s: >8} │ {s: <14} │\n", .{ type_str, size_str, time_str });
    }

    // Print footer
    std.debug.print("╰─", .{});
    for (0..index_width) |_| std.debug.print("─", .{});
    std.debug.print("─┴─", .{});
    for (0..max_name_len) |_| std.debug.print("─", .{});
    std.debug.print("─┴──────┴──────────┴────────────────╯\n", .{});
}
