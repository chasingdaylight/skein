# Changelog

## 0.1.1 (unreleased)

- The extension carries the `skein` program for its platform and puts it on the `PATH` of new terminals, so `skein check` works there with nothing else installed. There is a package for Windows, Linux, Alpine and macOS, each for x86_64 and arm64; other platforms get the package without a program.
- The setting `skein.path` names another `skein` to use, and the command "skein: Show Version" says which one is in use.

## 0.1.0

- Highlighting of skein's item markers (`%type[id words key=value]`) and references (`%[id]`, `%[id words]`) in Markdown files.
