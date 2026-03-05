import AppKit
import Combine
import SwiftUI

struct MenuView: View {
    @ObservedObject var manager: DeviceManager
    @StateObject private var colorPanelObserver = ColorPanelObserver()

    var body: some View {
        Text("Water Temp: \(String(format: "%.1f°C", manager.temperature))")
            .disabled(true)

        Divider()

        effectButton("Off", effect: .off)

        Menu {
            ForEach(RGBColor.presets, id: \.name) { preset in
                Button(preset.name) {
                    manager.setStaticColor(preset.color)
                    manager.setEffect(.staticColor)
                }
            }

            Divider()

            Button("Custom...") {
                openColorPanel(for: .staticColor)
            }
        } label: {
            Text(prefix(for: .staticColor) + "Static Color")
        }

        Menu {
            ForEach(SpeedPreset.allCases, id: \.rawValue) { speed in
                Button(speedLabel(speed, current: manager.rainbowSpeed)) {
                    manager.rainbowSpeed = speed.rawValue
                }
            }
        } label: {
            Text(prefix(for: .rainbow) + "Rainbow")
        }

        Menu {
            ForEach(RGBColor.presets, id: \.name) { preset in
                Button(preset.name) {
                    manager.setBreatheColor(preset.color)
                    manager.setEffect(.breathe)
                }
            }

            Divider()

            Menu("Speed") {
                ForEach(SpeedPreset.allCases, id: \.rawValue) { speed in
                    Button(speedLabel(speed, current: manager.breatheSpeed)) {
                        manager.breatheSpeed = speed.rawValue
                    }
                }
            }
        } label: {
            Text(prefix(for: .breathe) + "Breathe")
        }

        Menu {
            ForEach(TempProfile.presets, id: \.name) { profile in
                Button(tempProfileLabel(profile)) {
                    manager.setTempProfile(profile)
                    manager.setEffect(.tempColor)
                }
            }
        } label: {
            Text(prefix(for: .tempColor) + "Temperature Color")
        }

        Divider()

        Menu("Brightness: \(BrightnessPreset(rawValue: manager.brightness)?.label ?? "\(Int(manager.brightness * 100))%")") {
            ForEach(BrightnessPreset.allCases, id: \.rawValue) { preset in
                Button(brightnessLabel(preset)) {
                    manager.brightness = preset.rawValue
                }
            }
        }

        Divider()

        Button(manager.launchAtLogin ? "✓ Launch at Login" : "  Launch at Login") {
            manager.toggleLaunchAtLogin()
        }

        if !manager.isConnected {
            Divider()
            Text("⚠ Device not connected")
                .disabled(true)
        }

        Divider()

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func effectButton(_ title: String, effect: LightingEffect) -> some View {
        Button(prefix(for: effect) + title) {
            manager.setEffect(effect)
        }
    }

    private func prefix(for effect: LightingEffect) -> String {
        manager.currentEffect == effect ? "● " : "○ "
    }

    private func speedLabel(_ preset: SpeedPreset, current: Double) -> String {
        (preset.rawValue == current ? "● " : "○ ") + preset.label
    }

    private func brightnessLabel(_ preset: BrightnessPreset) -> String {
        (preset.rawValue == manager.brightness ? "● " : "○ ") + preset.label
    }

    private func tempProfileLabel(_ profile: TempProfile) -> String {
        let active = manager.activeTempProfile
        return (active == profile ? "● " : "○ ") + profile.name
    }

    private func openColorPanel(for effect: LightingEffect) {
        colorPanelObserver.observe { color in
            switch effect {
            case .staticColor:
                manager.setStaticColor(color)
                manager.setEffect(.staticColor)
            case .breathe:
                manager.setBreatheColor(color)
                manager.setEffect(.breathe)
            default:
                break
            }
        }

        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.orderFront(nil)
    }
}

final class ColorPanelObserver: ObservableObject {
    private var cancellable: AnyCancellable?

    func observe(onChange: @escaping (RGBColor) -> Void) {
        let panel = NSColorPanel.shared
        cancellable = NotificationCenter.default
            .publisher(for: NSColorPanel.colorDidChangeNotification, object: panel)
            .sink { _ in
                guard let color = panel.color.usingColorSpace(.sRGB) else {
                    return
                }

                let rgb = RGBColor(
                    r: UInt8(max(0, min(255, Int(round(color.redComponent * 255))))),
                    g: UInt8(max(0, min(255, Int(round(color.greenComponent * 255))))),
                    b: UInt8(max(0, min(255, Int(round(color.blueComponent * 255)))))
                )
                onChange(rgb)
            }
    }
}
