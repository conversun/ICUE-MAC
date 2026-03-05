import SwiftUI

@main
struct ICUEApp: App {
    @StateObject private var manager = DeviceManager()

    var body: some Scene {
        MenuBarExtra {
            MenuView(manager: manager)
        } label: {
            Image(systemName: "drop.fill")
            Text(String(format: "%.1f°", manager.temperature))
        }
    }
}
