---
paths:
  - "app/lib/**/presentation/**"
  - "app/lib/shared/**"
---
# Screens and widgets

## One screen, three layouts

`WindowSize.of(context)` (`app/lib/core/layout/window_size.dart`) gives the
Material 3 width class; every screen works in all three.

| class | width | frame | content |
|---|---|---|---|
| compact | < 600 | bottom `NavigationBar` | one pane; details open as a bottom sheet over the map |
| medium | 600 to 839 | `NavigationRail` with labels | one pane, wider margins; details in a side sheet |
| expanded | >= 840 | extended `NavigationRail` | map plus list and detail panes side by side |

The shell (`app/lib/shared/adaptive_shell.dart`) owns the navigation; a
screen never builds its own bar or rail.

## The audience

Many users are 55 to 75 and read the app at arm's length in a van cab. So:

- touch targets of 48 dp at least, text from the theme's text styles (they
  follow the system font scale), never a fixed font size in a widget;
- contrast from the colour scheme roles (`onSurface`, `onPrimaryContainer`),
  never a hard-coded grey;
- one primary action per screen, named with a verb;
- every icon-only button carries a tooltip (it is also the semantics label).

## Text and data

- Every string a user reads comes from slang (`context.t`), never a literal
  (`.claude/rules/translations.md`).
- Every value shown that came from a source shows where it came from: the
  source badge, its licence attribution on the detail screen
  (`.claude/rules/data-sources.md`).
- Empty, loading and error are three distinct states with their own text; an
  `AsyncValue` is rendered with `switch` over its three cases.

## Motion and fluidity

- No layout jump: reserve the space of an image or a list item before it
  loads (fixed aspect ratio, skeleton).
- Lists over a few dozen items use a builder (`ListView.builder`,
  `SliverList`); markers on the map go through the map's clustered source,
  never one widget per spot.
- Animations use the theme durations and curves; nothing blocks the UI
  thread (parsing and clustering of large payloads run in an isolate).
