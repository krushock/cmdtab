import AppKit
import ScreenCaptureKit

/// Captures window previews with ScreenCaptureKit, a few at a time, into an observable cache.
@MainActor
final class ThumbnailStore {
    nonisolated static let maxConcurrent = 4
    nonisolated static let maxPixelSide: CGFloat = 1000

    func captureAll(_ windows: [WindowInfo], source: WindowSource, into update: @escaping @MainActor (CGWindowID, CGImage) -> Void) async {
        guard !windows.isEmpty else { return }
        let jobs: [(CGWindowID, SCWindow?)] = windows.map { ($0.id, source.scWindow(for: $0.id)) }
        await withTaskGroup(of: (CGWindowID, CGImage?).self) { group in
            var next = 0
            func enqueue() {
                guard next < jobs.count else { return }
                let (id, sc) = jobs[next]
                next += 1
                group.addTask {
                    guard let sc else { return (id, nil) }
                    return (id, await ThumbnailStore.capture(sc))
                }
            }
            for _ in 0..<min(Self.maxConcurrent, windows.count) { enqueue() }
            for await (id, image) in group {
                if Task.isCancelled { break }
                if let image { update(id, image) }
                enqueue()
            }
        }
    }

    nonisolated static func capture(_ window: SCWindow) async -> CGImage? {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let size = window.frame.size
        guard size.width > 0, size.height > 0 else { return nil }
        let backingScale: CGFloat = 2
        let factor = min(1, maxPixelSide / max(size.width, size.height))
        config.width = max(1, Int(size.width * factor * backingScale))
        config.height = max(1, Int(size.height * factor * backingScale))
        config.showsCursor = false
        config.ignoreShadowsSingleWindow = true
        config.captureResolution = .best
        config.scalesToFit = true
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
