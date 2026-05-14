import Foundation

enum LightingEffect: String, CaseIterable {
    case off
    case staticColor
    case rainbow
    case breathe
    case tempColor
    case gradient
    case wave
    case chase
    case fire
    case sparkle
    case aurora
    case colorCycle
    case cpuUsage
    case timeOfDay
}

struct RGBColor: Equatable {
    let r: UInt8
    let g: UInt8
    let b: UInt8

    static let red = RGBColor(r: 255, g: 0, b: 0)
    static let orange = RGBColor(r: 255, g: 128, b: 0)
    static let yellow = RGBColor(r: 255, g: 255, b: 0)
    static let green = RGBColor(r: 0, g: 255, b: 0)
    static let blue = RGBColor(r: 0, g: 0, b: 255)
    static let purple = RGBColor(r: 128, g: 0, b: 255)
    static let white = RGBColor(r: 255, g: 255, b: 255)
    static let off = RGBColor(r: 0, g: 0, b: 0)

    static let presets: [(name: String, color: RGBColor)] = [
        ("Red", .red), ("Orange", .orange), ("Yellow", .yellow),
        ("Green", .green), ("Blue", .blue), ("Purple", .purple), ("White", .white)
    ]

    func scaled(by factor: Double) -> RGBColor {
        let f = max(0, min(1, factor))
        return RGBColor(
            r: UInt8(Double(r) * f),
            g: UInt8(Double(g) * f),
            b: UInt8(Double(b) * f)
        )
    }
}

extension RGBColor: RawRepresentable {
    init?(rawValue: String) {
        guard rawValue.count == 6,
              let r = UInt8(rawValue.prefix(2), radix: 16),
              let g = UInt8(rawValue.dropFirst(2).prefix(2), radix: 16),
              let b = UInt8(rawValue.dropFirst(4).prefix(2), radix: 16) else { return nil }
        self.init(r: r, g: g, b: b)
    }

    var rawValue: String {
        String(format: "%02X%02X%02X", r, g, b)
    }
}

enum SpeedPreset: Double, CaseIterable {
    case slow = 0.5
    case normal = 1.0
    case fast = 1.5
    case faster = 2.0
    case fastest = 3.0

    var label: String {
        switch self {
        case .slow: return "0.5×"
        case .normal: return "1.0×"
        case .fast: return "1.5×"
        case .faster: return "2.0×"
        case .fastest: return "3.0×"
        }
    }
}

enum BrightnessPreset: Double, CaseIterable {
    case quarter = 0.25
    case half = 0.50
    case threeQuarter = 0.75
    case full = 1.00

    var label: String {
        switch self {
        case .quarter: return "25%"
        case .half: return "50%"
        case .threeQuarter: return "75%"
        case .full: return "100%"
        }
    }
}

struct TempProfile: Equatable {
    let name: String
    let cold: Double
    let warm: Double
    let hot: Double

    static let standard = TempProfile(name: "Default (25-35-45°C)", cold: 25, warm: 35, hot: 45)
    static let overclocker = TempProfile(name: "Overclocker (30-40-50°C)", cold: 30, warm: 40, hot: 50)
    static let server = TempProfile(name: "Server (35-45-55°C)", cold: 35, warm: 45, hot: 55)
    static let conservative = TempProfile(name: "Conservative (20-30-40°C)", cold: 20, warm: 30, hot: 40)

    static let presets = [standard, overclocker, server, conservative]
}

func hsvToRgb(hue: Double, saturation: Double, value: Double) -> RGBColor {
    let h = hue * 6.0
    let c = value * saturation
    let x = c * (1.0 - abs(h.truncatingRemainder(dividingBy: 2.0) - 1.0))
    let m = value - c

    let (r1, g1, b1): (Double, Double, Double)

    if h < 1.0 {
        (r1, g1, b1) = (c, x, 0)
    } else if h < 2.0 {
        (r1, g1, b1) = (x, c, 0)
    } else if h < 3.0 {
        (r1, g1, b1) = (0, c, x)
    } else if h < 4.0 {
        (r1, g1, b1) = (0, x, c)
    } else if h < 5.0 {
        (r1, g1, b1) = (x, 0, c)
    } else {
        (r1, g1, b1) = (c, 0, x)
    }

    return RGBColor(
        r: UInt8((r1 + m) * 255.0),
        g: UInt8((g1 + m) * 255.0),
        b: UInt8((b1 + m) * 255.0)
    )
}

