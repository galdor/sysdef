# SYSDEF
## Project
SYSDEF is yet another system facility. While Common Lisp supports packages, they
are collections of symbols and have no support to deal with full projects and
the various artifacts they contain.

Historically this is what the term "system" has been used for. See for example
[mk-defsystem](https://www.cliki.net/mk-defsystem), LispWork's [Common
Defsystem](https://www.lispworks.com/documentation/lw60/LW/html/lw-289.htm) and
of course the very well known [ASDF](https://asdf.common-lisp.dev).

The author was curious about what it really takes to build a minimal system
loader. SYSDEF is the result. ASDF is ~14k LoC. The initial version of SYSDEF is
394 LoC.

SYSDEF supports a minimal set of metadata, an extensible collection of
components (builtin support for static files, Common Lisp source files and
component groups), and two fundamental operations (build and load).

Seems to be working as it should on a Linux machine with SBCL, CCL and ECL

I may add more features in the future. Or not.

## Usage
You probably should not use it.

If you do:
- Configure `SYSDEF:*SYSTEM-DIRECTORIES*` to point at directories containing
  `.cls` files.
- Call `SYSDEF:INITIALIZE-REGISTRY`.
- Call `SYSDEF:LOAD-SYSTEM` to (re)load a system.

## Licensing
SYSDEF is open source software distributed under the
[ISC](https://opensource.org/licenses/ISC) license.

## Contributions
### Bug reporting
I am thankful for any bug report. Feel free to open issues and include as much
useful information as possible. I cannot however guarantee that I will fix every
bug.

### Ideas and feature suggestions
Ideas about current systems and suggestions for new ones are welcome, either on
GitHub discussions or by [email](mailto:nicolas@n16f.net).

You can also [hire me](mailto:nicolas@exograd.com) for support or to develop
specific features.
