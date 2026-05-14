import SwiftUI

@main
struct ICUEApp: App {
    @StateObject private var manager = DeviceManager()

    var body: some Scene {
        MenuBarExtra("ICUE XC7", systemImage: "drop.fill") {
            MenuView(manager: manager)
        }
    }
}
