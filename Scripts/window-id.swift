// Prints the CGWindowID of the first on-screen window owned by an app, for `screencapture -l`.
//   window-id <owner> [--width N] [--any-layer]
// Used by the README screenshot workflow.
import CoreGraphics
import Foundation

let arguments = CommandLine.arguments
guard arguments.count > 1 else {
    FileHandle.standardError.write(Data("usage: window-id <owner> [--width N] [--any-layer]\n".utf8))
    exit(64)
}
let owner = arguments[1]
let width = arguments.firstIndex(of: "--width").flatMap { Double(arguments[$0 + 1]) }
let anyLayer = arguments.contains("--any-layer")

let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for window in windows {
    guard window[kCGWindowOwnerName as String] as? String == owner,
          let number = window[kCGWindowNumber as String] as? Int,
          let bounds = window[kCGWindowBounds as String] as? [String: Any],
          let windowWidth = bounds["Width"] as? Double,
          let windowHeight = bounds["Height"] as? Double,
          windowHeight > 100 else { continue }
    let layer = window[kCGWindowLayer as String] as? Int ?? 0
    if !anyLayer && layer != 0 { continue }
    if anyLayer && layer == 0 { continue }
    if let width, abs(windowWidth - width) > 2 { continue }
    print(number)
    exit(0)
}
FileHandle.standardError.write(Data("no matching window for \(owner)\n".utf8))
exit(1)
