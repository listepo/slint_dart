# Agent notes — `slint_build`

Shared plumbing for every `hook/build.dart` in the repo: cargo runs through
a `bazel_worker` persistent worker and the artifact becomes a code asset.
Read the root `AGENTS.md` first.

## What lives here

| Path | Role |
|---|---|
| `lib/src/cargo_builder.dart` | `runCargoBuild` (one crate → one artifact, `cdylib` or `staticlib`), `buildCargoCrate` (the one-call FFI-package form that also emits the `DynamicLoadingBundled` code asset), `rustTriple`, cross-compile env (Android NDK, iOS, macOS), `packageRootFromConfig`. |
| `bin/cargo_worker.dart` | The persistent worker. Request: crate, manifest, triple, profile, artifact kind, env. Response: artifact path plus cargo's full output. |

Pure Dart, no tests of its own: the hooks that use it are exercised by
`flutter test` in `examples/todo` and `dart test` in `slint_testing`.

## Commands

```bash
mise exec -- dart analyze .
```

## Invariants

- **Cargo output is returned verbatim**, not just the exit code.
  `slint_compiler`'s build hook parses rustc's `native-static-libs:` note
  out of it to get the link line for the AOT relink. Don't filter or
  truncate the worker's stdout/stderr.
- **`packageRootFromConfig(packageConfig, name)` is how hooks find sibling
  packages** — through `.dart_tool/package_config.json`, because
  `Isolate.resolvePackageUri` is unavailable inside hooks and build_runner
  builders. It resolves the worker script (`bin/cargo_worker.dart`) too, so
  it works wherever the package is checked out, including under
  `packages/`.
- **Source dirs passed as `dependencies` are the hook's cache key.** A hook
  that forgets to list a crate its crate depends on (e.g. `../slint/rust/`)
  will not rebuild when that crate changes. The FFI hooks list every path
  dependency explicitly.
- **The cargo profile defaults to `release`** (debug Slint rendering is
  unusably slow) and is switched per package via pubspec user-defines
  (`hooks.user_defines.<pkg>.profile`), read from the workspace root
  pubspec. User-defines are hook input, so changing them invalidates the
  cache correctly.
- **Artifact copies, not symlinks.** The artifact is copied into the hook's
  output directory; Flutter bundles from there.

## Traps

- The worker script runs from source (`Process.start(dart, [...])`), so a
  syntax error in `bin/cargo_worker.dart` surfaces as a hook failure in
  whichever package builds first, not as an analyzer error here — run
  `dart analyze .` in this package before testing a hook change.
- A failing cargo build reports through the hook of the *consuming*
  package (`slint_interpreter`, `slint_testing`, the AOT app); read the
  cargo output the worker returned rather than re-running cargo by hand
  with guessed flags.
