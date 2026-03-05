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
        ("Red", .red),
        ("Orange", .orange),
        ("Yellow", .yellow),
        ("Green", .green),
        ("Blue", .blue),
        ("Purple", .purple),
        ("White", .white)
    ]
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
    
    let r = UInt8((r1 + m) * 255.0)
    let g = UInt8((g1 + m) * 255.0)
    let b = UInt8((b1 + m) * 255.0)
    
    return RGBColor(r: r, g: g, b: b)
}

func calculateRainbow(offset: Double) -> [RGBColor] {
    var colors: [RGBColor] = []
    for i in 0..<Constants.ledCount {
        let hue = (Double(i) / Double(Constants.ledCount) + offset).truncatingRemainder(dividingBy: 1.0)
        let color = hsvToRgb(hue: hue, saturation: 1.0, value: 1.0)
        colors.append(color)
    }
    return colors
}

func calculateBreathe(color: RGBColor, time: Double) -> RGBColor {
    let brightness = (sin(time) + 1.0) / 2.0
    let r = UInt8(Double(color.r) * brightness)
    let g = UInt8(Double(color.g) * brightness)
    let b = UInt8(Double(color.b) * brightness)
    return RGBColor(r: r, g: g, b: b)
}

func temperatureToColor(_ temp: Double) -> RGBColor {
    if temp <= 25.0 {
        return RGBColor(r: 0, g: 0, b: 255)
    } else if temp <= 35.0 {
        let t = (temp - 25.0) / 10.0
        let g = UInt8(255.0 * t)
        let b = UInt8(255.0 * (1.0 - t))
        return RGBColor(r: 0, g: g, b: b)
    } else if temp <= 45.0 {
        let t = (temp - 35.0) / 10.0
        let r = UInt8(255.0 * t)
        let g = UInt8(255.0 * (1.0 - t))
        return RGBColor(r: r, g: g, b: 0)
    } else {
        return RGBColor(r: 255, g: 0, b: 0)
    }
}
