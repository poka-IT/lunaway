// Prints the id of the largest on-screen window of the process named in the
// first argument, for `screencapture -l`.
import CoreGraphics
import Foundation

let owner = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Lunaway"
let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
var best: (id: Int, area: Double)?
for w in windows {
  guard (w[kCGWindowOwnerName as String] as? String) == owner,
        (w[kCGWindowLayer as String] as? Int ?? 0) <= 3,
        let b = w[kCGWindowBounds as String] as? [String: Double],
        let id = w[kCGWindowNumber as String] as? Int else { continue }
  let area = (b["Width"] ?? 0) * (b["Height"] ?? 0)
  if best == nil || area > best!.area { best = (id, area) }
}
if let b = best { print(b.id) }
