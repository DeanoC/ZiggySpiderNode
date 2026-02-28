const std = @import("std");

const max_payload_bytes: usize = 1024 * 1024;
const max_response_bytes: usize = 2 * 1024 * 1024;
const default_max_results: usize = 5;
const hard_max_results: usize = 12;

const SearchRequest = struct {
    query: []const u8,
    max_results: usize = default_max_results,
    region: ?[]const u8 = null,
    safesearch: ?[]const u8 = null,
};

const SearchResult = struct {
    title: []u8,
    url: []u8,
    snippet: []u8,
    source: []u8,

    fn deinit(self: *SearchResult, allocator: std.mem.Allocator) void {
        allocator.free(self.title);
        allocator.free(self.url);
        allocator.free(self.snippet);
        allocator.free(self.source);
        self.* = undefined;
    }
};

fn fatal(msg: []const u8) noreturn {
    std.fs.File.stderr().writeAll(msg) catch {};
    std.fs.File.stderr().writeAll("\n") catch {};
    std.process.exit(2);
}

fn jsonEscapeOwned(allocator: std.mem.Allocator, value: []const u8) ![]u8 {
    var out = std.ArrayListUnmanaged(u8){};
    errdefer out.deinit(allocator);

    for (value) |ch| {
        switch (ch) {
            '"' => try out.appendSlice(allocator, "\\\""),
            '\\' => try out.appendSlice(allocator, "\\\\"),
            '\n' => try out.appendSlice(allocator, "\\n"),
            '\r' => try out.appendSlice(allocator, "\\r"),
            '\t' => try out.appendSlice(allocator, "\\t"),
            else => {
                if (ch < 0x20) {
                    try out.writer(allocator).print("\\u00{x:0>2}", .{ch});
                } else {
                    try out.append(allocator, ch);
                }
            },
        }
    }

    return out.toOwnedSlice(allocator);
}

