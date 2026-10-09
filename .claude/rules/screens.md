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
| compact | < 600 | floating dock (the shell's `_Dock`, in the Scaffold's bottom bar slot) | one pane; details open as a bottom sheet over the map, the dock gives way to the place's action bar |
| medium | 600 to 839 | the shell's rail with labels | one pane, wider margins; details in a side panel |
| expanded | >= 840 | the wide rail with the brand lockup | map plus list and detail panes side by side |

The design system (`app/lib/shared/theme/`) themes every Material component;
the shell draws its own dock and rail rather than `NavigationBar` and
`NavigationRail`. A message goes through `showMessage`
(`app/lib/shared/messages.dart`), never a bare `showSnackBar`: it replaces
the message shown, and one with an action (undo) still leaves by itself,
except under a screen reader where it waits to be closed. A bar of actions
at the bottom of the window wraps itself in `LiftsMessages`; the shell then
floats every message above it, on a phone as on a panel's foot. Never
position a message by hand.

Every notice follows one rule (`app/lib/shared/notices.dart`). A passing
notice (something that just happened) shows 4 s, 6 s with an action,
fades, closes at a tap or a swipe towards its edge; one at a time, the
latest in place of the one shown unless that one matters more
(`NoticePriority`). A standing notice (a state that lasts) stays while its
state holds, folds into a chip at a tap or a swipe up (a swipe alone when
it has a tap of its own, the map's offline line), and opens again when its
`level` rises. A screen reader hears each once: no live region on a
text whose figures change. `showMessage` is the passing notice of every
screen; a screen that shows notices its own way takes the app's messages
while it is up (`redirectMessages`, the guidance under its maneuver,
`NoticeColumn` in `shared/widgets/notice_views.dart`).

An element meant to be centred over the screen or the map (a floating
button, a card, a notice) centres on the whole screen, or on the map beside
the rail or a fixed panel, and moves aside only as far as a column of
buttons, a panel or a camera cut-out it would cover requires:
`CentredClear` (`app/lib/shared/widgets/centred_clear.dart`), never a
`Center` inside the room a column leaves. A message centres the same way, on
the `MessageStage` of the screen shown (`app/lib/shared/messages.dart`), else
on the page beside the rail, and a button over the map wrapped in
`PushesMessagesAside` moves it aside; the route preview, outside the shell,
sets its `messageInsets`, and the guidance shows the messages with its
notices under the maneuver, across the banner's width.
`test/widget/centring_test.dart` measures each against the screen.

The shell (`app/lib/shared/adaptive_shell.dart`) owns the navigation; a
screen never builds its own bar or rail.

## The audience

Many users are 55 to 75 and read the app at arm's length in a van cab. So:

- touch targets of 48 dp at least, text from the theme's text styles (they
  follow the system font scale), never a fixed font size in a widget. With a
  mouse in a medium or expanded window (`pointerDensity`,
  `app/lib/core/layout/pointer_input.dart`) the theme is a notch denser:
  compact visual density, text a point smaller. A control the app draws
  itself takes its height from `controlHeight(context, touch)`, never a bare
  number, so it follows;
- contrast from the colour scheme roles (`onSurface`, `onPrimaryContainer`),
  never a hard-coded grey;
- one primary action per screen, named with a verb;
- every icon-only button carries a tooltip (it is also the semantics label).

## The mouse

Everything that reacts to a click shows the pointing hand, on every
platform (Material keeps it for the web only), and the arrow once disabled.
The theme sets it for buttons, menus and toggles; an `InkWell`, a chip or a
dropdown takes `mouseCursor: WidgetStateMouseCursor.clickable`, a
`GestureDetector` with a tap sits in a `MouseRegion` with
`SystemMouseCursors.click`, a drag handle the app draws shows the axis it
moves (`resizeUpDown`) or `grab`. A modal sheet opens through `showSheet`
(`app/lib/shared/widgets/modal_sheet.dart`), whose handle shows the hand
and closes the sheet on a click: Material's own keeps the arrow, out of
the theme's reach (gate: `structure_check` rule `sheet-handle`). A `ListTile` with no tap of
its own, as in a menu item, leaves the cursor to what holds it (set in
the theme). `test/widget/mouse_cursor_test.dart` hovers the screens and
fails on a control without its cursor; a new screen joins it.

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
