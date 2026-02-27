const std = @import("std");

fn writeErr(stderr_ptr: [*]u8, stderr_cap: usize, stderr_len: *usize, msg: []const u8) void {
    const copy_len = @min(stderr_cap, msg.len);
    if (copy_len > 0) @memcpy(stderr_ptr[0..copy_len], msg[0..copy_len]);
    stderr_len.* = copy_len;
}

pub export fn spiderweb_driver_v1_invoke_json(
    payload_ptr: [*]const u8,
    payload_len: usize,
    stdout_ptr: [*]u8,
    stdout_cap: usize,
    stdout_len: *usize,
    stderr_ptr: [*]u8,
    stderr_cap: usize,
    stderr_len: *usize,
) callconv(.c) i32 {
    stdout_len.* = 0;
    stderr_len.* = 0;

    if (payload_len == 0) {
        writeErr(stderr_ptr, stderr_cap, stderr_len, "payload is empty");
        return 2;
    }
    const payload = payload_ptr[0..payload_len];
    const trimmed = std.mem.trim(u8, payload, " \t\r\n");
    if (trimmed.len == 0 or trimmed[0] != '{') {
        writeErr(stderr_ptr, stderr_cap, stderr_len, "payload must be a JSON object");
        return 2;
    }

    const prefix = "{\"ok\":true,\"driver\":\"spiderweb-echo-inproc\",\"echo\":";
    const suffix = "}";
    const required = prefix.len + trimmed.len + suffix.len;
    if (required > stdout_cap) {
        writeErr(stderr_ptr, stderr_cap, stderr_len, "output buffer too small");
        return 3;
    }

    var cursor: usize = 0;
    @memcpy(stdout_ptr[cursor .. cursor + prefix.len], prefix);
    cursor += prefix.len;
    @memcpy(stdout_ptr[cursor .. cursor + trimmed.len], trimmed);
    cursor += trimmed.len;
    @memcpy(stdout_ptr[cursor .. cursor + suffix.len], suffix);
    cursor += suffix.len;
    stdout_len.* = cursor;
    return 0;
}