fn parsePayload(allocator: std.mem.Allocator, payload: []const u8) !SearchRequest {
    const trimmed = std.mem.trim(u8, payload, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidPayload;

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, trimmed, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return error.InvalidPayload;

    const obj = parsed.value.object;
    const query_val = obj.get("query") orelse return error.InvalidPayload;
    if (query_val != .string) return error.InvalidPayload;
    const query_trimmed = std.mem.trim(u8, query_val.string, " \t\r\n");
    if (query_trimmed.len == 0) return error.InvalidPayload;

    var req = SearchRequest{ .query = try allocator.dupe(u8, query_trimmed) };
    errdefer allocator.free(req.query);

    if (obj.get("max_results")) |value| {
        if (value != .integer or value.integer < 1) return error.InvalidPayload;
        req.max_results = @intCast(@min(@as(i64, hard_max_results), value.integer));
    }

    if (obj.get("region")) |value| {
        if (value != .string) return error.InvalidPayload;
        const region_trimmed = std.mem.trim(u8, value.string, " \t\r\n");
        if (region_trimmed.len > 0) req.region = try allocator.dupe(u8, region_trimmed);
    }

    if (obj.get("safesearch")) |value| {
        if (value != .string) return error.InvalidPayload;
        const safe_trimmed = std.mem.trim(u8, value.string, " \t\r\n");
        if (safe_trimmed.len > 0) req.safesearch = try allocator.dupe(u8, safe_trimmed);
    }

    return req;
}

fn freeRequest(allocator: std.mem.Allocator, req: *SearchRequest) void {
    allocator.free(req.query);
    if (req.region) |v| allocator.free(v);
    if (req.safesearch) |v| allocator.free(v);
    req.* = undefined;
}

fn appendQueryParam(
    allocator: std.mem.Allocator,
    out: *std.ArrayListUnmanaged(u8),
    key: []const u8,
    value: []const u8,
) !void {
    try out.append(allocator, '&');
    try out.appendSlice(allocator, key);
    try out.append(allocator, '=');
    for (value) |ch| {
        const is_unreserved = std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '_' or ch == '.' or ch == '~';
        if (is_unreserved) {
            try out.append(allocator, ch);
        } else {
            try out.writer(allocator).print("%{X:0>2}", .{ch});
        }
    }
}

fn buildSearchUrl(allocator: std.mem.Allocator, req: SearchRequest) ![]u8 {
    var out = std.ArrayListUnmanaged(u8){};
    errdefer out.deinit(allocator);

    try out.appendSlice(
        allocator,
        "https://api.duckduckgo.com/?format=json&no_html=1&no_redirect=1&skip_disambig=1",
    );
    try appendQueryParam(allocator, &out, "q", req.query);
    if (req.region) |value| try appendQueryParam(allocator, &out, "kl", value);
    if (req.safesearch) |value| try appendQueryParam(allocator, &out, "kp", value);

    return out.toOwnedSlice(allocator);
}

fn fetchJson(allocator: std.mem.Allocator, url: []const u8) ![]u8 {
    const uri = try std.Uri.parse(url);

    var client: std.http.Client = .{ .allocator = allocator };
    defer client.deinit();

    const headers = [_]std.http.Header{
        .{ .name = "accept", .value = "application/json" },
        .{ .name = "user-agent", .value = "spiderweb-web-search-driver/1" },
    };

    var req = try client.request(.GET, uri, .{
        .redirect_behavior = std.http.Client.Request.RedirectBehavior.init(4),
        .extra_headers = &headers,
    });
    defer req.deinit();

    try req.sendBodiless();
    var response = try req.receiveHead(&.{});
    if (response.head.status != .ok) {
        return error.HttpStatusNotOk;
    }

    var body_writer: std.Io.Writer.Allocating = .init(allocator);
    defer body_writer.deinit();
    _ = try response.reader(&.{}).streamRemaining(&body_writer.writer);
    const body = try body_writer.toOwnedSlice();
    if (body.len > max_response_bytes) {
        allocator.free(body);
        return error.ResponseTooLarge;
    }
    return body;
}

fn appendResult(
    allocator: std.mem.Allocator,
    out: *std.ArrayListUnmanaged(SearchResult),
    title: []const u8,
    url: []const u8,
    snippet: []const u8,
    source: []const u8,
) !void {
    if (title.len == 0 or url.len == 0) return;
    try out.append(allocator, .{
        .title = try allocator.dupe(u8, title),
        .url = try allocator.dupe(u8, url),
        .snippet = try allocator.dupe(u8, snippet),
        .source = try allocator.dupe(u8, source),
    });
}

fn extractRelatedTopics(
    allocator: std.mem.Allocator,
    value: std.json.Value,
    out: *std.ArrayListUnmanaged(SearchResult),
    max_results: usize,
) !void {
    if (out.items.len >= max_results) return;
    if (value != .array) return;

    for (value.array.items) |item| {
        if (out.items.len >= max_results) return;
        if (item != .object) continue;
        const obj = item.object;

        if (obj.get("Topics")) |nested| {
            try extractRelatedTopics(allocator, nested, out, max_results);
            continue;
        }

        const text = if (obj.get("Text")) |v| switch (v) {
            .string => v.string,
            else => "",
        } else "";
        const first_url = if (obj.get("FirstURL")) |v| switch (v) {
            .string => v.string,
            else => "",
        } else "";
        if (text.len == 0 or first_url.len == 0) continue;

        try appendResult(allocator, out, text, first_url, text, "duckduckgo.related");
    }
}

fn parseSearchResults(
    allocator: std.mem.Allocator,
    body_json: []const u8,
    max_results: usize,
) !std.ArrayListUnmanaged(SearchResult) {
    var out = std.ArrayListUnmanaged(SearchResult){};
    errdefer {
        for (out.items) |*entry| entry.deinit(allocator);
        out.deinit(allocator);
    }

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body_json, .{});
    defer parsed.deinit();
    if (parsed.value != .object) return out;

    const root = parsed.value.object;

    const abstract_text = if (root.get("AbstractText")) |v| switch (v) {
        .string => v.string,
        else => "",
    } else "";
    const abstract_url = if (root.get("AbstractURL")) |v| switch (v) {
        .string => v.string,
        else => "",
    } else "";
    const heading = if (root.get("Heading")) |v| switch (v) {
        .string => v.string,
        else => "",
    } else "";

    if (abstract_text.len > 0 and abstract_url.len > 0 and out.items.len < max_results) {
        const title = if (heading.len > 0) heading else abstract_text;
        try appendResult(allocator, &out, title, abstract_url, abstract_text, "duckduckgo.abstract");
    }

    if (root.get("RelatedTopics")) |related| {
        try extractRelatedTopics(allocator, related, &out, max_results);
    }

    if (out.items.len == 0) {
        const answer = if (root.get("Answer")) |v| switch (v) {
            .string => v.string,
            else => "",
        } else "";
        const answer_type = if (root.get("AnswerType")) |v| switch (v) {
            .string => v.string,
            else => "",
        } else "";
        if (answer.len > 0) {
            const source = if (answer_type.len > 0) answer_type else "duckduckgo.answer";
            try appendResult(allocator, &out, answer, "https://duckduckgo.com", answer, source);
        }
    }

    return out;
}

