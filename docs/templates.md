# Templates

A template is a way of working that comes with skein: the item types, link types and profiles a kind of project needs. A project of that kind names it in one line rather than writing them out in every repository:

```toml
# .skein/config.toml
template = "langspec"

[[sources]]
path = "spec"
```

The project then has the template's types and links as if they were in its `.skein/`. A file of its own of the same name, `.skein/types/rule.toml` say, replaces the template's: so a project takes what fits and changes the rest.

```text
$ skein template list
langspec  The specification of a programming language: rules, terms, and examples that show them

$ skein template show langspec
```

## Several templates, and options

A project can use several, for what it is at once: `template = ["langspec", "npr7150.2d"]`. Two templates that declare the same name are reported, until the project declares that name itself.

A template can take options, which choose among what it declares: a software class, whether software is safety-critical. They are given in a table per template:

```toml
[template.npr]
name = "npr7150.2d"
class = "C"
safety-critical = false
```

`skein template show NAME` lists a template's options, their values and their defaults. An option the template does not have, or a value it does not allow, is reported.

## The templates

| Template | For |
| --- | --- |
| `langspec` | The specification of a programming language: rules (syntax, legality, static and dynamic semantics), terms, and examples that show the rules (tested examples). |

More are planned: NASA NPR 7150.2D, and requirements as ISO/IEC/IEEE 29148 describes them.

## Writing one

A template is a directory of `templates/` in skein's repository, laid out as `.skein/` is (`types/`, `links/`, `profiles/`), with a `template.toml`:

```toml
description = "What it is for, in one line"

[options.class]
description = "The software class of the project"
values = ["A", "B", "C", "D", "E", "F"]
default = "C"
```

In its files, `{{class}}` is written as the value of the option. Every file of `templates/` is listed in `templates/__root__.zig`, which builds them into skein; a test holds the list to the directory.
