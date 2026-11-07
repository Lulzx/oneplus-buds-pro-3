import ServiceManagement
import SwiftUI

@main
struct BudsBarApp: App {
    @State private var buds = Buds()

    init() { AutoStart.enableOnFirstLaunch() }

    var body: some Scene {
        // The icon is only in the menu bar while the buds are connected to this Mac.
        MenuBarExtra(isInserted: $buds.budsPresent) {
            PanelView()
                .environment(buds)
        } label: {
            MenuBarLabel(buds: buds)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let buds: Buds

    var body: some View {
        if buds.link == .connected, let level = buds.budLevel {
            Label("\(level)%", systemImage: "earbuds")
                .labelStyle(.titleAndIcon)
        } else {
            Image(systemName: "earbuds")
                .opacity(buds.link == .connected ? 1 : 0.5)
        }
    }
}

/// Runs BudsBar silently at login so it can show up as soon as the buds connect.
enum AutoStart {
    private static let askedKey = "autoStartConfigured"

    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func enableOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: askedKey) else { return }
        UserDefaults.standard.set(true, forKey: askedKey)
        set(true)
    }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("BudsBar login item \(on ? "register" : "unregister") failed: \(error)")
        }
    }
}
