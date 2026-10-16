import AppKit
import SwiftUI
import AgentHUDCore

struct DisplayPane: View {
    let settings: SettingsStore
    let store: UsageStore
    let theme: Theme
    @State private var screen: String = ScreensPane.attached().first?.key ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            ScreensPane(settings: settings, store: store, theme: theme, selected: $screen)
            IslandPane(settings: settings, theme: theme)
        }
    }
}

/// Decorative wallpaper for the glow preview.
struct SettingsPreview<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity)
            .background {
                GeometryReader { geometry in
                    Image(nsImage: SettingsPreviewArtwork.wallpaper)
                        .resizable().scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(12)
            .accessibilityHidden(true)
            // A glow reaches past the box it is previewed in, and the preview sits in front of the rows
            // above it. Left interactive, that overhang silently swallows their clicks: AppKit-backed
            // controls keep working because they are real views, and plain SwiftUI buttons stop responding.
            .allowsHitTesting(false)
    }
}

@MainActor
private enum SettingsPreviewArtwork {
    static let wallpaper = NSImage(contentsOf: AppResources.bundle.url(forResource: "settings-wallpaper", withExtension: "png")!)!
}
