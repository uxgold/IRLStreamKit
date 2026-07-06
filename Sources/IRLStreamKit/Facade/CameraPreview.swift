// UI-only seam, deliberately OUTSIDE the StreamEngine protocol so view models
// (and fakes) never touch UIKit. Only views consume this.

import SwiftUI
import UIKit

@MainActor
public protocol CameraPreviewSource: AnyObject {
    /// Returns the engine's live preview view (the processed stream frames).
    /// The same instance is returned on every call; install it in one place.
    func makePreviewUIView() -> UIView
}

extension IRLStreamEngine: CameraPreviewSource {
    public func makePreviewUIView() -> UIView {
        internalPreviewView
    }
}

/// SwiftUI camera preview for the operator-cockpit widget. Renders a black
/// placeholder when `source` is nil (Xcode previews, simulator, tests).
public struct CameraPreviewView: View {
    private let source: (any CameraPreviewSource)?

    public init(source: (any CameraPreviewSource)?) {
        self.source = source
    }

    public var body: some View {
        if let source {
            PreviewViewRepresentable(source: source)
        } else {
            Color.black
        }
    }
}

private struct PreviewViewRepresentable: UIViewRepresentable {
    let source: any CameraPreviewSource

    func makeUIView(context _: Context) -> UIView {
        source.makePreviewUIView()
    }

    func updateUIView(_: UIView, context _: Context) {}
}
