@preconcurrency import Foundation
import Combine
import ServiceManagement

@MainActor
class DeviceManager: ObservableObject {
    @Published var currentEffect: LightingEffect = .off
    @Published var staticColor: RGBColor = .red
    @Published var breatheColor: RGBColor = .blue
    @Published var temperature: Double = 0.0
    @Published var isConnected: Bool = false
    @Published var launchAtLogin: Bool = false

    private let hid = HIDService()
    private var effectTimer: AnyCancellable?
    private var tempTimer: AnyCancellable?
    private var rainbowOffset: Double = 0.0
    private var breatheTime: Double = 0.0

    init() {
        hid.onDeviceConnected = { [weak self] in
            guard let self else { return }
            self.isConnected = true
            self.setEffect(self.currentEffect)
        }

        hid.onDeviceDisconnected = { [weak self] in
            self?.isConnected = false
        }

        launchAtLogin = SMAppService.mainApp.status == .enabled

        hid.start()
        startTemperaturePolling()
    }

    func setEffect(_ effect: LightingEffect) {
        currentEffect = effect
        effectTimer?.cancel()
        effectTimer = nil

        switch effect {
        case .off:
            hid.setAllRGB(.off)
            effectTimer = Timer.publish(every: Constants.keepAliveInterval, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.hid.setAllRGB(.off)
                }

        case .staticColor:
            hid.setAllRGB(staticColor)
            effectTimer = Timer.publish(every: Constants.keepAliveInterval, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.hid.setAllRGB(self.staticColor)
                }

        case .rainbow:
            rainbowOffset = 0.0
            effectTimer = Timer.publish(every: 0.03, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self else { return }
                    let colors = calculateRainbow(offset: self.rainbowOffset)
                    self.hid.writeRGB(colors: colors)
                    self.rainbowOffset = (self.rainbowOffset + 0.01).truncatingRemainder(dividingBy: 1.0)
                }

        case .breathe:
            breatheTime = 0.0
            effectTimer = Timer.publish(every: 0.03, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self else { return }
                    let color = calculateBreathe(color: self.breatheColor, time: self.breatheTime)
                    self.hid.setAllRGB(color)
                    self.breatheTime += 0.05
                }

        case .tempColor:
            let currentTemp = temperature
            hid.setAllRGB(temperatureToColor(currentTemp))
            effectTimer = Timer.publish(every: Constants.keepAliveInterval, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.hid.setAllRGB(temperatureToColor(self.temperature))
                }
        }
    }

    func toggleLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchAtLogin.toggle()
        } catch {
            print("Failed to toggle launch at login: \(error)")
        }
    }

    func setStaticColor(_ color: RGBColor) {
        staticColor = color
        if currentEffect == .staticColor {
            setEffect(.staticColor)
        }
    }

    func setBreatheColor(_ color: RGBColor) {
        breatheColor = color
        if currentEffect == .breathe {
            setEffect(.breathe)
        }
    }

    private func startTemperaturePolling() {
        tempTimer?.cancel()
        tempTimer = Timer.publish(every: Constants.tempPollInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                if let temp = self.hid.readTemperature() {
                    self.temperature = temp
                }
            }
    }
}
