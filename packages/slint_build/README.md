# slint_build

Shared plumbing for native-assets hooks: every `hook/build.dart` drives cargo
through this package (persistent `bazel_worker`) instead of shelling out
itself. Used by the FFI packages and the AOT build/link hooks.

```yaml
dependencies:
  slint_build: ^0.1.0
```

**Full docs:** see the docs site (`just docs-serve`) — package page under
Packages. Cargo profile defaults and user-defines are also covered in the
root README.
