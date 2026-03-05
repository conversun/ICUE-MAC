import Foundation
import IOKit.hid

class HIDService {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private let queue = DispatchQueue(label: "com.cyonsun.icue-xc7.hid")

    var isConnected: Bool {
        queue.sync { device != nil }
    }

    var onDeviceConnected: (() -> Void)?
    var onDeviceDisconnected: (() -> Void)?

    func start() {
        queue.sync {
            if manager != nil {
                return
            }

            let hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
            let matching: [String: Any] = [
                kIOHIDVendorIDKey as String: Constants.vendorID,
                kIOHIDProductIDKey as String: Constants.productID
            ]

            IOHIDManagerSetDeviceMatching(hidManager, matching as CFDictionary)

            let context = Unmanaged.passUnretained(self).toOpaque()
            IOHIDManagerRegisterDeviceMatchingCallback(hidManager, { context, _, _, device in
                guard let context else { return }
                let service = Unmanaged<HIDService>.fromOpaque(context).takeUnretainedValue()
                service.handleDeviceMatched(device)
            }, context)

            IOHIDManagerRegisterDeviceRemovalCallback(hidManager, { context, _, _, _ in
                guard let context else { return }
                let service = Unmanaged<HIDService>.fromOpaque(context).takeUnretainedValue()
                service.handleDeviceRemoved()
            }, context)

            IOHIDManagerScheduleWithRunLoop(hidManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDManagerOpen(hidManager, IOOptionBits(kIOHIDOptionsTypeNone))

            manager = hidManager
        }
    }

    func stop() {
        queue.sync {
            if let currentDevice = device {
                IOHIDDeviceClose(currentDevice, IOOptionBits(kIOHIDOptionsTypeNone))
                device = nil
            }

            if let currentManager = manager {
                IOHIDManagerUnscheduleFromRunLoop(currentManager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
                IOHIDManagerClose(currentManager, IOOptionBits(kIOHIDOptionsTypeNone))
                manager = nil
            }
        }
    }

    func writeRGB(colors: [RGBColor]) {
        queue.async { [weak self] in
            guard let self, let currentDevice = self.device else {
                return
            }

            var buffer = [UInt8](repeating: 0, count: Constants.rgbBufferSize)
            buffer[0] = Constants.rgbReportHeader[0]
            buffer[1] = Constants.rgbReportHeader[1]
            buffer[2] = Constants.rgbReportHeader[2]

            let count = min(Constants.ledCount, colors.count)
            for i in 0..<count {
                let base = 3 + i * 3
                buffer[base] = colors[i].r
                buffer[base + 1] = colors[i].g
                buffer[base + 2] = colors[i].b
            }

            _ = buffer.withUnsafeBytes { rawBuffer in
                guard let pointer = rawBuffer.baseAddress else {
                    return kIOReturnError
                }
                return IOHIDDeviceSetReport(
                    currentDevice,
                    kIOHIDReportTypeOutput,
                    CFIndex(0),
                    pointer.assumingMemoryBound(to: UInt8.self),
                    buffer.count
                )
            }
        }
    }

    func setAllRGB(_ color: RGBColor) {
        let colors = Array(repeating: color, count: Constants.ledCount)
        writeRGB(colors: colors)
    }

    func readTemperature() -> Double? {
        queue.sync {
            guard let currentDevice = device else {
                return nil
            }

            var buffer = [UInt8](repeating: 0, count: Constants.tempReportSize)
            var reportLength = buffer.count
            let result = buffer.withUnsafeMutableBytes { rawBuffer in
                guard let pointer = rawBuffer.baseAddress else {
                    return kIOReturnError
                }
                return IOHIDDeviceGetReport(
                    currentDevice,
                    kIOHIDReportTypeFeature,
                    CFIndex(Constants.tempReportID),
                    pointer.assumingMemoryBound(to: UInt8.self),
                    &reportLength
                )
            }

            guard result == kIOReturnSuccess, reportLength >= 4 else {
                return nil
            }

            let raw = Int16(littleEndian: Int16(bitPattern: UInt16(buffer[2]) | (UInt16(buffer[3]) << 8)))
            return Double(raw) / 10.0
        }
    }

    private func handleDeviceMatched(_ matchedDevice: IOHIDDevice?) {
        guard let matchedDevice else {
            return
        }

        queue.async { [weak self] in
            guard let self else {
                return
            }

            self.device = matchedDevice
            DispatchQueue.main.async { [weak self] in
                self?.onDeviceConnected?()
            }
        }
    }

    private func handleDeviceRemoved() {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            self.device = nil
            DispatchQueue.main.async { [weak self] in
                self?.onDeviceDisconnected?()
            }
        }
    }
}
