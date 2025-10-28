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
};

// ANSI color codes
const Color = struct {
    const reset = "\x1b[0m";
    const cyan = "\x1b[96m";
    const light_red = "\x1b[91m";
    const magenta = "\x1b[95m";
    const green = "\x1b[92m";
    const yellow = "\x1b[93m";
};

fn getColorForEntry(entry: FileEntry) []const u8 {
    switch (entry.kind) {
        .directory => return Color.cyan,
        .sym_link => return Color.magenta,
        .file => {
            // Check if executable (owner, group, or other has execute permission)
            const is_executable = (entry.mode & 0o111) != 0;
            if (is_executable) {
                return Color.light_red;
            }
            return Color.reset;
        },
        else => return Color.reset,
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

fn parseArgs() !Options {
    var opts = Options{};
    var args = std.process.args();

    // Skip program name
    _ = args.skip();

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--all")) {
            opts.show_hidden = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            std.debug.print("Usage: nulis [OPTIONS]\n", .{});
            std.debug.print("Options:\n", .{});
            std.debug.print("  -a, --all     Show hidden files (files starting with .)\n", .{});
            std.debug.print("  -h, --help    Show this help message\n", .{});
            std.process.exit(0);
        }
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

    var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
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
    std.debug.print("{s}#{s} │ {s}name{s}", .{ Color.green, Color.reset, Color.green, Color.reset });
    for (0..max_name_len - 4) |_| std.debug.print(" ", .{});
    std.debug.print(" │ {s}type{s} │ {s}  size{s}   │ {s}   modified{s}    │\n", .{ Color.green, Color.reset, Color.green, Color.reset, Color.green, Color.reset });

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

        const color = getColorForEntry(entry);

        // Print index with padding
        var idx_buf: [32]u8 = undefined;
        const idx_str = try std.fmt.bufPrint(&idx_buf, "{d}", .{i});
        std.debug.print("│ ", .{});
        for (0..index_width - idx_str.len) |_| std.debug.print(" ", .{});
        std.debug.print("{s}{s}{s} │ {s}{s}{s}", .{ Color.green, idx_str, Color.reset, color, entry.name, Color.reset });
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
