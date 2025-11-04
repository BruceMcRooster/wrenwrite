# ˏ₍๏ɞ๏₎ˎ WrenWrite

WrenWrite (or Wren, for short) is a super fast, minimal, single-executable blogging tool.
It’s heavily inspired by [ʕ•ᴥ•ʔ Bear](https://bearblog.dev) and more generally by minimal, no-nonsense blogs.

Interested? Check out [an example blog](https://brucemcrooster.dev) or [set it up for yourself](#getting-started)

> [!WARNING]
> Wren is in the very early stages of development. Many features that you might expect are not available, and you are likely to run into bugs.
> If you do run into bugs, open a [GitHub Issue](https://github.com/BruceMcRooster/wrenwrite/issues/new) and/or [reach out to me](https://brucemcrooster.dev/contact).

## Getting Started

### Dependencies
* [Swift](https://www.swift.org/install/)
* macOS, or Linux or Windows if you’re really brave. Wren is currently only tested on macOS, though it is a goal to support more platforms in the future.

### Installing
1. Download from GitHub
```
git clone https://github.com/brucemcrooster/wrenwrite && cd wrenwrite
```
2. Clone submodules
```
git submodule init
```
3. Build
```
swift build
```

You can now use the executable in `/path/to/wrenwrite/.build/<my-platform>/debug/WrenWrite`.

## Usage

Everything in Wren centers around a single folder for your site. Currently, Wren will not traverse into any subdirectories of the folder you run the tool in.

The absolute minimum you need to make a site is one file in a folder, `index.md`.
Include the following at the top of the file to configure your site.
```markdown
---
title: your site title
---
Your wonderful content in markdown
```
Your title will be displayed in the header of the site and in the meta description.
You can optionally (and I recommend you do) add `description:` to give a meta description to your site, and `url:` to use in meta tags as the canonical url.

Once you have a site set up, run the executable you generated (`/path/to/wrenwrite/.build/<my-platform>/debug/WrenWrite`) from the directory you created your site in, and a fully static set of html files will be generated in the `dist/` folder inside your project folder.
You can then host these HTML files anywhere you like (GitHub Pages, Cloudflare Pages, etc.).
To preview your site locally, I like to navigate into the `dist/` folder and run `python3 -m http.server` to serve the site locally to `localhost:8000`.

### Customizing navigation
Add a file called `nav.md` to your site’s root directory. Anything of the form [Destination Title](destination url) will be added to your navigation bar. Two items will always appear in your navigation: "Home" and "Blog"

### Creating pages
Any pages in the root directory besides `index.md` and `nav.md` will be converted to pages. The following metadata is available as options, but has default values listed here.
```markdown
---
title: "Untitled"
description: uses site metadescription
date: yyyy-MM-dd format, uses date of generation by default
is_page: false; will be listed on the blog posts list, will include post title and date at top of page
---
```

### Supported markdown
Wren’s markdown generation is powered by [md4c](https://github.com/mity/md4c/), which is fully CommonMark compliant.
Wren also enables a few extensions:
* [GitHub-flavored tables](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/organizing-information-with-tables)
* ~~Strikethrough~~ using `~~Strikethrough~~` and <ins>underline</ins> using `__underline__`
* [x] Checkboxes using `[ ]` for unchecked and `[x]` for checked

## License

WrenWrite is licensed under the MIT license.

It uses code from [md4c](https://github.com/mity/md4c/), which is also licensed under the MIT license.
It also references code from [Bear Blog](https://github.com/HermanMartinus/bearblog), specifically code from before the licensed was changed to less permissive than the MIT license so that this project can remain MIT licensed. You can see my fork [here](https://github.com/HermanMartinus/bearblog), frozen at the commit just before the license change.

## Acknowledgements

First of all, the incredible work of [Herman Martinus](https://herman.bearblog.dev/) on [Bear Blog](https://bearblog.dev) was a major inspiration for this project.
In many cases (especially in the current state of the project), it takes code directly from his work to power this version.
Wren is in no way supposed to replace the amazing platform and community he has built. It is merely a self-hostable alternative and an exploratory project for me.

Secondly, the incredible work of [Martin Mitáš](https://github.com/mity) on [md4c](https://github.com/mity/md4c/) makes the project possible.
The simplicity of only a few C files makes using the markdown parser he built a breeze, and the speed and extensibility of md4c is something that is both useful now and will be even more useful as Wren matures.
