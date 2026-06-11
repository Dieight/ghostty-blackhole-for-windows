import AppKit
import SwiftUI

@main
struct BlackHoleTunerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = ShaderStore()

    var body: some Scene {
        WindowGroup("Black Hole Tuner") {
            ContentView()
                .environmentObject(store)
        }
    }
}

/// `swift run` produces a bare executable with no bundle; without this the
/// window never comes to the front (or appears at all).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
