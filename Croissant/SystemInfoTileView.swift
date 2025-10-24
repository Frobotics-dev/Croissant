//
//  SystemInfoTileView.swift
//  Dashboard
//
//  Created by Frederik Mondel on 15.10.25.
//

import SwiftUI
// IOKit.ps is only used by SystemInfoManager, not directly in this View.
// import IOKit.ps

struct SystemInfoTileView: View {
    @StateObject var manager = SystemInfoManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("System Info", systemImage: "info.circle")
                .font(.headline)
            
            // NEW: Ensure this VStack uses the full width
            VStack(alignment: .leading, spacing: 5) {
                // Uptime
                SystemInfoRow(icon: "hourglass", label: "Uptime", value: manager.uptime)
                
                // Disk Space
                if let total = manager.totalDiskSpace, let available = manager.availableDiskSpace {
                    SystemInfoRow(icon: "internaldrive", label: "Disk Space", value: "\(available.formattedString()) free of \(total.formattedString())")
                } else {
                    SystemInfoRow(icon: "internaldrive", label: "Disk Space", value: "Not available")
                }
                
                // Battery Info
                // Moved complex battery logic into a private helper function
                if let batteryLevel = manager.batteryLevel {
                    batteryInfoRow(batteryLevel: batteryLevel, isCharging: manager.isCharging)
                } else {
                    // Improved message for systems without an internal battery
                    SystemInfoRow(icon: "battery.50", label: "Battery", value: "No internal battery found") // Changed icon to a more compatible one
                }
                
                // CPU Usage
                SystemInfoRow(icon: "cpu", label: "CPU", value: "\(Int(manager.cpuUsage * 100))%")

                // Displays (all monitors)
                if manager.monitors.isEmpty {
                    SystemInfoRow(icon: "display", label: "Displays", value: manager.externalMonitorConnected ? "External connected" : "Only built-in")
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(manager.monitors) { m in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .center, spacing: 6) {
                                    Image(systemName: "display")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .frame(width: 25, alignment: .center)
                                    Text(monitorLabel(for: m))
                                        .foregroundColor(.secondary)
                                        .fontWeight(.semibold)
                                }
                                Text(monitorValue(for: m))
                                    .font(.body)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .padding(.leading, 31) // Align text under the label
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading) // NEW: Ensure rows use full width
        }
        // .tileStyle() // REMOVED: DashboardTileView now applies the styling
        .onAppear {
            manager.startMonitoring()
        }
        .onDisappear {
            manager.stopMonitoring()
        }
    }
    
    // Helper function to determine battery icon name based on level and charging status
    // BEIBEHALTEN: Die Logik für das Icon bleibt, um das Lade-Icon (.bolt) zu zeigen.
    private func batteryIcon(for level: Float, isCharging: Bool?) -> String {
        let percentage = Int(level * 100)
        let chargingSuffix = (isCharging == true) ? ".bolt" : ""

        if percentage >= 95 {
            return "battery.100" + chargingSuffix
        } else if percentage >= 70 {
            return "battery.75" + chargingSuffix
        } else if percentage >= 45 {
            return "battery.50" + chargingSuffix
        } else if percentage >= 20 {
            return "battery.25" + chargingSuffix
        } else {
            return "battery.0" + chargingSuffix
        }
    }

    // Helper function to encapsulate battery info row logic and return a View
    private func batteryInfoRow(batteryLevel: Float, isCharging: Bool?) -> some View {
        let percentage = Int(batteryLevel * 100)
        // 1. Entferne Lade-/Nicht-Lade-Informationen aus dem Text
        let batteryText = "\(percentage)%"
        
        // 2. Setze die Icon-Farbe immer auf sekundär (grau/weiß)
        let iconColor: Color = .secondary
        
        // 3. Verwende `isCharging` nur, um das .bolt-Symbol auszuwählen.
        let batteryIconName = self.batteryIcon(for: batteryLevel, isCharging: isCharging)
        
        // 4. Gib die Zeile mit der neutralen Farbe zurück
        return SystemInfoRow(icon: batteryIconName, label: "Battery", value: batteryText, iconColor: iconColor)
    }
    // MARK: - Monitor formatting helpers
    private func monitorLabel(for m: MonitorInfo) -> String {
        if m.isBuiltin { return m.isMain ? "Built-in (Main)" : "Built-in" }
        if m.isMain { return "External (Main)" }
        return "External"
    }

    private func monitorValue(for m: MonitorInfo) -> String {
        let res = "\(m.resolutionWidth)×\(m.resolutionHeight)"
        let hz: String = {
            if let r = m.refreshRate, r > 0 { return "@ \(Int((r).rounded())) Hz" }
            else { return "" }
        }()
        let scaleStr: String = {
            let rounded = (m.scale * 10).rounded() / 10
            if abs(rounded - rounded.rounded(.toNearestOrAwayFromZero)) < 0.0001 {
                return "\(Int(rounded))×"
            } else {
                return String(format: "%.1f×", rounded)
            }
        }()
        let hdr = m.isHDR ? "HDR On" : "HDR Off"
        return [res + (hz.isEmpty ? "" : " " + hz), scaleStr, m.colorSpaceName, hdr]
            .joined(separator: " • ")
    }
}

// Helper View for consistent row layout in System Info tile
struct SystemInfoRow: View {
    let icon: String
    let label: String
    let value: String
    var iconColor: Color = .secondary

    var body: some View {
        HStack(alignment: .center) { // CHANGED: Explicit spacing removed, using Spacer now
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(iconColor)
                .frame(width: 25, alignment: .center) // Fixed width for the icon
            
            Spacer().frame(width: 8) // NEW: Fixed spacing between icon and label
            
            Text(label) // Removed the colon here
                .foregroundColor(.secondary)
                .lineLimit(1) // Ensure the label doesn't wrap
                // The label doesn't get a fixed width or priority to remain flexible
            
            Spacer(minLength: 5) // This Spacer pushes the value text to the right
            
            Text(value)
                .font(.body)
                .lineLimit(1) // Ensure the value text doesn't wrap
                .minimumScaleFactor(0.7) // Allows text to shrink
                .multilineTextAlignment(.trailing) // Right alignment
                .layoutPriority(1) // Gives the value text higher priority in claiming space
        }
    }
}

#Preview {
    SystemInfoTileView()
        .frame(width: 400, height: 300)
}
