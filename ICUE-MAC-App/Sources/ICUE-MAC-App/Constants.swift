import Foundation

enum Constants {
    static let vendorID: Int = 0x1B1C
    static let productID: Int = 0x0C42
    static let ledCount: Int = 31
    static let rgbBufferSize: Int = 1024
    static let rgbReportHeader: [UInt8] = [0x02, 0x07, 0x1F]
    static let tempReportID: Int = 0x18
    static let tempReportSize: Int = 33
    static let keepAliveInterval: TimeInterval = 8.0
    static let keepAliveIntervalPresets: [TimeInterval] = [2.0, 5.0, 8.0, 15.0]
    static let tempPollInterval: TimeInterval = 3.0
}
