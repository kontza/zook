const std = @import("std");
const yazap = @import("yazap");
const c = @cImport({
    @cInclude("signal.h");
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
    @cInclude("sys/event.h");
});

const PROGRAM_NAME = "zook";
const PROGRAM_VERSION = "1.0.0";
const AFTER = "after";
const EXECUTE = "execute";
const PROCESS = "process";
const VERSION = "version";

const App = yazap.App;
const Arg = yazap.Arg;
var after: []const u8 = "";

fn version() void {
    std.debug.print("{s} {s}\n", .{ PROGRAM_NAME, PROGRAM_VERSION });
    std.c.exit(0);
}

fn sigint_handler(_: c_int) callconv(.C) void {
    _ = c.system(after.ptr);
    std.c.exit(0);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const execute: ?*const u8 = null;
    var acode: i32 = 0;
    var ecode: i32 = 0;
    var ppid: c_int = 0;
    var fpid: i32 = 0;

    _ = c.signal(std.c.SIG.INT, sigint_handler);
    _ = c.signal(std.c.SIG.PIPE, sigint_handler);

    var app = App.init(allocator, PROGRAM_NAME, "Runs a command after a parent process has finished");
    defer app.deinit();
    var zook = app.rootCommand();
    try zook.addArg(Arg.booleanOption(VERSION, null, null));
    try zook.addArg(Arg.singleValueOption(AFTER, 'a', "executes command after the parent process has ended"));
    try zook.addArg(Arg.singleValueOption(EXECUTE, 'e', "executes command on start"));
    try zook.addArg(Arg.singleValueOption(PROCESS, 'p', "waits for for the given PID to exit instead of parent process"));

    const matches = try app.parseProcess();
    if (matches.containsArg(VERSION)) {
        version();
    }
    if (matches.getSingleValue(AFTER)) |cmd| {
        after = cmd;
    }

    // const args = [][]const u8;
    // for (args) |arg| {
    //     if (std.mem.eql(u8, arg, "--help")) {
    //         usage(0);
    //     } else if (std.mem.eql(u8, arg, "--version")) {
    //         version();
    //     } else if (std.mem.eql(u8, arg, "--after")) {
    //         after = args.next();
    //     } else if (std.mem.eql(u8, arg, "--execute")) {
    //         execute = args.next();
    //     } else if (std.mem.eql(u8, arg, "--process")) {
    //         const pid_str = args.next();
    //         const pid = std.fmt.parseInt(i32, pid_str) catch |err| {
    //             std.log.info("process: Invalid argument: {}\n", .{err});
    //             usage(1);
    //         };
    //         ppid = pid;
    //     }
    // }

    if (execute != null) {
        ecode = c.system(execute);
    }

    if (ecode > 0) {
        std.c.exit(1);
    }

    if (after.len == 0) {
        std.c.exit(0);
    }

    if (ppid == 0) {
        ppid = c.getppid();
    }

    fpid = c.fork();
    if (fpid != 0) {
        std.c.exit(0);
    }

    // Set up kqueue and wait for the parent process to exit
    const kq = c.kqueue();
    if (kq == -1) {
        std.log.info("kqueue failed\n", .{});
        std.c.exit(1);
    }

    const timeout = c.timespec{ .tv_sec = 8 * 60 * 60, .tv_nsec = 0 };
    var kev = c.struct_kevent{ .ident = @intCast(ppid), .filter = c.EVFILT_PROC, .flags = c.EV_ADD, .fflags = c.NOTE_EXIT, .data = 0, .udata = null };

    if (c.kevent(kq, &kev, 1, null, 0, null) == -1) {
        std.log.info("kevent failed\n", .{});
        std.c.exit(1);
    }

    if (c.kevent(kq, null, 0, &kev, 1, &timeout) == -1) {
        std.log.info("kevent failed\n", .{});
        std.c.exit(1);
    }

    if (kev.data > 0) {
        acode = c.system(after.ptr);
    }

    if (acode > 0) {
        std.c.exit(1);
    }

    std.c.exit(0);
}
