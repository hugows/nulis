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
    reverse: bool = false, // reverse sort order (most recent last)
    plain: bool = false, // plain text output (no table, no colors)
    csv: bool = false, // CSV output format
    path: []const u8 = ".", // directory path to list
    theme: ?[]const u8 = null, // theme string "dir,exe,sym,hdr"
    hyperlink: bool = false, // wrap filenames in OSC 8 hyperlinks
};

// ANSI color codes
const Color = struct {
    const reset = "\x1b[0m";
};

const ColorConfig = struct {
    directory: [16]u8,
    executable: [16]u8,
    symlink: [16]u8,
    header: [16]u8,
    regular: [16]u8,

    fn default() ColorConfig {
        var config: ColorConfig = .{
            .directory = [_]u8{0} ** 16,
            .executable = [_]u8{0} ** 16,
            .symlink = [_]u8{0} ** 16,
            .header = [_]u8{0} ** 16,
            .regular = [_]u8{0} ** 16,
        };
        _ = std.fmt.bufPrint(&config.directory, "\x1b[96m", .{}) catch unreachable;
        _ = std.fmt.bufPrint(&config.executable, "\x1b[91m", .{}) catch unreachable;
        _ = std.fmt.bufPrint(&config.symlink, "\x1b[95m", .{}) catch unreachable;
        _ = std.fmt.bufPrint(&config.header, "\x1b[92m", .{}) catch unreachable;
        _ = std.fmt.bufPrint(&config.regular, "\x1b[0m", .{}) catch unreachable;
        return config;
    }

    fn fromTheme(theme_str: []const u8) !ColorConfig {
        var config: ColorConfig = .{
            .directory = [_]u8{0} ** 16,
            .executable = [_]u8{0} ** 16,
            .symlink = [_]u8{0} ** 16,
            .header = [_]u8{0} ** 16,
            .regular = [_]u8{0} ** 16,
        };

        // Set defaults first
        _ = std.fmt.bufPrint(&config.directory, "\x1b[96m", .{}) catch unreachable;
        _ = std.fmt.bufPrint(&config.executable, "\x1b[91m", .{}) catch unreachable;
        _ = std.fmt.bufPrint(&config.symlink, "\x1b[95m", .{}) catch unreachable;
        _ = std.fmt.bufPrint(&config.header, "\x1b[92m", .{}) catch unreachable;
        _ = std.fmt.bufPrint(&config.regular, "\x1b[0m", .{}) catch unreachable;

        var parts = std.mem.splitScalar(u8, theme_str, ',');

        // Parse directory color
        if (parts.next()) |dir_code| {
            const trimmed = std.mem.trim(u8, dir_code, " \t");
            config.directory = [_]u8{0} ** 16;
            _ = try std.fmt.bufPrint(&config.directory, "\x1b[{s}m", .{trimmed});
        }

        // Parse executable color
        if (parts.next()) |exe_code| {
            const trimmed = std.mem.trim(u8, exe_code, " \t");
            config.executable = [_]u8{0} ** 16;
            _ = try std.fmt.bufPrint(&config.executable, "\x1b[{s}m", .{trimmed});
        }

        // Parse symlink color
        if (parts.next()) |sym_code| {
            const trimmed = std.mem.trim(u8, sym_code, " \t");
            config.symlink = [_]u8{0} ** 16;
            _ = try std.fmt.bufPrint(&config.symlink, "\x1b[{s}m", .{trimmed});
        }

        // Parse header color
        if (parts.next()) |hdr_code| {
            const trimmed = std.mem.trim(u8, hdr_code, " \t");
            config.header = [_]u8{0} ** 16;
            _ = try std.fmt.bufPrint(&config.header, "\x1b[{s}m", .{trimmed});
        }

        return config;
    }
};

// OSC 8 hyperlink escape sequences
const HYPERLINK_START = "\x1B]8;;file://";
const HYPERLINK_MIDDLE = "\x1B\\";
const HYPERLINK_END = "\x1B]8;;\x1B\\";

fn percentEncodeChar(c: u8) bool {
    return c <= 0x20 or c == 0x7F or c == ' ' or c == '%' or c == '#' or c == '?';
}

fn makeHyperlink(allocator: std.mem.Allocator, abs_path: []const u8, display_name: []const u8) ![]const u8 {
    // Calculate size needed for percent-encoded path
    var encoded_size: usize = 0;
    for (abs_path) |c| {
        encoded_size += if (percentEncodeChar(c)) 3 else 1;
    }

    // Build the hyperlink: \x1B]8;;file:///path\x1B\display_name\x1B]8;;\x1B\
    const total_size = HYPERLINK_START.len + encoded_size + HYPERLINK_MIDDLE.len + display_name.len + HYPERLINK_END.len;
    var buf = try allocator.alloc(u8, total_size);
    var idx: usize = 0;

    // Add start
    @memcpy(buf[idx..][0..HYPERLINK_START.len], HYPERLINK_START);
    idx += HYPERLINK_START.len;

    // Add percent-encoded path
    for (abs_path) |c| {
        if (percentEncodeChar(c)) {
            buf[idx] = '%';
            _ = std.fmt.bufPrint(buf[idx + 1 ..][0..2], "{X:0>2}", .{c}) catch unreachable;
            idx += 3;
        } else {
            buf[idx] = c;
            idx += 1;
        }
    }

    // Add middle separator
    @memcpy(buf[idx..][0..HYPERLINK_MIDDLE.len], HYPERLINK_MIDDLE);
    idx += HYPERLINK_MIDDLE.len;

    // Add display name
    @memcpy(buf[idx..][0..display_name.len], display_name);
    idx += display_name.len;

    // Add end
    @memcpy(buf[idx..][0..HYPERLINK_END.len], HYPERLINK_END);

    return buf;
}