fn renderOutput(
    allocator: std.mem.Allocator,
    req: SearchRequest,
    results: []const SearchResult,
) ![]u8 {
    var out = std.ArrayListUnmanaged(u8){};
    errdefer out.deinit(allocator);

    const escaped_query = try jsonEscapeOwned(allocator, req.query);
    defer allocator.free(escaped_query);

    try out.writer(allocator).print(
        "{{\"ok\":true,\"driver\":\"spiderweb-web-search-driver\",\"provider\":\"duckduckgo_instant_answer\",\"query\":\"{s}\",\"result_count\":{d},\"fetched_at_ms\":{d},\"results\":[",
        .{ escaped_query, results.len, std.time.milliTimestamp() },
    );

    for (results, 0..) |entry, idx| {
        if (idx != 0) try out.append(allocator, ',');
        const escaped_title = try jsonEscapeOwned(allocator, entry.title);
        defer allocator.free(escaped_title);
        const escaped_url = try jsonEscapeOwned(allocator, entry.url);
        defer allocator.free(escaped_url);
        const escaped_snippet = try jsonEscapeOwned(allocator, entry.snippet);
        defer allocator.free(escaped_snippet);
        const escaped_source = try jsonEscapeOwned(allocator, entry.source);
        defer allocator.free(escaped_source);

        try out.writer(allocator).print(
            "{{\"title\":\"{s}\",\"url\":\"{s}\",\"snippet\":\"{s}\",\"source\":\"{s}\"}}",
            .{ escaped_title, escaped_url, escaped_snippet, escaped_source },
        );
    }

    try out.appendSlice(allocator, "]}");
    return out.toOwnedSlice(allocator);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const payload = std.fs.File.stdin().readToEndAlloc(allocator, max_payload_bytes) catch {
        fatal("failed reading invoke payload");
    };
    defer allocator.free(payload);

    var req = parsePayload(allocator, payload) catch {
        fatal("invoke payload must be a JSON object with non-empty string field: query");
    };
    defer freeRequest(allocator, &req);

    const url = buildSearchUrl(allocator, req) catch {
        fatal("failed building search URL");
    };
    defer allocator.free(url);

    const body_json = fetchJson(allocator, url) catch {
        fatal("web search request failed");
    };
    defer allocator.free(body_json);

    var results = parseSearchResults(allocator, body_json, req.max_results) catch {
        fatal("search response parsing failed");
    };
    defer {
        for (results.items) |*entry| entry.deinit(allocator);
        results.deinit(allocator);
    }

    const rendered = renderOutput(allocator, req, results.items) catch {
        fatal("failed rendering search results");
    };
    defer allocator.free(rendered);

    std.fs.File.stdout().writeAll(rendered) catch {
        fatal("failed writing result");
    };
}
