//! The process's standard streams.
//!
//! On Windows a parent can hand over a pipe opened for asynchronous
//! (overlapped) I/O: MSYS2 and Cygwin programs do (Git Bash's
//! `skein ... | wc`). The standard library's synchronous path does not
//! expect that, and output is dropped. The functions here ask the handle
//! how it was opened and set the file's `nonblocking` flag to match. Use
//! them, not `std.Io.File`'s, for the standard streams.
//!
//! From cesiumlang/zfls, src/stdio.zig (MIT), commit 1359ed1.

const std = @import("std");
const sysinfo = @import("builtin");
const Io = std.Io;
const windows = std.os.windows;

const is_windows = sysinfo.target.os.tag == .windows;

pub fn stdin() Io.File {
    return adapt(Io.File.stdin());
}

pub fn stdout() Io.File {
    return adapt(Io.File.stdout());
}

pub fn stderr() Io.File {
    return adapt(Io.File.stderr());
}

/// `file` with the `nonblocking` flag that its handle needs
pub fn adapt(file: Io.File) Io.File {
    if (!is_windows) return file;
    var f = file;
    f.flags.nonblocking = isAsynchronous(file.handle);
    return f;
}

// FILE_MODE_INFORMATION's flags (wdm.h)
const FILE_SYNCHRONOUS_IO_ALERT: windows.ULONG = 0x10;
const FILE_SYNCHRONOUS_IO_NONALERT: windows.ULONG = 0x20;

/// Whether `handle` was opened for asynchronous (overlapped) I/O. False
/// when the handle cannot be asked (none, or not a file).
fn isAsynchronous(handle: windows.HANDLE) bool {
    var iosb: windows.IO_STATUS_BLOCK = undefined;
    var mode: windows.ULONG = 0;
    const status = windows.ntdll.NtQueryInformationFile(handle, &iosb, &mode, @sizeOf(windows.ULONG), .Mode);
    if (status != .SUCCESS) return false;
    return mode & (FILE_SYNCHRONOUS_IO_ALERT | FILE_SYNCHRONOUS_IO_NONALERT) == 0;
}
