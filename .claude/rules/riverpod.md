---
paths:
  - "app/lib/**/application/**"
  - "app/lib/core/**"
  - "app/test/**"
---
# Riverpod conventions

Riverpod 3 with code generation: `@riverpod` / `@Riverpod(keepAlive: true)`
on a function or a class, `part '<file>.g.dart'`, then
`fvm dart run build_runner build` in `app/`. riverpod_lint runs as an analyzer
plugin and reports only through `fvm dart analyze` (`flutter analyze` does not
load plugins; measured 2026-10-05).

## Rules

- **Pick the shape by use case.**

  | use case | declaration |
  |---|---|
  | a service, a repository, a client | `@Riverpod(keepAlive: true)` function |
  | a cached async read | `@riverpod` `Future<T>` function |
  | mutable state | `@riverpod class X extends _$X` with `build()` |
  | parameterised | arguments on the function or on `build()` |

  No `StateProvider`, `StateNotifierProvider` or `ChangeNotifierProvider`
  (they live in `legacy.dart` for migrations only). Gate: `structure_check`
  rule `no-legacy-provider`.
- **`ref.watch` in `build`, `ref.read` in methods.** Never `ref.watch` after an
  `await` inside `build`: the dependency is registered too late.
- **Check `ref.mounted` after every `await`** in a notifier method before
  touching `state`; the provider may have been disposed meanwhile.
- **`keepAlive` carries a one-line comment** saying why the value must outlive
  its listeners. Default to auto-dispose.
- **Never `ref.invalidateSelf()` to refresh**; expose a method that sets
  `state` explicitly, so the UI keeps its previous value while reloading.
- **Never swallow a `build()` failure into an empty value.** Throw; the UI
  renders `AsyncError`. An empty list and a failed load are different screens.
- **Retry.** Riverpod 3 retries a failing provider with exponential backoff.
  A failure the user must see at once (refused request, validation error)
  opts out: `@Riverpod(retry: noRetry)` with `Duration? noRetry(int _, Object _) => null;`.
- **Off-screen pollers pause.** Riverpod 3 pauses providers whose widgets are
  not visible; a provider holding a timer or a stream also stops it in
  `ref.onCancel` and restarts in `ref.onResume`.
- **Services stay stateless and testable without a container**; the provider
  only wires them.

## Tests

`ProviderContainer.test()` for unit tests; `overrideWith` / `overrideWithValue`
to inject fakes; `WidgetTester.container` in widget tests. See
`.claude/rules/dart-tests.md`.
