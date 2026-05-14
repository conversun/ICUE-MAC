@preconcurrency import Foundation
import Combine
import AppKit
import os.log
import Darwin

/// File-scope so notification observer closures (Sendable) can reference it without crossing the @MainActor boundary.
private let recoveryLog = OSLog(subsystem: "com.cyonsun.icue-xc7", category: "recovery")


/// Isolated observable for the live water-temperature reading.
///
/// Kept separate from `DeviceManager` so the 3-second temperature poll does
/// not invalidate `MenuView` and tear down any open submenu. Only the
/// temperature row subscribes to this object; the rest of the menu stays put.
@MainActor
final class TemperatureMonitor: ObservableObject {
    @Published var value: Double = 0.0
}

@MainActor
class DeviceManager: ObservableObject {
    @Published var currentEffect: LightingEffect = .off {
        didSet { UserDefaults.standard.set(currentEffect.rawValue, forKey: "currentEffect") }
    }
    @Published var staticColor: RGBColor = .red {
        didSet { UserDefaults.standard.set(staticColor.rawValue, forKey: "staticColor") }
    }
    @Published var breatheColor: RGBColor = .blue {
        didSet { UserDefaults.standard.set(breatheColor.rawValue, forKey: "breatheColor") }
    }
    let temperature = TemperatureMonitor()
    @Published var isConnected: Bool = false

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
    @Published var keepAliveInterval: TimeInterval = Constants.keepAliveInterval {
        didSet {
            UserDefaults.standard.set(keepAliveInterval, forKey: "keepAliveInterval")
            // Restart only if a keep-alive driven effect is active (animation timers are independent)
            switch currentEffect {
            case .off, .staticColor, .tempColor, .gradient, .timeOfDay:
                setEffect(currentEffect)
            case .rainbow, .breathe, .wave, .chase, .fire, .sparkle, .aurora, .colorCycle, .cpuUsage:
                break
            }
        }
    }
    @Published var gradientColorA: RGBColor = .blue {
        didSet {
            UserDefaults.standard.set(gradientColorA.rawValue, forKey: "gradientColorA")
            if currentEffect == .gradient { setEffect(.gradient) }
        }
    }
    @Published var gradientColorB: RGBColor = .purple {
        didSet {
            UserDefaults.standard.set(gradientColorB.rawValue, forKey: "gradientColorB")
            if currentEffect == .gradient { setEffect(.gradient) }
        }
    }
    @Published var waveColorA: RGBColor = .blue {
        didSet {
            UserDefaults.standard.set(waveColorA.rawValue, forKey: "waveColorA")
            if currentEffect == .wave { setEffect(.wave) }
        }
    }
    @Published var waveColorB: RGBColor = .purple {
        didSet {
            UserDefaults.standard.set(waveColorB.rawValue, forKey: "waveColorB")
            if currentEffect == .wave { setEffect(.wave) }
        }
    }
    @Published var waveSpeed: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(waveSpeed, forKey: "waveSpeed")
            if currentEffect == .wave { setEffect(.wave) }
        }
    }
    @Published var chaseColor: RGBColor = .white {
        didSet {
            UserDefaults.standard.set(chaseColor.rawValue, forKey: "chaseColor")
            if currentEffect == .chase { setEffect(.chase) }
        }
    }
    @Published var chaseSpeed: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(chaseSpeed, forKey: "chaseSpeed")
            if currentEffect == .chase { setEffect(.chase) }
        }
    }
    @Published var colorCycleSpeed: Double = 1.0 {
        didSet {
            UserDefaults.standard.set(colorCycleSpeed, forKey: "colorCycleSpeed")
            if currentEffect == .colorCycle { setEffect(.colorCycle) }
        }
    }

    private let hid = HIDService()
    private var effectTimer: AnyCancellable?
    private var tempTimer: AnyCancellable?
    private var rainbowOffset: Double = 0.0
    private var breatheTime: Double = 0.0
    private var lastCPUTicks: (active: UInt64, total: UInt64)?
    /// True while AppKit is tracking a menu (status-item menu open, submenu hovered, etc.).
    /// While true, the temperature timer skips its `@Published` write so SwiftUI's
    /// `MenuBarExtra` does not invalidate and rebuild the underlying `NSMenu` —
    /// rebuilding tears down whatever submenu the user is currently selecting.
    /// Apple confirmed (FB13683957) that any state change in the menu hierarchy
    /// causes a full NSMenu reconstruction, not an incremental update.
    private var isMenuTracking = false

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
        if ud.object(forKey: "keepAliveInterval") != nil { keepAliveInterval = ud.double(forKey: "keepAliveInterval") }
        if let hex = ud.string(forKey: "gradientColorA"), let c = RGBColor(rawValue: hex) { gradientColorA = c }
        if let hex = ud.string(forKey: "gradientColorB"), let c = RGBColor(rawValue: hex) { gradientColorB = c }
        if let hex = ud.string(forKey: "waveColorA"), let c = RGBColor(rawValue: hex) { waveColorA = c }
        if let hex = ud.string(forKey: "waveColorB"), let c = RGBColor(rawValue: hex) { waveColorB = c }
        if ud.object(forKey: "waveSpeed") != nil { waveSpeed = ud.double(forKey: "waveSpeed") }
        if let hex = ud.string(forKey: "chaseColor"), let c = RGBColor(rawValue: hex) { chaseColor = c }
        if ud.object(forKey: "chaseSpeed") != nil { chaseSpeed = ud.double(forKey: "chaseSpeed") }
        if ud.object(forKey: "colorCycleSpeed") != nil { colorCycleSpeed = ud.double(forKey: "colorCycleSpeed") }

        if let saved = ud.string(forKey: "currentEffect"),
           let effect = LightingEffect(rawValue: saved) {
            currentEffect = effect
        }

        hid.onDeviceConnected = { [weak self] in
            guard let self else { return }
            self.isConnected = true
            self.setEffect(self.currentEffect)
        }

        hid.onDeviceDisconnected = { [weak self] in
            self?.isConnected = false
        }

        hid.start()
        startTemperaturePolling()
        setupRecoveryHandlers()
        setupMenuTrackingObservers()

        // Apply the restored effect immediately so the keep-alive / animation
        // timer matches the in-memory state. HID writes are no-ops until IOKit
        // matches the device; `onDeviceConnected` will re-apply once attached.
        // Without this, `keepAliveInterval.didSet` above leaves a stale .off
        // keep-alive timer running because `currentEffect` was still the
        // default at that point in init.
        setEffect(currentEffect)
    }


    /// Wires up sleep/wake observers and HID write-failure recovery.
    /// Defends against silent USB failures during long keep-alive intervals.
    private func setupRecoveryHandlers() {
        // On persistent write failures, restart the HID manager so IOKit re-matches the device.
        hid.onWriteFailureThresholdReached = { [weak self] in
            guard let self else { return }
            os_log("Persistent HID write failures — restarting HID manager", log: recoveryLog, type: .error)
            self.hid.restart()
            // onDeviceConnected callback will re-apply currentEffect once the device re-matches.
        }

        let nc = NSWorkspace.shared.notificationCenter

        nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            os_log("System will sleep", log: recoveryLog, type: .info)
        }

        nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                os_log("System did wake — refreshing current effect", log: recoveryLog, type: .info)
                // Force immediate refresh: device may have lost state during sleep,
                // and the next keep-alive tick could be up to 15s away.
                self.setEffect(self.currentEffect)
            }
        }
    }

    /// Pauses periodic `@Published` writes while any AppKit menu is being tracked.
    ///
    /// Without this, the 3-second temperature poll fires `objectWillChange` on
    /// `TemperatureMonitor` (or any other periodic publisher) while the user is
    /// hovering a submenu. SwiftUI's `MenuBarExtra` reacts by tearing down and
    /// rebuilding the entire `NSMenu` (see Apple Feedback FB13683957), which
    /// closes the open submenu mid-selection.
    ///
    /// `NSMenu.didBeginTrackingNotification` fires when the user opens the status
    /// item menu; `didEndTrackingNotification` fires when the menu fully closes.
    /// Submenus opened within that session do NOT emit new notifications — they
    /// inherit the root menu's tracking state, which is exactly what we want.
    private func setupMenuTrackingObservers() {
        let nc = NotificationCenter.default

        nc.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isMenuTracking = true
            }
        }

        nc.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isMenuTracking = false
                // Push one fresh reading now so the next menu open shows current data.
                if let temp = self.hid.readTemperature() {
                    self.temperature.value = temp
                }
            }
        }
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
            let c = temperatureToColor(temperature.value, cold: tempCold, warm: tempWarm, hot: tempHot)
                .scaled(by: brightness)
            hid.setAllRGB(c)
            effectTimer = keepAliveTimer { [weak self] in
                guard let self else { return }
                let c = temperatureToColor(self.temperature.value, cold: self.tempCold, warm: self.tempWarm, hot: self.tempHot)
                    .scaled(by: self.brightness)
                self.hid.setAllRGB(c)
            }

        case .gradient:
            applyGradient()
            effectTimer = keepAliveTimer { [weak self] in self?.applyGradient() }

        case .wave:
            var phase: Double = 0
            effectTimer = animationTimer { [weak self] in
                guard let self else { return }
                let colors = calculateWave(colorA: self.waveColorA, colorB: self.waveColorB, phase: phase)
                    .map { $0.scaled(by: self.brightness) }
                self.hid.writeRGB(colors: colors)
                phase = (phase + 0.005 * self.waveSpeed).truncatingRemainder(dividingBy: 1.0)
            }

        case .chase:
            var position: Double = 0
            effectTimer = animationTimer { [weak self] in
                guard let self else { return }
                let colors = calculateChase(color: self.chaseColor, head: position)
                    .map { $0.scaled(by: self.brightness) }
                self.hid.writeRGB(colors: colors)
                position = (position + 0.3 * self.chaseSpeed)
                    .truncatingRemainder(dividingBy: Double(Constants.ledCount))
            }

        case .fire:
            var heat = Array(repeating: 0.0, count: Constants.ledCount)
            effectTimer = animationTimer { [weak self] in
                guard let self else { return }
                let colors = calculateFire(heat: &heat)
                    .map { $0.scaled(by: self.brightness) }
                self.hid.writeRGB(colors: colors)
            }

        case .sparkle:
            var state = Array(repeating: 0.0, count: Constants.ledCount)
            effectTimer = animationTimer { [weak self] in
                guard let self else { return }
                let colors = calculateSparkle(state: &state, sparkColor: .white)
                    .map { $0.scaled(by: self.brightness) }
                self.hid.writeRGB(colors: colors)
            }

        case .aurora:
            var time: Double = 0
            effectTimer = animationTimer { [weak self] in
                guard let self else { return }
                let colors = calculateAurora(time: time)
                    .map { $0.scaled(by: self.brightness) }
                self.hid.writeRGB(colors: colors)
                time += 0.005
            }

        case .colorCycle:
            var phase: Double = 0
            effectTimer = animationTimer { [weak self] in
                guard let self else { return }
                let colors = calculateColorCycle(phase: phase)
                    .map { $0.scaled(by: self.brightness) }
                self.hid.writeRGB(colors: colors)
                phase = (phase + 0.001 * self.colorCycleSpeed)
                    .truncatingRemainder(dividingBy: 1.0)
            }

        case .cpuUsage:
            // Prime the sampler so the first 1Hz tick has real delta data; the priming
            // call records baseline ticks and returns 0 (no delta yet).
            lastCPUTicks = nil
            _ = readSystemCPUUsage()
            effectTimer = Timer.publish(every: 1.0, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    guard let self else { return }
                    let cpu = self.readSystemCPUUsage()
                    let colors = calculateCPUUsage(cpuPct: cpu)
                        .map { $0.scaled(by: self.brightness) }
                    self.hid.writeRGB(colors: colors)
                }

        case .timeOfDay:
            applyTimeOfDay()
            effectTimer = keepAliveTimer { [weak self] in self?.applyTimeOfDay() }
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

    func setGradientPair(_ pair: GradientPair) {
        gradientColorA = pair.colorA
        gradientColorB = pair.colorB
        if currentEffect == .gradient { setEffect(.gradient) }
    }

    func setWavePair(_ pair: GradientPair) {
        waveColorA = pair.colorA
        waveColorB = pair.colorB
        if currentEffect == .wave { setEffect(.wave) }
    }

    func setChaseColor(_ color: RGBColor) {
        chaseColor = color
        if currentEffect == .chase { setEffect(.chase) }
    }

    var activeGradientPair: GradientPair? {
        GradientPair.presets.first { $0.colorA == gradientColorA && $0.colorB == gradientColorB }
    }

    var activeWavePair: GradientPair? {
        GradientPair.presets.first { $0.colorA == waveColorA && $0.colorB == waveColorB }
    }

    private func keepAliveTimer(_ action: @escaping () -> Void) -> AnyCancellable {
        Timer.publish(every: keepAliveInterval, on: .main, in: .common)
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
                guard !self.isMenuTracking else { return }
                if let temp = self.hid.readTemperature() {
                    self.temperature.value = temp
                }
            }
    }

    // MARK: - Effect-specific apply helpers

    private func applyGradient() {
        let colors = calculateGradient(colorA: gradientColorA, colorB: gradientColorB)
            .map { $0.scaled(by: brightness) }
        hid.writeRGB(colors: colors)
    }

    private func applyTimeOfDay() {
        let colors = calculateTimeOfDay(hour: currentHourFloat())
            .map { $0.scaled(by: brightness) }
        hid.writeRGB(colors: colors)
    }

    private func currentHourFloat() -> Double {
        let comps = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
        let h = Double(comps.hour ?? 0)
        let m = Double(comps.minute ?? 0)
        let s = Double(comps.second ?? 0)
        return h + m / 60.0 + s / 3600.0
    }

    /// System-wide CPU usage in [0, 1] via mach `host_statistics(HOST_CPU_LOAD_INFO)`.
    /// Compares cumulative tick counts between calls; returns 0 on the first (priming) call.
    private func readSystemCPUUsage() -> Double {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &info) { infoPtr in
            infoPtr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { ptr in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, ptr, &count)
            }
        }

        guard result == KERN_SUCCESS else { return 0 }

        let user   = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle   = UInt64(info.cpu_ticks.2)
        let nice   = UInt64(info.cpu_ticks.3)

        let active = user &+ system &+ nice
        let total  = active &+ idle

        guard let last = lastCPUTicks else {
            lastCPUTicks = (active: active, total: total)
            return 0
        }

        let dActive = active &- last.active
        let dTotal  = total  &- last.total
        lastCPUTicks = (active: active, total: total)

        guard dTotal > 0 else { return 0 }
        return Double(dActive) / Double(dTotal)
    }
}

