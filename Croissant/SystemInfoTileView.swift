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
                SystemInfoRow(icon: "hourglass", label: "Uptime", value: manager.uptime.formattedUptime())
                
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

                // External Monitor Info
                SystemInfoRow(icon: "display", label: "Monitor", value: manager.externalMonitorConnected ? "Connected" : "Not connected")
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
        var batteryText = "\(percentage)%"
        var iconColor: Color = .primary
        
        if let isCharging = isCharging {
            if isCharging {
                batteryText += " (Charging)"
                iconColor = .green // Always green when charging
            } else {
                batteryText += " (Not charging)"
                if percentage <= 20 { // Low battery when not charging
                    iconColor = .red
                } else {
                    iconColor = .primary // Ensure it's primary if not charging and not low
                }
            }
        } else {
            // Charging status unknown, only base on level for color
            if percentage <= 20 {
                 iconColor = .red
            } else {
                iconColor = .primary // Ensure it's primary if charging status is unknown and not low
            }
        }
        
        let batteryIconName = self.batteryIcon(for: batteryLevel, isCharging: isCharging)
        return SystemInfoRow(icon: batteryIconName, label: "Battery", value: batteryText, iconColor: iconColor)
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
