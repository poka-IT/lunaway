---
paths:
  - "app/test/**"
  - "app/integration_test/**"
---
# Dart tests

## What a test must be

- **It fails without the code it covers.** Before keeping a test, ask what
  change in `lib/` would turn it red; if the answer is "none", it is hollow.
- **It asserts behaviour a user or a caller sees**: a text on screen, a
  navigation, a value a provider exposes, a request sent. Not that a widget
  type exists for its own sake.
- **It names the behaviour**: `'a phone width gets the bottom navigation bar'`,
  not `'test 1'`.

## Layers

| layer | where | runs | covers |
|---|---|---|---|
| unit | `test/unit/` or next to the feature | `fvm flutter test` | services, parsers, mappers, scoring, pure providers through `ProviderContainer.test()` |
| widget | `test/` | `fvm flutter test` (headless) | a screen or a flow with fakes: navigation, layouts per width class, empty, loading and error states, translations |
| golden | `test/goldens/` | `fvm flutter test --tags golden` | the visual result of key screens per width class and theme, reviewed as images |
| integration | `integration_test/` | `fvm flutter test integration_test -d macos` | the real app on a real engine: startup, map, storage |

Fakes over mocks: a fake repository implementing the same interface, injected
with a provider override. Network calls never leave a unit or widget test.

## Practicalities

- Set the surface size per width class with `tester.view.physicalSize` and
  `addTearDown(tester.view.reset)`.
- Set the locale explicitly in `setUp` (`LocaleSettings.setLocale`), so a test
  does not depend on the machine's language.
- `pumpAndSettle` only when an animation must finish; a stream or a timer that
  never settles needs `pump(duration)`.
- A unit test of a timer (retries, waits) runs under `fakeAsync` (package
  `fake_async`, a dev dependency) and moves the clock with `elapse`; it never
  sleeps on real time (`test/unit/sync_retry_test.dart`).
- Recorded responses of external services live in `test/fixtures/`, trimmed
  to what the test reads.
- An integration test that reads an auto-disposed provider's future listens
  to it while it waits (`integration_test/fixtures/listened.dart`): read
  alone, a provider no widget watches is disposed before it emits.
- What only the screen shows (a map frozen on its last frame while its
  engine moves) is checked by the host: `tool/screens/capture.py` answers
  the system's location prompt (`ALLOW LOCATION`) and compares two shots
  (`CHECK MOVED <a> <b>`); `integration_test/location_grant_test.dart`
  shows the use.
