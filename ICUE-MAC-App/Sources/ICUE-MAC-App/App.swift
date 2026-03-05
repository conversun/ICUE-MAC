import SwiftUI

@main
struct ICUEApp: App {
    @StateObject private var manager = DeviceManager()

    var body: some Scene {
        MenuBarExtra {
            MenuView(manager: manager)
        } label: {
            HStack(alignment: .center, spacing: 4) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(String(format: "%.1f°", manager.temperature))
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
    }
}
