# slint_dart

https://github.com/listepo/slint_dart

Slint UI toolkit ↔ Flutter integration.

| # | Status | Priority | Complexity | Readiness | Agent |
| --- | --- | --- | --- | --- | --- |
| T2 | in progress | P2 | 2 | 70% | Grok Bot |

### T2. Regenerate `slint_skia` ffigen bindings (drop stale `texture_id`)

After T1 removed `slint_skia_instance_texture_id` from the C ABI, `packages/slint_skia/rust/include/slint_skia_ffi.h` no longer declares it, but the committed `packages/slint_skia/lib/src/bindings.g.dart` still exports `slint_skia_instance_texture_id`. Nothing calls that symbol (platforms use attach/detach + Flutter texture ids via the channel), yet the stale binding is misleading and will break if anything ever imports it. Platform attach/detach/pixels stay excluded in `ffigen.yaml` and hand-declared `@Native` in `skia_native.dart` by design — regeneration must not duplicate them.

**Why now:** Ivan explicitly claimed this optional follow-up from `ideas.md` / T1 done notes; one-shot ffigen is allowed for this task only. The local ban on `cargo build/check/clippy` of `slint-skia-ffi` and on flutter-building `todo_skia` stays.

**Steps:**
1. On fresh `main` (`b07a2de`), branch `chore/ffigen-slint-skia-bindings`.
2. Claim this card; clear the optional bullet from `ideas.md`.
3. Refresh the C header if needed: `just bindings slint_skia` (cbindgen → `packages/slint_skia/rust/include/slint_skia_ffi.h`, then `dart run ffigen --config ffigen.yaml` under `packages/slint_skia`). Do **not** compile Skia.
4. Diff `bindings.g.dart`: confirm `slint_skia_instance_texture_id` is gone; shared ABI symbols (`last_error`, engine/compile/instantiate, set_size/render, pointer/key/property/invoke, …) remain; excluded platform symbols (`attach_*`, `pixels`, `detach`) are **not** present in `bindings.g.dart` (still only in `skia_native.dart`).
5. Update `packages/slint_skia/AGENTS.md`: bindings are no longer stale; clarify that the standing ban is on building Skia / routine local ffigen, while this one-shot regen was intentional; drop the upgrade-path bullet about regenerating for `texture_id`.
6. Local checks that do not build Skia: `mise exec -- dart format` on touched Dart under `packages/slint_skia`, `mise exec -- dart analyze .` in that package (`bindings.g.dart` remains excluded in `analysis_options.yaml` — fine).
7. Commit (English), open PR, `gh workflow run ci.yml --ref <branch>`, wait green (max 10 attempts), merge. Move this card to `done.md` and clear the plan row.


**ffigen quirk:** the C header uses raw `void*` (no named opaques like `slint_interpreter`), so ffigen emits `Pointer<Void>` and a large macOS system-header tail (~1.5k lines, same shape as the interpreter bindings). The old short `bindings.g.dart` had hand-added `SlintSkiaEngine` / `SlintSkiaInstance` / `SlintSkiaDefinitionList` aliases; those are gone. `skia_engine.dart` now uses `Pointer<Void>` like `skia_native.dart`. Platform `@Native`s remain hand-declared by design.

**Check:**
- `rg texture_id packages/slint_skia/lib/src/bindings.g.dart` is empty.
- `rg 'slint_skia_instance_(attach_|pixels|detach)' packages/slint_skia/lib/src/bindings.g.dart` is empty (no duplicates of `skia_native.dart`).
- Shared `slint_skia_*` ABI symbols still present in bindings.
- `dart analyze` clean for package rules; CI green on the branch; Skia was never built locally.