func calculateRainbow(offset: Double) -> [RGBColor] {
    (0..<Constants.ledCount).map { i in
        let hue = (Double(i) / Double(Constants.ledCount) + offset).truncatingRemainder(dividingBy: 1.0)
        return hsvToRgb(hue: hue, saturation: 1.0, value: 1.0)
    }
}

func calculateBreathe(color: RGBColor, time: Double) -> RGBColor {
    let brightness = (sin(time) + 1.0) / 2.0
    return color.scaled(by: brightness)
}

func temperatureToColor(_ temp: Double, cold: Double = 25, warm: Double = 35, hot: Double = 45) -> RGBColor {
    if temp <= cold {
        return .blue
    } else if temp <= warm {
        let t = (temp - cold) / (warm - cold)
        return RGBColor(r: 0, g: UInt8(255.0 * t), b: UInt8(255.0 * (1.0 - t)))
    } else if temp <= hot {
        let t = (temp - warm) / (hot - warm)
        return RGBColor(r: UInt8(255.0 * t), g: UInt8(255.0 * (1.0 - t)), b: 0)
    } else {
        return .red
    }
}


// MARK: - Two-color gradient presets (used by .gradient and .wave)

struct GradientPair: Equatable {
    let name: String
    let colorA: RGBColor
    let colorB: RGBColor

    static let presets: [GradientPair] = [
        GradientPair(name: "Blue → Violet", colorA: .blue,  colorB: .purple),
        GradientPair(name: "Sunset",        colorA: RGBColor(r: 255, g: 60,  b: 60),  colorB: RGBColor(r: 255, g: 200, b: 60)),
        GradientPair(name: "Ocean",         colorA: .green, colorB: .blue),
        GradientPair(name: "Candy",         colorA: RGBColor(r: 255, g: 80,  b: 200), colorB: RGBColor(r: 0,   g: 200, b: 255)),
        GradientPair(name: "Ember",         colorA: .white, colorB: .red),
    ]
}

// MARK: - Color helpers

/// Linear interpolation between two RGB colors.
func lerpColor(_ a: RGBColor, _ b: RGBColor, _ t: Double) -> RGBColor {
    let clamped = max(0, min(1, t))
    return RGBColor(
        r: UInt8(Double(a.r) * (1 - clamped) + Double(b.r) * clamped),
        g: UInt8(Double(a.g) * (1 - clamped) + Double(b.g) * clamped),
        b: UInt8(Double(a.b) * (1 - clamped) + Double(b.b) * clamped)
    )
}

/// Sample a piecewise-linear color palette at parameter `t` in [0, 1].
/// `palette` MUST be sorted by stop in ascending order and span [0, 1].
func paletteLookup(_ palette: [(stop: Double, color: RGBColor)], _ t: Double) -> RGBColor {
    let clamped = max(0, min(1, t))
    for i in 0..<(palette.count - 1) {
        let lo = palette[i]
        let hi = palette[i + 1]
        if clamped <= hi.stop {
            let span = hi.stop - lo.stop
            let local = span > 0 ? (clamped - lo.stop) / span : 0
            return lerpColor(lo.color, hi.color, local)
        }
    }
    return palette.last!.color
}

// MARK: - New effect calculators

/// Smooth A→B→A radial gradient across the ring (one full sine cycle).
func calculateGradient(colorA: RGBColor, colorB: RGBColor) -> [RGBColor] {
    (0..<Constants.ledCount).map { i in
        let pos = Double(i) / Double(Constants.ledCount)
        let t = (sin(2 * .pi * pos) + 1) / 2
        return lerpColor(colorA, colorB, t)
    }
}

