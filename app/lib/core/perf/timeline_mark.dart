import 'dart:developer' as developer;

/// Marks [name] on the timeline, for the measurements of a profile build:
/// a slice of no length rather than an instant, because an Android system
/// trace (Perfetto, the app started with `trace-systrace`) drops the
/// timeline's instants. A release build records no timeline.
void timelineMark(String name) {
  developer.Timeline.startSync(name);
  developer.Timeline.finishSync();
}