// MARK: - Language preference

extension DeviceManager {
    /// User-facing language choice. `.system` means "defer to the macOS locale chain"
    /// (i.e. no `AppleLanguages` override). The explicit cases match BCP-47 codes
    /// that line up with the bundled `<locale>.lproj` directories.
    enum AppLanguage: String, CaseIterable {
        case system
        case english = "en"
        case simplifiedChinese = "zh-Hans"

        /// Display name shown in the menu. Native names for the explicit choices
        /// ("English", "简体中文") stay verbatim regardless of UI locale; only the
        /// `.system` label is translated so it reads naturally in either UI.
        var label: String {
            switch self {
            case .system: return NSLocalizedString("System (Auto)", comment: "")
            case .english: return "English"
            case .simplifiedChinese: return "简体中文"
            }
        }
    }

    /// Resolves the current override from `UserDefaults[AppleLanguages]`.
    /// Absent / unrecognized → `.system` (follow the system preference chain).
    var currentLanguage: AppLanguage {
        if let langs = UserDefaults.standard.array(forKey: "AppleLanguages") as? [String],
           let first = langs.first,
           let match = AppLanguage(rawValue: first) {
            return match
        }
        return .system
    }

    /// Writes the override and respawns the app so the new locale takes effect on
    /// every UI string. Cocoa reads `AppleLanguages` once at launch — mutating it
    /// in-place would only affect strings looked up after the change.
    func setLanguage(_ language: AppLanguage) {
        let ud = UserDefaults.standard
        switch language {
        case .system:
            ud.removeObject(forKey: "AppleLanguages")
        case .english, .simplifiedChinese:
            ud.set([language.rawValue], forKey: "AppleLanguages")
        }
        ud.synchronize()

        // `open -n` forces a fresh instance even if macOS would normally focus the
        // existing one. The 200 ms grace period gives `open` enough wall-clock to
        // hand off before we tear down the current process.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundlePath]
        try? task.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApplication.shared.terminate(nil)
        }
    }
}
