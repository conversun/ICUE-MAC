import Foundation

enum LightingEffect: String, CaseIterable {
    case off
    case staticColor
    case rainbow
    case breathe
    case tempColor
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
