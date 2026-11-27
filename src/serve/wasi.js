// cspell:ignore BADF INVAL ISDIR NOENT NOSYS dirfd fdflags fdstat iovs oflags pread ptrs pwrite
// skein built for WebAssembly (wasm32-wasi), run in a page: the WASI calls
// it makes, over files held in memory. Each run starts the module afresh
// on the same files, so what one run writes the next one reads.
(function (global) {
  "use strict";
  var E = { SUCCESS: 0, BADF: 8, EXIST: 20, INVAL: 28, ISDIR: 31, NOENT: 44, NOSYS: 52, NOTDIR: 54, NOTEMPTY: 55 };
  var DIR = 3, FILE = 4;
  var ALL = 0xffffffffffffffffn;

  function Exit(code) { this.code = code; }

  function normalize(parts) {
    var out = [];
    parts.forEach(function (p) {
      if (p === "" || p === ".") return;
      if (p === "..") out.pop(); else out.push(p);
    });
    return out.join("/");
  }

  // files: an object or Map of path -> Uint8Array; changed: a Set the paths written go in
  function Files(files) {
    this.files = files instanceof Map ? files : new Map(Object.entries(files));
    this.dirs = new Set([""]);
    this.times = new Map();
    this.changed = new Set();
    var self = this;
    this.files.forEach(function (_, path) { self.addParents(path); });
  }
  Files.prototype.addParents = function (path) {
    var parts = path.split("/");
    for (var i = 1; i < parts.length; i++) this.dirs.add(parts.slice(0, i).join("/"));
  };
  Files.prototype.kind = function (path) {
    if (this.files.has(path)) return FILE;
    if (this.dirs.has(path)) return DIR;
    return 0;
  };
  Files.prototype.children = function (dir) {
    var prefix = dir === "" ? "" : dir + "/";
    var names = new Map();
    var collect = function (path, kind) {
      if (!path.startsWith(prefix) || path === dir) return;
      var rest = path.slice(prefix.length);
      var slash = rest.indexOf("/");
      if (slash >= 0) names.set(rest.slice(0, slash), DIR); else names.set(rest, kind);
    };
    this.files.forEach(function (_, p) { collect(p, FILE); });
    this.dirs.forEach(function (p) { collect(p, DIR); });
    return Array.from(names.entries()).sort(function (a, b) { return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0; });
  };
  Files.prototype.write = function (path, data) {
    this.files.set(path, data);
    this.addParents(path);
    this.times.set(path, BigInt(Date.now()) * 1000000n);
    this.changed.add(path);
  };

  // Runs `module` (a WebAssembly.Module) with `args` on `fs` (a Files), `stdin` bytes given
  function run(module, fs, args, stdin) {
    var memory = null;
    var out = [], err = [];
    var input = stdin || new Uint8Array(0), inputAt = 0;
    var fds = [null, null, null, { kind: DIR, path: "" }];
    var enc = new TextEncoder(), dec = new TextDecoder();
    var view = function () { return new DataView(memory.buffer); };
    var bytes = function () { return new Uint8Array(memory.buffer); };
    var str = function (ptr, len) { return dec.decode(bytes().subarray(ptr, ptr + len)); };
    var argv = args.map(function (s) { return enc.encode(s + "\0"); });
    var resolve = function (dirfd, ptr, len) {
      var d = fds[dirfd];
      if (!d || d.kind !== DIR) return null;
      return normalize((d.path + "/" + str(ptr, len)).split("/"));
    };
    var iovs = function (ptr, n) {
      var v = view(), list = [];
      for (var i = 0; i < n; i++) list.push([v.getUint32(ptr + i * 8, true), v.getUint32(ptr + i * 8 + 4, true)]);
      return list;
    };
    var gather = function (ptr, n) {
      var parts = iovs(ptr, n), total = 0;
      parts.forEach(function (p) { total += p[1]; });
      var data = new Uint8Array(total), at = 0, b = bytes();
      parts.forEach(function (p) { data.set(b.subarray(p[0], p[0] + p[1]), at); at += p[1]; });
      return data;
    };
    var scatter = function (ptr, n, src) {
      var at = 0, b = bytes();
      iovs(ptr, n).forEach(function (p) {
        var k = Math.min(p[1], src.length - at);
        if (k > 0) b.set(src.subarray(at, at + k), p[0]);
        at += Math.max(k, 0);
      });
      return Math.min(at, src.length);
    };
    var writeAt = function (f, pos, data) {
      var old = fs.files.get(f.path) || new Uint8Array(0);
      var size = Math.max(old.length, pos + data.length);
      var next = new Uint8Array(size);
      next.set(old);
      next.set(data, pos);
      fs.write(f.path, next);
    };
    var filestat = function (ptr, path) {
      var v = view(), kind = fs.kind(path);
      var size = kind === FILE ? fs.files.get(path).length : 0;
      var t = fs.times.get(path) || 0n;
      for (var i = 0; i < 64; i += 8) v.setBigUint64(ptr + i, 0n, true);
      v.setBigUint64(ptr + 8, BigInt(path.length + 1), true);
      v.setUint8(ptr + 16, kind);
      v.setBigUint64(ptr + 24, 1n, true);
      v.setBigUint64(ptr + 32, BigInt(size), true);
      v.setBigUint64(ptr + 40, t, true);
      v.setBigUint64(ptr + 48, t, true);
      v.setBigUint64(ptr + 56, t, true);
    };
    var wasi = {
      args_sizes_get: function (n, size) {
        view().setUint32(n, argv.length, true);
        view().setUint32(size, argv.reduce(function (s, a) { return s + a.length; }, 0), true);
        return 0;
      },
      args_get: function (ptrs, buf) {
        var at = buf;
        argv.forEach(function (a, i) { view().setUint32(ptrs + i * 4, at, true); bytes().set(a, at); at += a.length; });
        return 0;
      },
      environ_sizes_get: function (n, size) { view().setUint32(n, 0, true); view().setUint32(size, 0, true); return 0; },
      environ_get: function () { return 0; },
      fd_prestat_get: function (fd, ptr) {
        if (fd !== 3) return E.BADF;
        view().setUint8(ptr, 0);
        view().setUint32(ptr + 4, 1, true);
        return 0;
      },
      fd_prestat_dir_name: function (fd, ptr) {
        if (fd !== 3) return E.BADF;
        bytes()[ptr] = 46;
        return 0;
      },
      proc_exit: function (code) { throw new Exit(code); },
      random_get: function (ptr, len) {
        for (var at = 0; at < len; at += 65536) crypto.getRandomValues(bytes().subarray(ptr + at, ptr + Math.min(len, at + 65536)));
        return 0;
      },
      clock_time_get: function (_, __, ptr) { view().setBigUint64(ptr, BigInt(Date.now()) * 1000000n, true); return 0; },
      clock_res_get: function (_, ptr) { view().setBigUint64(ptr, 1000000n, true); return 0; },
      poll_oneoff: function () { return E.NOSYS; },
      fd_write: function (fd, ptr, n, written) {
        var data = gather(ptr, n);
        if (fd === 1) out.push(data);
        else if (fd === 2) err.push(data);
        else {
          var f = fds[fd];
          if (!f || f.kind !== FILE) return E.BADF;
          if (f.append) f.pos = (fs.files.get(f.path) || []).length;
          writeAt(f, f.pos, data);
          f.pos += data.length;
        }
        view().setUint32(written, data.length, true);
        return 0;
      },
      fd_pwrite: function (fd, ptr, n, offset, written) {
        var f = fds[fd];
        if (!f || f.kind !== FILE) return E.BADF;
        var data = gather(ptr, n);
        writeAt(f, Number(offset), data);
        view().setUint32(written, data.length, true);
        return 0;
      },
      fd_read: function (fd, ptr, n, read) {
        var got;
        if (fd === 0) {
          got = scatter(ptr, n, input.subarray(inputAt));
          inputAt += got;
        } else {
          var f = fds[fd];
          if (!f) return E.BADF;
          if (f.kind !== FILE) return E.ISDIR;
          got = scatter(ptr, n, (fs.files.get(f.path) || new Uint8Array(0)).subarray(f.pos));
          f.pos += got;
        }
        view().setUint32(read, got, true);
        return 0;
      },
      fd_pread: function (fd, ptr, n, offset, read) {
        var f = fds[fd];
        if (!f || f.kind !== FILE) return E.BADF;
        view().setUint32(read, scatter(ptr, n, (fs.files.get(f.path) || new Uint8Array(0)).subarray(Number(offset))), true);
        return 0;
      },
      fd_seek: function (fd, offset, whence, ptr) {
        var f = fds[fd];
        if (!f || f.kind !== FILE) return E.BADF;
        var size = (fs.files.get(f.path) || []).length;
        var base = whence === 0 ? 0 : whence === 1 ? f.pos : size;
        f.pos = Math.max(0, base + Number(offset));
        view().setBigUint64(ptr, BigInt(f.pos), true);
        return 0;
      },
      fd_close: function (fd) { if (fd > 3) fds[fd] = null; return 0; },
      fd_sync: function () { return 0; },
      fd_fdstat_get: function (fd, ptr) {
        var f = fds[fd];
        var kind = fd <= 2 ? 2 : f ? f.kind : 0;
        if (!kind) return E.BADF;
        var v = view();
        v.setUint8(ptr, kind);
        v.setUint16(ptr + 2, 0, true);
        v.setBigUint64(ptr + 8, ALL, true);
        v.setBigUint64(ptr + 16, ALL, true);
        return 0;
      },
      fd_filestat_get: function (fd, ptr) {
        var f = fds[fd];
        if (!f) return E.BADF;
        filestat(ptr, f.path);
        return 0;
      },
      fd_filestat_set_size: function (fd, size) {
        var f = fds[fd];
        if (!f || f.kind !== FILE) return E.BADF;
        var old = fs.files.get(f.path) || new Uint8Array(0);
        var next = new Uint8Array(Number(size));
        next.set(old.subarray(0, Math.min(old.length, next.length)));
        fs.write(f.path, next);
        return 0;
      },
      fd_filestat_set_times: function () { return 0; },
      path_filestat_get: function (fd, _, ptr, len, out) {
        var path = resolve(fd, ptr, len);
        if (path === null) return E.BADF;
        if (!fs.kind(path)) return E.NOENT;
        filestat(out, path);
        return 0;
      },
      path_open: function (dirfd, _, ptr, len, oflags, rb, ri, fdflags, out) {
        var path = resolve(dirfd, ptr, len);
        if (path === null) return E.BADF;
        var kind = fs.kind(path);
        if ((oflags & 4) && kind) return E.EXIST;
        if (oflags & 2) {
          if (kind !== DIR) return kind ? E.NOTDIR : E.NOENT;
        } else if (!kind) {
          if (!(oflags & 1)) return E.NOENT;
          fs.write(path, new Uint8Array(0));
          kind = FILE;
        } else if (kind === FILE && (oflags & 8)) fs.write(path, new Uint8Array(0));
        fds.push({ kind: kind, path: path, pos: 0, append: !!(fdflags & 1) });
        view().setUint32(out, fds.length - 1, true);
        return 0;
      },
      fd_readdir: function (fd, buf, bufLen, cookie, used) {
        var f = fds[fd];
        if (!f || f.kind !== DIR) return E.NOTDIR;
        var list = fs.children(f.path), at = 0, b = bytes(), v = view();
        for (var i = Number(cookie); i < list.length; i++) {
          var name = enc.encode(list[i][0]);
          var entry = new Uint8Array(24 + name.length), ev = new DataView(entry.buffer);
          ev.setBigUint64(0, BigInt(i + 1), true);
          ev.setBigUint64(8, BigInt(i + 2), true);
          ev.setUint32(16, name.length, true);
          ev.setUint8(20, list[i][1]);
          entry.set(name, 24);
          var k = Math.min(entry.length, bufLen - at);
          b.set(entry.subarray(0, k), buf + at);
          at += k;
          if (at >= bufLen) break;
        }
        v.setUint32(used, at, true);
        return 0;
      },
      path_create_directory: function (fd, ptr, len) {
        var path = resolve(fd, ptr, len);
        if (path === null) return E.BADF;
        if (fs.kind(path)) return E.EXIST;
        fs.dirs.add(path);
        fs.addParents(path);
        return 0;
      },
      path_unlink_file: function (fd, ptr, len) {
        var path = resolve(fd, ptr, len);
        if (fs.kind(path) !== FILE) return E.NOENT;
        fs.files.delete(path);
        fs.changed.add(path);
        return 0;
      },
      path_remove_directory: function (fd, ptr, len) {
        var path = resolve(fd, ptr, len);
        if (fs.kind(path) !== DIR) return E.NOENT;
        if (fs.children(path).length) return E.NOTEMPTY;
        fs.dirs.delete(path);
        return 0;
      },
      path_rename: function (fd, ptr, len, fd2, ptr2, len2) {
        var from = resolve(fd, ptr, len), to = resolve(fd2, ptr2, len2);
        if (fs.kind(from) !== FILE) return E.NOENT;
        fs.write(to, fs.files.get(from));
        fs.files.delete(from);
        fs.changed.add(from);
        return 0;
      },
      path_readlink: function () { return E.INVAL; },
      path_symlink: function () { return E.NOSYS; },
      path_link: function () { return E.NOSYS; },
    };
    var join = function (parts) {
      var total = parts.reduce(function (s, p) { return s + p.length; }, 0), all = new Uint8Array(total), at = 0;
      parts.forEach(function (p) { all.set(p, at); at += p.length; });
      return dec.decode(all);
    };
    // a browser instantiates a module this large only asynchronously
    return WebAssembly.instantiate(module, { wasi_snapshot_preview1: wasi }).then(function (instance) {
      memory = instance.exports.memory;
      var code = 0;
      try {
        instance.exports._start();
      } catch (e) {
        if (e instanceof Exit) code = e.code; else throw e;
      }
      return { code: code, stdout: join(out), stderr: join(err) };
    });
  }

  global.SkeinWasi = { Files: Files, run: run };
})(typeof window !== "undefined" ? window : globalThis);
