import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct MacDiskScopeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("MacDiskScope — Analizador Visual de Disco y Duplicados") {
            ContentView()
                .frame(minWidth: 1080, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1280, height: 800)
    }
}