fn getColorForEntry(entry: FileEntry, config: *const ColorConfig) []const u8 {
    switch (entry.kind) {
        .directory => return std.mem.sliceTo(&config.directory, 0),
        .sym_link => return std.mem.sliceTo(&config.symlink, 0),
        .file => {
            // Check if executable (owner, group, or other has execute permission)
            const is_executable = (entry.mode & 0o111) != 0;
            if (is_executable) {
                return std.mem.sliceTo(&config.executable, 0);
            }
            return std.mem.sliceTo(&config.regular, 0);
        },
        else => return std.mem.sliceTo(&config.regular, 0),
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

fn sortByModifiedAsc(_: void, a: FileEntry, b: FileEntry) bool {
    return a.modified < b.modified;
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
        } else if (std.mem.eql(u8, arg, "--reverse")) {
            opts.reverse = true;
        } else if (std.mem.eql(u8, arg, "--hyperlink")) {
            opts.hyperlink = true;
        } else if (std.mem.startsWith(u8, arg, "--theme=")) {
            opts.theme = arg[8..];
        } else if (std.mem.eql(u8, arg, "--help")) {
            std.debug.print("Usage: nulis [OPTIONS] [PATH]\n", .{});
            std.debug.print("Options:\n", .{});
            std.debug.print("  -a, --all          Show hidden files (files starting with .)\n", .{});
            std.debug.print("  -p, --plain        Plain text output (no table, no colors)\n", .{});
            std.debug.print("  -c, --csv          CSV output format\n", .{});
            std.debug.print("  -r, --reverse      Reverse sort order (most recent last)\n", .{});
            std.debug.print("      --hyperlink    Make filenames clickable hyperlinks\n", .{});
            std.debug.print("      --theme=CODES  Custom colors (e.g., --theme=96,91,95,92)\n", .{});
            std.debug.print("  -h, --help         Show this help message\n", .{});
            std.debug.print("\nArguments:\n", .{});
            std.debug.print("  PATH               Directory to list (default: current directory)\n", .{});
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "-h")) {
            // Show help only for standalone -h
            std.debug.print("Usage: nulis [OPTIONS] [PATH]\n", .{});
            std.debug.print("Options:\n", .{});
            std.debug.print("  -a, --all          Show hidden files (files starting with .)\n", .{});
            std.debug.print("  -p, --plain        Plain text output (no table, no colors)\n", .{});
            std.debug.print("  -c, --csv          CSV output format\n", .{});
            std.debug.print("  -r, --reverse      Reverse sort order (most recent last)\n", .{});
            std.debug.print("      --hyperlink    Make filenames clickable hyperlinks\n", .{});
            std.debug.print("      --theme=CODES  Custom colors (e.g., --theme=96,91,95,92)\n", .{});
            std.debug.print("  -h, --help         Show this help message\n", .{});
            std.debug.print("\nArguments:\n", .{});
            std.debug.print("  PATH               Directory to list (default: current directory)\n", .{});
            std.process.exit(0);
        } else if (arg[0] == '-' and arg.len > 1 and arg[1] != '-') {
            // Short form flags (can be grouped like -lah)
            for (arg[1..]) |flag_char| {
                switch (flag_char) {
                    'a' => opts.show_hidden = true,
                    'p' => opts.plain = true,
                    'c' => opts.csv = true,
                    'r' => opts.reverse = true,
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
    const color_config = if (opts.theme) |theme|
        try ColorConfig.fromTheme(theme)
    else
        ColorConfig.default();

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

    // Sort by modification time
    if (opts.sort_by_time) {
        if (opts.reverse) {
            std.mem.sort(FileEntry, entries.items, {}, sortByModifiedAsc);
        } else {
            std.mem.sort(FileEntry, entries.items, {}, sortByModifiedDesc);
        }
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

    // Get absolute path of the directory for hyperlinks
    var abs_dir_buf: [std.posix.PATH_MAX]u8 = undefined;
    const abs_dir = try dir.realpath(".", &abs_dir_buf);

    // Print entries
    var hyperlink_strings: std.ArrayList([]const u8) = .{};
    defer {
        for (hyperlink_strings.items) |str| {
            allocator.free(str);
        }
        hyperlink_strings.deinit(allocator);
    }

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

        // Prepare filename display (with hyperlink if enabled)
        const display_name = if (opts.hyperlink) blk: {
            // Build absolute path: abs_dir + "/" + entry.name
            const abs_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ abs_dir, entry.name });
            defer allocator.free(abs_path);

            const hyperlinked = try makeHyperlink(allocator, abs_path, entry.name);
            try hyperlink_strings.append(allocator, hyperlinked);
            break :blk hyperlinked;
        } else entry.name;

        // Print index with padding
        var idx_buf: [32]u8 = undefined;
        const idx_str = try std.fmt.bufPrint(&idx_buf, "{d}", .{i});
        std.debug.print("│ ", .{});
        for (0..index_width - idx_str.len) |_| std.debug.print(" ", .{});
        std.debug.print("{s}{s}{s} │ {s}{s}{s}", .{ color_config.header, idx_str, Color.reset, color, display_name, Color.reset });
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
