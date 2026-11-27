const std = @import("std");

pub const zon = @import("../build.zig.zon");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const options = b.addOptions();
    options.addOption([]const u8, "version", zon.version);
    // for the tests that check the example projects, and the list of templates
    options.addOptionPathUntracked("examples_dir", b.path("examples"));
    options.addOptionPathUntracked("templates_dir", b.path("templates"));

    // the templates, built into the program
    const templates = b.createModule(.{ .root_source_file = b.path("templates/__root__.zig") });

    const mod = skein(b, target, optimize, options, templates);

    const exe = b.addExecutable(.{
        .name = "skein",
        .root_module = mod,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.addPassthruArgs();
    const run_step = b.step("run", "Run skein");
    run_step.dependOn(&run_cmd.step);

    // skein built for WebAssembly, for the static site's edit mode (`render --edit`)
    const wasm = b.addExecutable(.{
        .name = "skein",
        .root_module = skein(b, b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi }), .small, options, templates),
    });
    const install_wasm = b.addInstallArtifact(wasm, .{ .dest_dir = .{ .override = .{ .custom = "web" } } });
    b.step("wasm", "Build skein for WebAssembly, for render --edit: zig-out/web/skein.wasm").dependOn(&install_wasm.step);

    const tests = b.addTest(.{ .root_module = mod });
    const test_step = b.step("test", "Run skein's unit tests");
    test_step.dependOn(&b.addRunArtifact(tests).step);

    // the generator of the npr7150.2d template's requirements, run by hand
    // when NASA revises the NPR; not part of the skein program
    const npr = b.createModule(.{
        .root_source_file = b.path("tools/npr7150/__main__.zig"),
        .target = target,
        .optimize = optimize,
    });
    // skein's own code, shared rather than copied
    npr.addImport("skein", mod);
    const npr_run = b.addRunArtifact(b.addExecutable(.{ .name = "npr7150", .root_module = npr }));
    npr_run.addPassthruArgs();
    b.step("npr7150", "Write NPR 7150.2D as skein documents: -- HTML_DIR OUT_DIR RETRIEVED").dependOn(&npr_run.step);
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = npr })).step);

    // the text of a PDF, for the generators of templates from standards published as PDF
    const pdf = b.createModule(.{
        .root_source_file = b.path("tools/pdf/__main__.zig"),
        .target = target,
        .optimize = optimize,
    });
    const pdf_run = b.addRunArtifact(b.addExecutable(.{ .name = "pdftext", .root_module = pdf }));
    pdf_run.addPassthruArgs();
    b.step("pdftext", "Write the text of a PDF: -- FILE.pdf OUT.txt").dependOn(&pdf_run.step);
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{ .root_module = pdf })).step);
}

/// The skein program's module, for `target`
fn skein(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.lang.Optimize, options: *std.Build.Step.Options, templates: *std.Build.Module) *std.Build.Module {
    const mod = b.createModule(.{
        .root_source_file = b.path("src/__root__.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod.addOptions("build_options", options);
    mod.addImport("templates", templates);
    // code of other projects built into skein: mermaid.js
    mod.addImport("vendor", b.createModule(.{ .root_source_file = b.path("vendor/__root__.zig") }));
    return mod;
}
