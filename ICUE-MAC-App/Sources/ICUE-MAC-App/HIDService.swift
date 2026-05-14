import Foundation
import IOKit.hid
import os.log

class HIDService {
    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private let queue = DispatchQueue(label: "com.cyonsun.icue-xc7.hid")
    private static let log = OSLog(subsystem: "com.cyonsun.icue-xc7", category: "hid")
    private static let writeFailureThreshold = 3
    private var consecutiveWriteFailures = 0  // queue-protected
    private static let restartCooldown: TimeInterval = 30.0
    private var lastRestartTime: Date?  // queue-protected

    var isConnected: Bool {
        queue.sync { device != nil }
    }

    var onDeviceConnected: (() -> Void)?
    var onDeviceDisconnected: (() -> Void)?
    var onWriteFailureThresholdReached: (() -> Void)?  // fired on main queue

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

    /// Tear down and re-establish the HID manager so IOKit re-matches the device.
    /// Gated by a cooldown to prevent runaway restart loops if writes keep failing
    /// post-restart (e.g., device truly gone). Returns true if restart actually executed.
    @discardableResult
    func restart() -> Bool {
        let canProceed: Bool = queue.sync {
            let now = Date()
            if let last = lastRestartTime, now.timeIntervalSince(last) < Self.restartCooldown {
                return false
            }
            lastRestartTime = now
            return true
        }
        guard canProceed else {
            os_log("HID restart skipped: cooldown active (%{public}.0fs)", log: Self.log, type: .info, Self.restartCooldown)
            return false
        }
        os_log("HID restart: tearing down and re-opening manager", log: Self.log, type: .info)
        stop()
        start()
        return true
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

            let result = buffer.withUnsafeBytes { rawBuffer -> IOReturn in
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

            if result == kIOReturnSuccess {
                if self.consecutiveWriteFailures > 0 {
                    os_log("HID write recovered after %{public}d failures", log: Self.log, type: .info, self.consecutiveWriteFailures)
                    self.consecutiveWriteFailures = 0
                }
            } else {
                self.consecutiveWriteFailures += 1
                os_log("HID write failed: 0x%{public}08X (consecutive=%{public}d)", log: Self.log, type: .error, UInt32(bitPattern: result), self.consecutiveWriteFailures)
                if self.consecutiveWriteFailures == Self.writeFailureThreshold {
                    DispatchQueue.main.async { [weak self] in
                        self?.onWriteFailureThresholdReached?()
                    }
                }
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