/// Sinusoidal A↔B wave rotating around the ring; `phase` shifts the wave.
func calculateWave(colorA: RGBColor, colorB: RGBColor, phase: Double) -> [RGBColor] {
    (0..<Constants.ledCount).map { i in
        let pos = Double(i) / Double(Constants.ledCount)
        let t = (sin(2 * .pi * (pos + phase)) + 1) / 2
        return lerpColor(colorA, colorB, t)
    }
}

/// Single bright dot at LED position `head`, with a `tailLength`-LED fading trail behind it.
/// Position is in floating-point LED units; wraps around the ring.
func calculateChase(color: RGBColor, head: Double, tailLength: Int = 8) -> [RGBColor] {
    let n = Constants.ledCount
    let nDouble = Double(n)
    let normalizedHead = ((head.truncatingRemainder(dividingBy: nDouble)) + nDouble).truncatingRemainder(dividingBy: nDouble)
    return (0..<n).map { i in
        let raw = normalizedHead - Double(i)
        let dist = ((raw.truncatingRemainder(dividingBy: nDouble)) + nDouble).truncatingRemainder(dividingBy: nDouble)
        if dist < Double(tailLength) {
            let intensity = 1.0 - dist / Double(tailLength)
            return color.scaled(by: intensity * intensity)
        }
        return .off
    }
}

private let firePalette: [(stop: Double, color: RGBColor)] = [
    (0.00, .off),
    (0.20, RGBColor(r: 80,  g: 0,   b: 0)),
    (0.40, RGBColor(r: 200, g: 30,  b: 0)),
    (0.60, RGBColor(r: 255, g: 100, b: 0)),
    (0.80, RGBColor(r: 255, g: 200, b: 50)),
    (1.00, RGBColor(r: 255, g: 255, b: 200))
]

/// Heat-diffusion fire simulation: cool, smear toward neighbors, drop random sparks.
/// Mutates `heat` to advance the simulation by one frame.
func calculateFire(heat: inout [Double]) -> [RGBColor] {
    let n = heat.count
    // Cool every cell
    for i in 0..<n {
        heat[i] *= 0.92
    }
    // Diffuse toward neighbors (ring wraparound)
    var next = heat
    for i in 0..<n {
        let prev = heat[(i + n - 1) % n]
        let nxt  = heat[(i + 1) % n]
        next[i] = heat[i] * 0.6 + prev * 0.2 + nxt * 0.2
    }
    heat = next
    // Inject a few random sparks per frame
    for _ in 0..<3 {
        if Double.random(in: 0..<1) < 0.5 {
            let i = Int.random(in: 0..<n)
            heat[i] = min(1.0, heat[i] + Double.random(in: 0.5..<1.0))
        }
    }
    return heat.map { paletteLookup(firePalette, $0) }
}

/// Random sparkles of `sparkColor` on a dark base. Each LED has its own brightness that decays per frame.
/// Mutates `state` to advance per-LED brightness.
func calculateSparkle(state: inout [Double], sparkColor: RGBColor) -> [RGBColor] {
    let n = state.count
    for i in 0..<n {
        state[i] *= 0.88
    }
    if Double.random(in: 0..<1) < 0.30 {
        let i = Int.random(in: 0..<n)
        state[i] = 1.0
    }
    return state.map { sparkColor.scaled(by: $0) }
}

