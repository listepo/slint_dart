# slint_build

Shared plumbing for the repo's native-assets hooks: every `hook/build.dart`
drives cargo through this package instead of shelling out itself.

## API

- `runCargoBuild(...)` — build one crate for the hook's target and copy the
  artifact into the hook output directory. Parameters cover the crate name
  and manifest, the artifact kind (`cdylib` default, `staticlib` for the AOT
  link-hook path), extra env (e.g. `RUSTFLAGS=--print=native-static-libs`),
  and source dirs registered as hook dependencies. Returns the bundled
  artifact URI plus cargo's combined output — the AOT build hook parses
  rustc's `native-static-libs:` note out of it.
- `buildCargoCrate(...)` — the one-call convenience for FFI packages
  (`slint_interpreter`, `slint_skia`): `runCargoBuild` plus emitting the
  cdylib as a `DynamicLoadingBundled` code asset.
- Target-triple mapping (`rustTriple`) and cross-compile env for Android
  NDK / iOS / macOS.

## The worker

Cargo runs inside a `bazel_worker` persistent worker
(`bin/cargo_worker.dart`), so repeated hook invocations reuse one process.
The request names the crate, manifest, triple, cargo profile, artifact kind,
and env; the response carries the artifact path and the full cargo output.

The cargo profile defaults to `release` (debug Slint rendering is unusably
slow) and is switched per package via pubspec user-defines — see the root
README's "Native assets build" section.
