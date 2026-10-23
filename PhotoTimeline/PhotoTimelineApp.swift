import SwiftUI

@main
struct PhotoTimelineApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var updater = Updater()

    var body: some Scene {
        DocumentGroup(newDocument: { TimelineDocument() }) { file in
            ContentView(document: file.document)
                .frame(minWidth: 600, minHeight: 400)
                .background(WindowPlacement())
                .onChange(of: file.fileURL, initial: true) { _, url in showExtension(of: url) }
        }
        .defaultLaunchBehavior(AppDelegate.documentsToRestore.isEmpty ? .automatic : .suppressed)
        .commands { UpdateCommands(updater: updater) }
        Settings {
            SettingsView(updater: updater)
        }
    }

    /// The save panel hides the extension by default; keep `.phototimeline` visible in Finder.
    private func showExtension(of url: URL?) {
        guard var url else { return }
        var values = URLResourceValues()
        values.hasHiddenExtension = false
        try? url.setResourceValues(values)
    }
}
