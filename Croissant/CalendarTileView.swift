//
//  CalendarTileView.swift
//  Dashboard
//
//  Created by Frederik Mondel on 15.10.25.
//

import SwiftUI
import EventKit
import AppKit // For NSWorkspace, to open URLs

// Make EKEvent Identifiable for use with sheet(item:)
extension EKEvent: @retroactive Identifiable {
    public var id: String {
        // EKEvent's calendarItemIdentifier is a unique string that can be used as an ID.
        // It's stable across saves and reloads from the Event Store.
        return calendarItemIdentifier
    }
}

// Enum to manage sheet content more robustly (NEW)
private enum SheetContent: Identifiable {
    case newEvent
    case editEvent(EKEvent)

    var id: String {
        switch self {
        case .newEvent: return "newEvent" // Unique ID for new event
        case .editEvent(let event): return event.id // Use EKEvent's ID
        }
    }
}

struct CalendarTileView: View {
    @ObservedObject var manager: EventKitManager
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var activeSheet: SheetContent? = nil // New state to manage sheet content
    @Environment(\.undoManager) var undoManager: UndoManager? // Inject UndoManager

    private var eventsForSelectedDate: [EKEvent] {
        let cal = Calendar.current
        let start = selectedDate
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        return manager.events.filter { event in
            // Include events that intersect the selected day
            let eventStart = event.startDate ?? start
            let eventEnd = event.endDate ?? eventStart
            return (eventStart < end) && (eventEnd >= start)
        }
    }
    