/// Three overlapping cool-tone sine bands moving at different speeds: northern-lights feel.
func calculateAurora(time: Double) -> [RGBColor] {
    let n = Constants.ledCount
    struct Band {
        let speed: Double
        let freq: Double
        let color: RGBColor
    }
    let bands: [Band] = [
        Band(speed: 0.7, freq: 1.0, color: RGBColor(r: 0,   g: 220, b: 100)),
        Band(speed: 1.1, freq: 1.5, color: RGBColor(r: 100, g: 0,   b: 220)),
        Band(speed: 0.4, freq: 0.7, color: RGBColor(r: 0,   g: 100, b: 220))
    ]
    return (0..<n).map { i in
        let pos = Double(i) / Double(n)
        var r: Double = 0, g: Double = 0, b: Double = 0
        var totalWeight: Double = 0
        for band in bands {
            let w = (sin(2 * .pi * (pos * band.freq + time * band.speed)) + 1) / 2
            r += Double(band.color.r) * w
            g += Double(band.color.g) * w
            b += Double(band.color.b) * w
            totalWeight += w
        }
        let norm = max(1.0, totalWeight)
        return RGBColor(
            r: UInt8(min(255, r / norm)),
            g: UInt8(min(255, g / norm)),
            b: UInt8(min(255, b / norm))
        )
    }
}

/// Whole ring lit in a single color whose hue cycles with `phase` in [0, 1).
func calculateColorCycle(phase: Double) -> [RGBColor] {
    let hue = ((phase.truncatingRemainder(dividingBy: 1.0)) + 1.0).truncatingRemainder(dividingBy: 1.0)
    let color = hsvToRgb(hue: hue, saturation: 1.0, value: 1.0)
    return Array(repeating: color, count: Constants.ledCount)
}

/// CPU-usage gauge: lit-LED count proportional to `cpuPct` in [0, 1].
/// Lit LEDs use a blue→green→red position-based gradient so the bar shows both fill AND intensity.
func calculateCPUUsage(cpuPct: Double) -> [RGBColor] {
    let n = Constants.ledCount
    let pct = max(0, min(1, cpuPct))
    let litCount = Int((pct * Double(n)).rounded())
    return (0..<n).map { i in
        guard i < litCount else { return .off }
        let posPct = Double(i) / Double(max(1, n - 1))
        return cpuGaugeColor(posPct)
    }
}

private func cpuGaugeColor(_ t: Double) -> RGBColor {
    if t < 0.5 {
        let local = t * 2
        return RGBColor(
            r: 0,
            g: UInt8(255 * local),
            b: UInt8(255 * (1 - local))
        )
    } else {
        let local = (t - 0.5) * 2
        return RGBColor(
            r: UInt8(255 * local),
            g: UInt8(255 * (1 - local)),
            b: 0
        )
    }
}

private let timeOfDayStops: [(hour: Double, color: RGBColor)] = [
    (0.0,  RGBColor(r: 20,  g: 0,   b: 80)),    // midnight
    (5.0,  RGBColor(r: 60,  g: 20,  b: 100)),   // pre-dawn
    (7.0,  RGBColor(r: 255, g: 150, b: 80)),    // sunrise
    (10.0, RGBColor(r: 255, g: 240, b: 200)),   // morning
    (13.0, RGBColor(r: 230, g: 240, b: 255)),   // midday
    (17.0, RGBColor(r: 255, g: 200, b: 120)),   // golden hour
    (19.0, RGBColor(r: 255, g: 100, b: 100)),   // sunset
    (21.0, RGBColor(r: 100, g: 30,  b: 150)),   // dusk
    (24.0, RGBColor(r: 20,  g: 0,   b: 80))     // back to midnight
]

/// Whole ring tinted to match the current time of day, smoothly interpolating between
/// preset stops (midnight blue → sunrise orange → noon white → sunset red → dusk purple).
func calculateTimeOfDay(hour: Double) -> [RGBColor] {
    let wrapped = ((hour.truncatingRemainder(dividingBy: 24)) + 24).truncatingRemainder(dividingBy: 24)
    var color = timeOfDayStops.last!.color
    for i in 0..<(timeOfDayStops.count - 1) {
        let lo = timeOfDayStops[i]
        let hi = timeOfDayStops[i + 1]
        if wrapped >= lo.hour && wrapped <= hi.hour {
            let span = hi.hour - lo.hour
            let local = span > 0 ? (wrapped - lo.hour) / span : 0
            color = lerpColor(lo.color, hi.color, local)
            break
        }
    }
    return Array(repeating: color, count: Constants.ledCount)
}