import 'package:meta/meta.dart';

/// A span during which a place is open, in UTC. The server computes them from
/// the OSM `opening_hours` text for the 14 days after the sync, so the app
/// answers "open now?" offline without parsing the syntax itself.
@immutable
final class OpeningInterval {
  const new(this.start, this.end);

  final DateTime start;
  final DateTime end;

  @override
  bool operator ==(Object other) =>
      other is OpeningInterval && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

/// How long the intervals of a sync stay meaningful.
const openingWindow = Duration(days: 14);

/// Whether a place is open at a moment, and until when.
@immutable
sealed class OpeningState {
  const new();
}

/// Open, and the intervals say when it closes.
final class OpenUntil extends OpeningState {
  const new(this.closesAt);

  final DateTime closesAt;
}

/// Open until past the end of the known window (often: around the clock).
final class OpenThroughWindow extends OpeningState {
  const new();
}

/// Closed, and the intervals say when it opens.
final class ClosedUntil extends OpeningState {
  const new(this.opensAt);

  final DateTime opensAt;
}

/// Closed for the rest of the known window.
final class ClosedThroughWindow extends OpeningState {
  const new();
}

/// The state at [now] from [intervals] valid until [validUntil]; null when the
/// answer would be a guess: no intervals, or a window that has run out.
OpeningState? openingStateAt(
  List<OpeningInterval>? intervals,
  DateTime now, {
  required DateTime? validUntil,
}) {
  if (intervals == null || validUntil == null || !now.isBefore(validUntil)) return null;
  final sorted = [...intervals]..sort((a, b) => a.start.compareTo(b.start));
  // Adjacent spans (one ending at midnight, the next starting there) read
  // as one opening: "closes at 02:00", not "closes at midnight".
  final merged = <OpeningInterval>[];
  for (final i in sorted) {
    if (merged.isNotEmpty && !i.start.isAfter(merged.last.end)) {
      final last = merged.removeLast();
      merged.add(OpeningInterval(last.start, i.end.isAfter(last.end) ? i.end : last.end));
    } else {
      merged.add(i);
    }
  }
  for (final i in merged) {
    if (!now.isBefore(i.start) && now.isBefore(i.end)) {
      return i.end.isBefore(validUntil) ? OpenUntil(i.end) : const OpenThroughWindow();
    }
    if (i.start.isAfter(now)) {
      return i.start.isBefore(validUntil) ? ClosedUntil(i.start) : const ClosedThroughWindow();
    }
  }
  return const ClosedThroughWindow();
}