    private var formattedSelectedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDate) {
            return "Today"
        }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        
        let currentYear = calendar.component(.year, from: Date())
        let selectedYear = calendar.component(.year, from: selectedDate)
        
        if currentYear == selectedYear {
            formatter.setLocalizedDateFormatFromTemplate("MMMMd") // e.g., "October 26"
        } else {
            formatter.setLocalizedDateFormatFromTemplate("MMM d, yyyy") // e.g., "Oct 26, 2024"
        }
        
        return formatter.string(from: selectedDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Calendar Events", systemImage: "calendar")
                    .font(.headline)
                Spacer()
                
                // Day navigation controls
                Button {
                    if let prev = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) {
                        selectedDate = Calendar.current.startOfDay(for: prev)
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .symbolRenderingMode(.monochrome)
                }
                .buttonStyle(.plain)

                Button {
                    selectedDate = Calendar.current.startOfDay(for: Date())
                } label: {
                    Text(formattedSelectedDate)
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .frame(minWidth: 120, alignment: .center)

                Button {
                    if let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) {
                        selectedDate = Calendar.current.startOfDay(for: next)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .symbolRenderingMode(.monochrome)
                }
                .buttonStyle(.plain)
            }
            
            if manager.eventsAccessGranted {
                if eventsForSelectedDate.isEmpty {
                    if Calendar.current.isDateInToday(selectedDate) {
                        Text("No events today 🎉")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        Text("No events for \(formattedSelectedDate) 🎉")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    ScrollView { // Added ScrollView to accommodate many events
                        VStack(alignment: .leading, spacing: 4) { // Wrapped in VStack for consistent spacing
                            ForEach(eventsForSelectedDate, id: \.calendarItemIdentifier) { event in
                                EventRow(
                                    event: event,
                                    onEdit: { eventToEdit in
                                        activeSheet = .editEvent(eventToEdit)
                                    },
                                    onDelete: { eventToDelete in
                                        deleteEvent(eventToDelete)
                                    },
                                    onOpenInCalendarApp: { eventToOpen in // NEW: Pass the action
                                        openEventInCalendarApp(event: eventToOpen)
                                    }
                                )
                                // Removed .onTapGesture here, now handled inside EventRow
                                // Removed .contextMenu here, now handled inside EventRow
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
            
            Spacer() // FIX: Dieser Spacer stellt sicher, dass der VStack die volle Höhe einnimmt, unabhängig vom Inhalt der ScrollView.
        }
        // .tileStyle() // REMOVED: DashboardTileView now applies the styling
        .onAppear {
            // Lade die Events für das initial ausgewählte Datum (heute)
            manager.fetchEvents(for: selectedDate)
            manager.fetchAvailableCalendars() // Also load calendars for Edit/Add View
        }
        .onChange(of: selectedDate) { _, newDate in // Updated onChange syntax
            // Lade die Events neu, wenn sich das Datum ändert
            manager.fetchEvents(for: newDate)
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            // Reload events when Event Store changes (e.g., event saved/deleted in sheet or via context menu)
            manager.fetchEvents(for: selectedDate)
        }
        // NEU: Bei Tageswechsel automatisch auf "Heute" zurücksetzen
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            selectedDate = Calendar.current.startOfDay(for: Date())
        }
        // Use sheet(item:) with our SheetContent enum (NEW)
        .sheet(item: $activeSheet) { sheetContent in
            Group { // Re-added Group here
                switch sheetContent {
                case .newEvent:
                    EventEditView(eventKitManager: manager, eventToEdit: nil)
                case .editEvent(let event):
                    EventEditView(eventKitManager: manager, eventToEdit: event)
                }
            } // Close Group here
            .frame(minWidth: 400, minHeight: 600) // Now applied to the Group's content
        }
        // ADDED: Plus button moved to bottom-right overlay
        .overlay(alignment: .bottomTrailing) {
            Button {
                activeSheet = .newEvent // Set activeSheet to create a new event
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                    .padding(10) // Padding around the icon for visual space
                    .background(.ultraThinMaterial) // Optional: subtle background for better visibility
                    .clipShape(Circle()) // Make the background circular
                    .shadow(radius: 5) // Optional: add a small shadow
            }
            .buttonStyle(.plain)
            .padding([.bottom, .trailing], 1) // MODIFIED: Reduced padding to 1
        }
    }

    private func deleteEvent(_ event: EKEvent) {
        do {
            try manager.deleteEvent(event, with: undoManager) // Pass undoManager here
        } catch {
            print("Failed to delete event from context menu: \(error.localizedDescription)")
            // Optionally, set an error message in the manager or a local state here
        }
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
    var onEdit: (EKEvent) -> Void // Closure to trigger edit in parent view
    var onDelete: (EKEvent) -> Void // Closure to trigger delete in parent view
    var onOpenInCalendarApp: (EKEvent) -> Void // NEW: Closure to open in Calendar app

    var body: some View {
        HStack(alignment: .top) {
            // Farblicher Balken für den Kalender
            Rectangle()
                .fill(event.calendar.cgColor.map { Color(cgColor: $0) } ?? Color.gray)
                .frame(width: 5)
                .cornerRadius(2.5)

            // Original content, now nested
            HStack(alignment: .top) {
                // Handles all-day events vs. time-bound events
                if event.isAllDay {
                    Text("All Day")
                        .font(.caption)
                        .frame(width: 60, alignment: .leading)
                } else {
                    Text(event.startDate, format: .dateTime.hour().minute())
                        .font(.caption)
                        .frame(width: 60, alignment: .leading)
                }
                
                VStack(alignment: .leading) {
                    Text(event.title ?? "Unnamed Event")
                        .font(.body)
                        .fontWeight(.medium)
                    if let location = event.location, !location.isEmpty {
                        Text(location)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer() // NEW: Pushes content to the left, making the row fill width
            }
        }
        .padding(.vertical, 2)
        // Ensures the entire row is recognized as a clickable area
        .contentShape(Rectangle())
        .onTapGesture { // MOVED: Tap gesture now on the whole row
            onEdit(event)
        }
        .contextMenu { // Keep context menu here
            Button("Edit") {
                onEdit(event)
            }
            Button("Open in Calendar App") {
                onOpenInCalendarApp(event) // NEW: Use the closure
            }
            Divider()
            Button("Delete", role: .destructive) {
                onDelete(event)
            }
        }
    }
}
