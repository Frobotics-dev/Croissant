import IOKit.ps
import Combine
import Foundation
import AppKit // For NSScreen and NSApplication notifications

import CoreGraphics

// Represents per-monitor information for UI display
struct MonitorInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let isBuiltin: Bool
    let isMain: Bool
    let resolutionWidth: Int
    let resolutionHeight: Int
    let scale: CGFloat
    let colorSpaceName: String
    let isHDR: Bool
    let refreshRate: Double?
}

class SystemInfoManager: ObservableObject {
    // Existing Properties
    @Published var batteryLevel: Float?
    @Published var isCharging: Bool?
    @Published var uptime: String = "N/A"

    // New Properties for Disk, CPU, and Monitor
    @Published var totalDiskSpace: Int64?
    @Published var availableDiskSpace: Int64?
    @Published var cpuUsage: Double = 0.0
    @Published var externalMonitorConnected: Bool = false

    // Monitors detail list (all connected displays)
    @Published var monitors: [MonitorInfo] = []

    private var timer: Timer?
    private var notificationSource: CFRunLoopSource?
    private var previousCPULoadInfo: host_cpu_load_info?
    
    private let uptimeFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .full
        return formatter
    }()

    init() {
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        // Fetch initial data for all properties
        fetchBatteryInfo()
        updateUptime()
        fetchDiskSpace()
        updateExternalMonitorStatus()

        updateMonitorsInfo()

        // Schedule timer for periodic updates
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.updateUptime()
            self?.updateCPUUsage()
            self?.fetchDiskSpace() // Disk space can change, update periodically
        }

        // Set up battery change notifications
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        notificationSource = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let manager = Unmanaged<SystemInfoManager>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                manager.fetchBatteryInfo()
            }
        }, context).takeRetainedValue()
        
        if let source = notificationSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }
        
        // Set up screen connection/disconnection notifications
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        
        if let source = notificationSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
            notificationSource = nil
        }
        
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }
    
    private func updateUptime() {
        let systemUptime = ProcessInfo.processInfo.systemUptime
        uptime = uptimeFormatter.string(from: systemUptime) ?? "N/A"
    }

    private func fetchDiskSpace() {
        do {
            let fileURL = URL(fileURLWithPath: "/")
            let values = try fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
            
            DispatchQueue.main.async {
                self.availableDiskSpace = values.volumeAvailableCapacityForImportantUsage
                self.totalDiskSpace = Int64(values.volumeTotalCapacity ?? 0)
            }
        } catch {
            print("Error fetching disk space: \(error)")
            DispatchQueue.main.async {
                self.availableDiskSpace = nil
                self.totalDiskSpace = nil
            }
        }
    }

    private func updateCPUUsage() {
        var cpuLoadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        
        let result = withUnsafeMutablePointer(to: &cpuLoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        if result == KERN_SUCCESS, let prev = previousCPULoadInfo {
            let userDiff = Double(cpuLoadInfo.cpu_ticks.0 - prev.cpu_ticks.0)
            let systemDiff = Double(cpuLoadInfo.cpu_ticks.1 - prev.cpu_ticks.1)
            let idleDiff = Double(cpuLoadInfo.cpu_ticks.2 - prev.cpu_ticks.2)
            let niceDiff = Double(cpuLoadInfo.cpu_ticks.3 - prev.cpu_ticks.3)
            
            let totalTicks = userDiff + systemDiff + idleDiff + niceDiff
            if totalTicks > 0 {
                let usage = (userDiff + systemDiff + niceDiff) / totalTicks
                DispatchQueue.main.async {
                    self.cpuUsage = usage
                }
            }
        }
        previousCPULoadInfo = cpuLoadInfo
    }
    
    @objc private func screenParametersChanged() {
        updateExternalMonitorStatus()
        updateMonitorsInfo()
    }
    
    private func updateExternalMonitorStatus() {
        // Detect external displays even when the system is in mirroring/duplicating mode.
        var displayCount: UInt32 = 0
        var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
        let error = CGGetOnlineDisplayList(UInt32(onlineDisplays.count), &onlineDisplays, &displayCount)
        guard error == .success else {
            DispatchQueue.main.async { self.externalMonitorConnected = false }
            return
        }

        var hasExternal = false
        if displayCount > 1 {
            // More than one online display -> there is definitely an external one
            hasExternal = true
        } else if displayCount == 1 {
            // Single display online could still be an external when the lid is closed or internal is off.
            let d = onlineDisplays[0]
            hasExternal = (CGDisplayIsBuiltin(d) == 0)
        }

        DispatchQueue.main.async {
            self.externalMonitorConnected = hasExternal
        }
    }
    
    private func fetchBatteryInfo() {
        // Use IOPowerSources snapshot (supported on modern macOS) instead of AppleSmartBattery registry
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else {
            self.batteryLevel = nil
            self.isCharging = nil
            return
        }
        guard let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef], !sources.isEmpty else {
            // No power sources found (desktop Mac or unknown). Clear values.
            self.batteryLevel = nil
            self.isCharging = nil
            return
        }
    
        var foundInternalBattery = false
    
        for ps in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
    
            // Only consider internal battery entries
            let type = desc[kIOPSTypeKey as String] as? String
            if type == (kIOPSInternalBatteryType as String) {
                foundInternalBattery = true
    
                if let current = desc[kIOPSCurrentCapacityKey as String] as? Int,
                   let max = desc[kIOPSMaxCapacityKey as String] as? Int, max > 0 {
                    self.batteryLevel = Float(current) / Float(max)
                } else {
                    self.batteryLevel = nil
                }
    
                // Prefer explicit charging flag; otherwise infer from power source state
                if let charging = desc[kIOPSIsChargingKey as String] as? Bool {
                    self.isCharging = charging
                } else if let state = desc[kIOPSPowerSourceStateKey as String] as? String {
                    self.isCharging = (state == (kIOPSACPowerValue as String))
                } else {
                    self.isCharging = nil
                }
    
                break // We only need the first internal battery
            }
        }
    
        if !foundInternalBattery {
            // Laptop without detected internal battery (should be rare). Clear values to let UI show appropriate message.
            self.batteryLevel = nil
            self.isCharging = nil
        }
    }

    private func updateMonitorsInfo() {
        var displayCount: UInt32 = 0
        var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
        let error = CGGetOnlineDisplayList(UInt32(onlineDisplays.count), &onlineDisplays, &displayCount)
        guard error == .success else {
            DispatchQueue.main.async { self.monitors = [] }
            return
        }

        var result: [MonitorInfo] = []
        for i in 0..<Int(displayCount) {
            let did = onlineDisplays[i]

            // Match to NSScreen to extract scale, color space, HDR
            let screenMatch = NSScreen.screens.first(where: { screen in
                if let num = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
                    return CGDirectDisplayID(num.uint32Value) == did
                }
                return false
            })

            let mode = CGDisplayCopyDisplayMode(did)
            let pixelW = mode?.pixelWidth ?? Int(CGDisplayPixelsWide(did))
            let pixelH = mode?.pixelHeight ?? Int(CGDisplayPixelsHigh(did))
            let hz = (mode?.refreshRate ?? 0) > 0 ? mode?.refreshRate : nil

            let scale = screenMatch?.backingScaleFactor ?? 1.0
            let csName = screenMatch?.colorSpace?.localizedName ?? "Unknown"
            let isHDR = (screenMatch?.maximumExtendedDynamicRangeColorComponentValue ?? 1.0) > 1.0

            let info = MonitorInfo(
                id: did,
                isBuiltin: CGDisplayIsBuiltin(did) != 0,
                isMain: CGDisplayIsMain(did) != 0,
                resolutionWidth: pixelW,
                resolutionHeight: pixelH,
                scale: scale,
                colorSpaceName: csName,
                isHDR: isHDR,
                refreshRate: hz
            )
            result.append(info)
        }

        DispatchQueue.main.async {
            self.monitors = result
        }
    }
}

// Helper extension to format byte counts into human-readable strings (e.g., "1.2 GB")
// This is needed by SystemInfoTileView.
extension Int64 {
    func formattedString() -> String {
        return ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
