# NetHackSwift

Native SwiftUI/Objective-C Mac app wrapping NetHack 5.0 as a static library (`libnh.a`).
Bundle ID `com.Bryceco.NetHackSwift`. Sandboxed.

## Three sibling repos

All three live side by side in the same parent directory. A change often spans more than one; check whether the boundary you're about to widen belongs in the shim instead.

| Repo | What it is | Built with |
| --- | --- | --- |
| `NetHack` | Upstream C NetHack 5.0. Keep changes minimal. | `make` (see below) |
| `NetHackSwiftLib` | Swift package; Objective-C shim implementing the C/Swift boundary. | Xcode |
| `NetHackSwift` | Pure Swift/SwiftUI app. Depends on `NetHackSwiftLib`. | Xcode |

## NetHack repo

This is a fork of the NetHack repo at https://github.com/NetHack/NetHack/  We want to minimize changes here, or at least keep them restricted to our windowport. Our fork adds files at:
* sys/unix/hints/macOS.swift
* win/swift/*

### Building

We compile NetHack as a library. Build `libnh.a` from the `NetHack` root, using our hints file and WANT_LIBNH:

```sh
make spotless && (cd sys/unix && ./setup.sh hints/macOS.500) && \
make WANT_LIBNH=1 WANT_DEFAULT=swift all
```

<!-- FIXME(bryce): the fork section says we add hints/macOS.swift but the command
     passes hints/macOS.500. Fix whichever is wrong and delete this comment. -->

The `make spotless` and `setup.sh` steps are not optional after a hints change —
skipping them means testing a stale Makefile.

#### Editing the hints file

- Use `NHCFLAGS+=`, not `CFLAGS+=`. `NHCFLAGS` fans out to both `CFLAGS` and `CCXXFLAGS`; a plain `CFLAGS` line is appended later in the Makefile and silently wins.
- Swift windowport objects go in `LIBNHSYSSRC` / `LIBNHSYSOBJ`, **not** `WINSRC` / `WINOBJ` — `WINOBJ` gets clobbered by `WINOBJ0`.

#### Never assume a define took effect

```
grep -n "THE_DEFINE" src/Makefile      # did it reach the Makefile
nm -gU src/libnh.a | grep symbol        # did it change what got compiled
```

The grep alone is not proof: a `#ifndef WIN32 / #undef / #endif` guard elsewhere can discard a command-line `-D` silently. For `NOCWD_ASSUMPTIONS` the definitive test is whether `fqname` is a real symbol rather than a pass-through macro.

#### Defines currently in effect for the libnh build

`SWIFT_GRAPHICS`, `NOCWD_ASSUMPTIONS`, `SELF_RECOVER`, `DLB`. `CHDIR` is disabled.

`SYSCF` is set without a directory. sysconf is read before the prefix system is trustworthy — sysconf itself may set prefixes — so NetHack never routes it through `fqname()`, on any build. There is no prefix-based fix. The app chdirs to `Bundle.main.resourceURL.path` at startup so sysconf resolves against it.

`CHDIR` is off because the app owns the working directory. Do not re-enable it — `chdirx()` would run during init and take that control back.

`NOCWD_ASSUMPTIONS` is on so the playground can live in a writable location independent of cwd. Consequences:

- `fqn_prefix[]` must be assigned **after** NetHack's early init, which wipes globals. This is why we own `main()` rather than calling `nhmain()`.
- Every prefix must be non-NULL before the first file access, or it's a null deref rather than a fallback to cwd.

### Windowport (`win/swift/`)

- `winswift.h` is plain C with **no NetHack includes** — it is consumed by the Swift side. Member names are camelCase to avoid collisions with `winprocs.h` macros.

- `winswift.c` implements `struct window_procs` and forwards to a registered `nhswift_callbacks` struct with typed callbacks.
- The `anything` union crosses the boundary as `uint64_t` via `memcpy`. Do not expose NetHack internals to Swift.
- The C layer stays a thin forwarding shim. Swift owns window ID allocation.
- Avoid the identifier `gi` and other 2-letter identifiers that can collide with #defines in NetHack's code.

Registering a windowport touches three places, and missing one fails late rather than at compile time: `wp_ids` in `winprocs.h`, `window_opts[]` in `makedefs.c`, and `windowing_sanity()`.

Feature gates that enumerate windowports by name usually need `SWIFT_GRAPHICS` added alongside `SHIM_GRAPHICS`. Grep for `SHIM_GRAPHICS` when a feature is mysteriously absent.

## NetHackSwiftLib

This package implements the interface between the flat C functions/data given to us by winswift.c and pure Swift delegate functions handled by NetHackSwift.

It is written in Obj-C and is built using Xcode.

The NetHack library is invoked on a background thread, so callbacks are synchronously dispatched to the main thread to be processed by the delegate (NetHackSwift). NetHack's window procs are synchronous and expect to block — don't restructure that control flow to suit Swift concurrency.

We want to minimize the amount of code in this layer, just enough to translate between the C structs and something Swift can consume.

## NetHackSwift

This is the main GUI app for playing NetHack.

### Paths and sandboxing

Read-only, in the app bundle's Resources, version-locked to the binary:
`sysconf`, `nhdat`, tiles PNG files, etc.

Writable, in the Application Support container: `perm`, `record`, `logfile`, `xlogfile`, `livelog`, `save/`. `perm` must exist before the game starts — these are copied from the Playground folder in Resources at program start.

`nh_getenv()` silently returns NULL for values over `BUFSZ/2` (128 chars). DerivedData paths exceed this. If an environment-supplied path appears to be ignored, check its length before anything else.

## Style

- Explicit, readable Swift over functional-style chaining.
- Small, correctness-driven changes. Don't refactor adjacent code unasked.
- When something is uncertain, ask for clarification or guidance.
