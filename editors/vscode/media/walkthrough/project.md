# A Skein project

A project is a directory with a `.skein/` directory in it: `.skein/config.toml` says where the documents are, and `.skein/types/` and `.skein/links/` the kinds of items and links.

**Skein: Initialize a Project...** runs `skein init` in a folder of the workspace, with one of the templates built into Skein, or none. A workspace may hold several projects, in its folders or inside them; the views follow the project of the file in the active editor, and **Skein: Choose Project...** picks another.
