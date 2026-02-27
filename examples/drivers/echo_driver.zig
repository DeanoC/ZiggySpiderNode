const std = @import("std");

const max_payload_bytes: usize = 1024 * 1024;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdin_file = std.fs.File.stdin();
    const payload = try stdin_file.readToEndAlloc(allocator, max_payload_bytes);
    defer allocator.free(payload);
    const trimmed = std.mem.trim(u8, payload, " \t\r\n");
    if (trimmed.len == 0) {
        try std.fs.File.stderr().writeAll("invoke payload must be a JSON object\n");
        std.process.exit(2);
    }

    var parsed = std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{}) catch {
        try std.fs.File.stderr().writeAll("invoke payload must be valid JSON\n");
        std.process.exit(2);
    };
    defer parsed.deinit();
    if (parsed.value != .object) {
        try std.fs.File.stderr().writeAll("invoke payload must be a JSON object\n");
        std.process.exit(2);
    }

    const echoed_json = try std.fmt.allocPrint(allocator, "{f}", .{std.json.fmt(parsed.value, .{})});
    defer allocator.free(echoed_json);

    const rendered = try std.fmt.allocPrint(
        allocator,
        "{{\"ok\":true,\"driver\":\"spiderweb-echo-driver\",\"ts_ms\":{d},\"echo\":{s}}}",
        .{ std.time.milliTimestamp(), echoed_json },
    );
    defer allocator.free(rendered);
    try std.fs.File.stdout().writeAll(rendered);
}
