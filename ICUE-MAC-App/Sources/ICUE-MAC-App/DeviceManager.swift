@preconcurrency import Foundation
import Combine
import ServiceManagement

@MainActor
class DeviceManager: ObservableObject {
    @Published var currentEffect: LightingEffect = .off
    @Published var staticColor: RGBColor = .red {
        didSet { UserDefaults.standard.set(staticColor.rawValue, forKey: "staticColor") }
    }
    @Published var breatheColor: RGBColor = .blue {
        didSet { UserDefaults.standard.set(breatheColor.rawValue, forKey: "breatheColor") }
    }
    @Published var temperature: Double = 0.0
    @Published var isConnected: Bool = false
    @Published var launchAtLogin: Bool = false

    @Published var rainbowSpeed: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(rainbowSpeed, forKey: "rainbowSpeed")
            if currentEffect == .rainbow { setEffect(.rainbow) }
        }
    }
    @Published var breatheSpeed: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(breatheSpeed, forKey: "breatheSpeed")
            if currentEffect == .breathe { setEffect(.breathe) }
        }
    }
    @Published var brightness: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(brightness, forKey: "brightness")
            if currentEffect != .off { setEffect(currentEffect) }
        }
    }
    @Published var tempCold: Double = 25.0 {
        didSet { UserDefaults.standard.set(tempCold, forKey: "tempCold") }
    }
    @Published var tempWarm: Double = 35.0 {
        didSet { UserDefaults.standard.set(tempWarm, forKey: "tempWarm") }
    }
    @Published var tempHot: Double = 45.0 {
        didSet { UserDefaults.standard.set(tempHot, forKey: "tempHot") }
    }

    private let hid = HIDService()
    private var effectTimer: AnyCancellable?
    private var tempTimer: AnyCancellable?
    private var rainbowOffset: Double = 0.0
    private var breatheTime: Double = 0.0

    init() {
        let ud = UserDefaults.standard
        if let hex = ud.string(forKey: "staticColor"), let c = RGBColor(rawValue: hex) { staticColor = c }
        if let hex = ud.string(forKey: "breatheColor"), let c = RGBColor(rawValue: hex) { breatheColor = c }
        if ud.object(forKey: "rainbowSpeed") != nil { rainbowSpeed = ud.double(forKey: "rainbowSpeed") }
        if ud.object(forKey: "breatheSpeed") != nil { breatheSpeed = ud.double(forKey: "breatheSpeed") }
        if ud.object(forKey: "brightness") != nil { brightness = ud.double(forKey: "brightness") }
        if ud.object(forKey: "tempCold") != nil { tempCold = ud.double(forKey: "tempCold") }
        if ud.object(forKey: "tempWarm") != nil { tempWarm = ud.double(forKey: "tempWarm") }
        if ud.object(forKey: "tempHot") != nil { tempHot = ud.double(forKey: "tempHot") }

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
            effectTimer = keepAliveTimer { [weak self] in
                self?.hid.setAllRGB(.off)
            }

        case .staticColor:
            hid.setAllRGB(staticColor.scaled(by: brightness))
            effectTimer = keepAliveTimer { [weak self] in
                guard let self else { return }
                self.hid.setAllRGB(self.staticColor.scaled(by: self.brightness))
            }

        case .rainbow:
            rainbowOffset = 0.0
            effectTimer = animationTimer { [weak self] in
                guard let self else { return }
                let colors = calculateRainbow(offset: self.rainbowOffset)
                    .map { $0.scaled(by: self.brightness) }
                self.hid.writeRGB(colors: colors)
                self.rainbowOffset = (self.rainbowOffset + 0.01 * self.rainbowSpeed)
                    .truncatingRemainder(dividingBy: 1.0)
            }

        case .breathe:
            breatheTime = 0.0
            effectTimer = animationTimer { [weak self] in
                guard let self else { return }
                let color = calculateBreathe(color: self.breatheColor, time: self.breatheTime)
                    .scaled(by: self.brightness)
                self.hid.setAllRGB(color)
                self.breatheTime += 0.05 * self.breatheSpeed
            }

        case .tempColor:
            let c = temperatureToColor(temperature, cold: tempCold, warm: tempWarm, hot: tempHot)
                .scaled(by: brightness)
            hid.setAllRGB(c)
            effectTimer = keepAliveTimer { [weak self] in
                guard let self else { return }
                let c = temperatureToColor(self.temperature, cold: self.tempCold, warm: self.tempWarm, hot: self.tempHot)
                    .scaled(by: self.brightness)
                self.hid.setAllRGB(c)
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
        if currentEffect == .staticColor { setEffect(.staticColor) }
    }

    func setBreatheColor(_ color: RGBColor) {
        breatheColor = color
        if currentEffect == .breathe { setEffect(.breathe) }
    }

    func setTempProfile(_ profile: TempProfile) {
        tempCold = profile.cold
        tempWarm = profile.warm
        tempHot = profile.hot
        if currentEffect == .tempColor { setEffect(.tempColor) }
    }

    var activeTempProfile: TempProfile? {
        TempProfile.presets.first { $0.cold == tempCold && $0.warm == tempWarm && $0.hot == tempHot }
    }

    private func keepAliveTimer(_ action: @escaping () -> Void) -> AnyCancellable {
        Timer.publish(every: Constants.keepAliveInterval, on: .main, in: .common)
            .autoconnect()
            .sink { _ in action() }
    }

    private func animationTimer(_ action: @escaping () -> Void) -> AnyCancellable {
        Timer.publish(every: 0.03, on: .main, in: .common)
            .autoconnect()
            .sink { _ in action() }
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
