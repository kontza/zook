const std = @import("std");
const yazap = @import("yazap");
const c = @cImport({
    @cInclude("signal.h");
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
    @cInclude("sys/event.h");
});

const PROGRAM_NAME = "phook";
const PROGRAM_VERSION = "0.08";
const App = yazap.App;
const Arg = yazap.Arg;
var after: ?*const u8 = null;

fn copyright() void {
    // std.log.info(
    //     \\Copyright (C) 2017 Ivan Drinchev
    //     \\This software may be modified and distributed
    //     \\under the terms of the MIT license.
    // , .{});
}

fn usage(status: u32) !void {
    if (status != 0) {
        std.log.info("Try '{} --help' for more information.\n", .{PROGRAM_NAME});
    } else {
        std.log.info("Usage: {} [OPTION]...\n", .{PROGRAM_NAME});
        std.log.info("Runs a command after a parent process has finished.\n\n", .{});
        std.log.info(
            \\Mandatory arguments to long options are mandatory for short options too
            \\  -a, --after=COMMAND        executes command after the parent process has ended
            \\  -e, --execute=COMMAND      executes command on start
            \\  -p, --process=PID          waits for PID to exit instead of parent process
            \\  -h, --help                 display this help and exit
            \\      --version              output version information and exit
        , .{});
        copyright();
    }
    std.c.exit(status);
}

fn version() void {
    // std.log.info("{} {}\n", .{ PROGRAM_NAME, PROGRAM_VERSION });
    copyright();
    std.c.exit(0);
}

fn sigint_handler(_: c_int) callconv(.C) void {
    if (after) |cmd| {
        _ = c.system(cmd);
    }
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

    var app = App.init(allocator, "zook", "Runs a command after a parent process has finished");
    defer app.deinit();
    var zook = app.rootCommand();
    try zook.addArg(Arg.booleanOption("version", null, null));
    const matches = try app.parseProcess();
    if (matches.containsArg("version")) {
        version();
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

    if (after != null) {
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
        acode = c.system(after);
    }

    if (acode > 0) {
        std.c.exit(1);
    }

    std.c.exit(0);
}
