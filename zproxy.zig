const std = @import("std");

pub const io_mode = .evented;

pub fn main() anyerror!void {
    var server = std.net.StreamServer.init(.{});
    defer server.deinit();

    try server.listen(std.net.Address.parseIp("127.0.0.1", 1883) catch unreachable);
    std.debug.warn("Listening at {}\n", .{server.listen_address});

    const allocator = std.heap.page_allocator;
    while (true) {
        const client = try allocator.create(Client);
        client.* = Client{
            .conn = try server.accept(),
            .handle_frame = async client.handle(),
        };
    }
}

const Client = struct {
    conn: std.net.StreamServer.Connection,
    handle_frame: @Frame(handle),

    fn handle(self: *Client) !void {
        // Close connection once we are donw with it
        defer self.conn.file.close();

        // Open TCP socket towards MQTT borker
        const brokerSocket = try std.net.tcpConnectToAddress(std.net.Address.parseIp("127.0.0.1", 1884) catch unreachable);
        defer brokerSocket.close();

        // Read from MQTT client and write to MQTT broker
        var c2b = async pipe(self.conn.file, brokerSocket);

        // Read from MQTT broker and write to MQTT client
        var b2c = async pipe(brokerSocket, self.conn.file);

        // Wait to finish
        try await c2b;
        try await b2c;
    }
};

fn pipe(in: std.fs.File, out: std.fs.File) !void {
    var buf = std.fifo.LinearFifo(u8, .{.Static = 4096}).init();
    while (true) {
        const bytes_read = try in.read(buf.writableSlice(0));
        std.debug.warn("Read {} bytes\n", .{bytes_read});
        if (bytes_read == 0 and buf.readableLength() == 0) {
            // EOF + all written out
            break;
        }
        buf.update(bytes_read);

        const bytes_written = try out.write(buf.readableSlice(0));
        buf.discard(bytes_written);
    }
}