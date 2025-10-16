//
//  CalendarTileView.swift
//  Dashboard
//
//  Created by Frederik Mondel on 15.10.25.
//

import SwiftUI
import EventKit
import AppKit // For NSWorkspace, to open URLs

struct CalendarTileView: View {
    @ObservedObject var manager: EventKitManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Calendar Events", systemImage: "calendar") // Corrected to "Calendar Events"
                .font(.headline)
            
            if manager.eventsAccessGranted {
                if manager.events.isEmpty {
                    Text("No events today 🎉")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    ScrollView { // Added ScrollView to accommodate many events
                        VStack(alignment: .leading, spacing: 4) { // Wrapped in VStack for consistent spacing
                            ForEach(manager.events, id: \.calendarItemIdentifier) { event in // Removed .prefix(3)
                                EventRow(event: event)
                                    .onTapGesture {
                                        openEventInCalendarApp(event: event)
                                    }
                            }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Access to calendars not granted.") // Translated
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    Button("Request Access") { // Translated
                        manager.requestAccessToEvents()
                    }
                    .buttonStyle(.borderedProminent) // More prominent button for permission
                }
            }
        }
        // .tileStyle() // REMOVED: DashboardTileView now applies the styling
    }

    private func openEventInCalendarApp(event: EKEvent) {
        // IMPORTANT: The "ical://" URL scheme is undocumented and not officially supported by Apple.
        // Its behavior may change or stop functioning in future macOS versions.
        // It attempts to open the Calendar app and navigate to the specific event using the calendarItemIdentifier.

        if let url = URL(string: "ical://ekevent/\(event.calendarItemIdentifier)") {
            NSWorkspace.shared.open(url)
        } else {
            print("Error: Could not construct URL for event '\(event.title ?? "Unnamed Event")'.") // Translated
            // Fallback: Just open the Calendar app using the modern API
            if let calendarAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
                NSWorkspace.shared.openApplication(at: calendarAppURL, configuration: .init()) { _, error in
                    if let error = error {
                        print("Error opening Calendar app: \(error.localizedDescription)")
                    }
                }
            } else {
                print("Error: Could not find Calendar application URL to open.")
            }
        }
    }
}

// Separate View for a single calendar entry row to encapsulate the logic
struct EventRow: View {
    let event: EKEvent

    var body: some View {
        HStack(alignment: .top) { // Changed to HStack to accommodate the color bar
            // Farblicher Balken für den Kalender
            Rectangle()
                .fill(event.calendar.cgColor.map { Color(cgColor: $0) } ?? Color.gray) // Standardfarbe Grau, falls keine Kalenderfarbe verfügbar ist
                .frame(width: 5)
                .cornerRadius(2.5) // Leicht abgerundete Ecken für den Balken

            // Original content, now nested
            HStack(alignment: .top) {
                // Handles all-day events vs. time-bound events
                if event.isAllDay {
                    Text("All Day") // Translated from "Ganztägig"
                        .font(.caption)
                        .frame(width: 60, alignment: .leading)
                } else {
                    Text(event.startDate, format: .dateTime.hour().minute())
                        .font(.caption)
                        .frame(width: 60, alignment: .leading)
                }
                
                VStack(alignment: .leading) {
                    Text(event.title ?? "Unnamed Event") // Translated from "Unbenannter Termin"
                        .font(.body)
                        .fontWeight(.medium)
                    if let location = event.location, !location.isEmpty {
                        Text(location)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 2)
        // Ensures the entire row is recognized as a clickable area
        .contentShape(Rectangle()) 
    }
}
