//! The documentation site (#322): tools/site.sh puts the pages together,
//! `gen` turns them into what Zine builds, and Zine writes the site.
//!
//!   zig build -Dcontent=DIR -p OUT    the site in OUT/public
//!   zig build serve -Dcontent=DIR     Zine's live server
//!   zig build test                    the generator's tests

// cspell:ignore Dcontent

const std = @import("std");
const zine = @import("zine");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const content = b.option([]const u8, "content", "The pages, as tools/site.sh puts them together") orelse "../.site/md";

    // the pages to the input of Zine: content/, assets/site-index.json
    const gen_exe = b.addExecutable(.{
        .name = "skein-site-gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("gen/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const gen = b.addRunArtifact(gen_exe);
    gen.setCwd(b.path("."));
    gen.has_side_effects = true;
    gen.addArgs(&.{ "--content", content, "--pages", "pages.txt", "--site", "." });
    b.step("gen", "Write the input of Zine from the pages").dependOn(&gen.step);

    const site = zine.website(b, .{
        .website_root = b.path("."),
        .output_path = "public",
        .force = true,
    });
    site.step.dependOn(&gen.step);
    b.getInstallStep().dependOn(&site.step);

    const serve = zine.serve(b, .{ .website_root = b.path(".") });
    serve.step.dependOn(&gen.step);
    b.step("serve", "Start the Zine dev server").dependOn(&serve.step);

    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("gen/__root__.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.step("test", "Run the tests of the generator").dependOn(&b.addRunArtifact(tests).step);
}
