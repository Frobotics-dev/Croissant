//
//  SystemInfoManager.swift
//  Dashboard
//
//  Created by Frederik Mondel on 15.10.25.
//

import Foundation
import Combine // Required for @Published
import IOKit.ps // Für Batterie-Informationen
import IOKit.pwr_mgt // Für Batterie-Informationen (Swift 5.7+ für macOS 13+)
import Darwin.sys.sysctl // Für CPU Auslastung
import MachO // For mach_host_self, host_statistics
import CoreGraphics // Import for display information

class SystemInfoManager: ObservableObject {
    @Published var uptime: TimeInterval = 0
    @Published var totalDiskSpace: Measurement<UnitInformationStorage>?
    @Published var availableDiskSpace: Measurement<UnitInformationStorage>?
    @Published var batteryLevel: Float? // 0.0 to 1.0
    @Published var isCharging: Bool?
    @Published var cpuUsage: Double = 0.0 // 0.0 to 1.0 (0% to 100%)
    @Published var externalMonitorConnected: Bool = false // For external monitor detection

    private var timer: Timer?

    // CPU usage tracking properties, moved out of the function
    private var prevIdleTicks: UInt64 = 0
    private var prevTotalTicks: UInt64 = 0
    
    init() {
        startMonitoring()
    }

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        // Initialer Abruf
        fetchSystemInfo()
        // Aktualisiere alle 5 Sekunden
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.fetchSystemInfo()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func fetchSystemInfo() {
        fetchUptime()
        fetchDiskSpace()
        fetchBatteryInfo()
        fetchCPUUsage()
        fetchDisplayInfo() // Call display info
    }

    private func fetchUptime() {
        uptime = ProcessInfo.processInfo.systemUptime
    }

    private func fetchDiskSpace() {
        // Using `FileManager.default.url(for...)` is generally preferred over NSHomeDirectory()
        // for better sandbox compatibility, but for total/available volume, we can check the root.
        let fileURL = URL(fileURLWithPath: "/") // Check root volume for total capacity
        do {
            let values = try fileURL.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
            if let totalCapacity = values.volumeTotalCapacity {
                totalDiskSpace = Measurement(value: Double(totalCapacity), unit: .bytes)
            }
            if let availableCapacity = values.volumeAvailableCapacityForImportantUsage {
                availableDiskSpace = Measurement(value: Double(availableCapacity), unit: .bytes)
            }
        } catch {
            print("Error fetching disk space: \(error.localizedDescription)")
            totalDiskSpace = nil
            availableDiskSpace = nil
        }
    }

    private func fetchBatteryInfo() {
        // IOKit ist ein C-API, daher ist der Zugriff etwas umständlicher
        // Prüfen, ob Batterie-Dienst verfügbar ist
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { // IOServiceGetMatchingService returns 0 if not found, not an Optional
            batteryLevel = nil
            isCharging = nil
            return
        }

        var batteryInfoCF: Unmanaged<CFMutableDictionary>?
        let status = IORegistryEntryCreateCFProperties(service, &batteryInfoCF, kCFAllocatorDefault, 0)

        guard status == KERN_SUCCESS,
              let batteryInfo = batteryInfoCF?.takeRetainedValue() as? [String: AnyObject] else {
            batteryLevel = nil
            isCharging = nil
            IOObjectRelease(service) // Release the service if we can't get info
            return
        }
        
        if let currentCapacity = batteryInfo[kIOPSCurrentCapacityKey] as? Int,
           let maxCapacity = batteryInfo[kIOPSMaxCapacityKey] as? Int {
            batteryLevel = Float(currentCapacity) / Float(maxCapacity)
        }
        if let charging = batteryInfo[kIOPSIsChargingKey] as? Bool {
            isCharging = charging
        }

        IOObjectRelease(service) // Wichtig: IORegistryEntryCreateCFProperties behält einen Retain-Count bei, den wir freigeben müssen.
    }
    
    // CPU Usage calculation based on host_statistics
    // This provides a system-wide average over the sampling period
    private func fetchCPUUsage() {
        let kernelPort: host_t = mach_host_self()
        var hostCPULoadInfo = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        
        // Correctly call host_statistics by rebinding the pointer type
        let result = withUnsafeMutablePointer(to: &hostCPULoadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(kernelPort, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        
        guard result == KERN_SUCCESS else {
            print("Error: host_statistics \(result)")
            self.cpuUsage = 0.0
            return
        }
        
        // Access tuple elements using dot notation and explicitly cast them to UInt64
        // to match the type of prevIdleTicks and prevTotalTicks for consistent arithmetic.
        let user    = UInt64(hostCPULoadInfo.cpu_ticks.0) // CPU_STATE_USER
        let system  = UInt64(hostCPULoadInfo.cpu_ticks.1) // CPU_STATE_SYSTEM
        let idle    = UInt64(hostCPULoadInfo.cpu_ticks.2) // CPU_STATE_IDLE
        let nice    = UInt64(hostCPULoadInfo.cpu_ticks.3) // CPU_STATE_NICE
        
        let currentIdleTicks = idle
        let currentTotalTicks = user + system + idle + nice
        
        // Calculate difference from previous sample
        let totalTicksDelta = currentTotalTicks - prevTotalTicks
        let idleTicksDelta = currentIdleTicks - prevIdleTicks
        
        if totalTicksDelta > 0 {
            // CPU_STATE_IDLE are ticks when the CPU is idle.
            // (total - idle) / total gives the usage.
            let usage = Double(totalTicksDelta - idleTicksDelta) / Double(totalTicksDelta)
            self.cpuUsage = max(0.0, min(1.0, usage)) // Clamp between 0 and 1
        } else {
            // If no ticks change, assume no usage or initial state.
            self.cpuUsage = 0.0
        }
        
        // Update previous ticks for the next calculation
        // Assignments are now UInt64 = UInt64
        self.prevIdleTicks = currentIdleTicks
        self.prevTotalTicks = currentTotalTicks
    }

    // Function to fetch display information
    private func fetchDisplayInfo() {
        var displayCount: UInt32 = 0
        // Allocate space for up to 16 display IDs; the actual number will be written to `displayCount`
        var onlineDisplays = [CGDirectDisplayID](repeating: 0, count: 16) 

        // Use CGGetOnlineDisplayList to get all displays that are currently connected and powered on.
        let error = CGGetOnlineDisplayList(UInt32(onlineDisplays.count), &onlineDisplays, &displayCount)
        guard error == CGError.success else {
            print("Error getting online display list: \(error)")
            externalMonitorConnected = false
            return
        }
        
        var hasExternalMonitor = false
        for i in 0..<displayCount {
            let displayID = onlineDisplays[Int(i)]
            // Check if the display is NOT a built-in display
            if (CGDisplayIsBuiltin(displayID) == 0) {
                hasExternalMonitor = true
                break
            }
        }
        externalMonitorConnected = hasExternalMonitor
    }
}

extension Measurement where UnitType == UnitInformationStorage {
    func formattedString() -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        // `allowsNonContiguousUnits` is not available on all platforms/versions; removed for compatibility.
        // If you need more specific formatting, you might need to implement custom logic.
        
        // Konvertiere zu Bytes, da `formatter` erwartet, dass die Werte in Bytes sind
        let byteValue = self.converted(to: .bytes).value
        return formatter.string(fromByteCount: Int64(byteValue))
    }
}

extension TimeInterval {
    func formattedUptime() -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .full
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: self) ?? "N/A"
    }
}
