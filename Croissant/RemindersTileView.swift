//
//  RemindersTileView.swift
//  Dashboard
//
//  Created by Frederik Mondel on 15.10.25.
//

import SwiftUI
import EventKit

// Make EKReminder Identifiable for use with sheet(item:)
extension EKReminder: @retroactive Identifiable {
    public var id: String {
        // EKReminder's calendarItemIdentifier is a unique string that can be used as an ID.
        // It's stable across saves and reloads from the Event Store.
        return calendarItemIdentifier
    }
}

// Enum to manage sheet content more robustly
private enum SheetContent: Identifiable {
    case newReminder
    case editReminder(EKReminder)

    var id: String {
        switch self {
        case .newReminder: return "newReminder" // Unique ID for new reminder
        case .editReminder(let reminder): return reminder.id // Use EKReminder's ID
        }
    }
}


// Changed struct name from RemindersTileView2 to RemindersTileView to match ContentView
struct RemindersTileView: View { 
    @ObservedObject var manager: EventKitManager
    // @State private var showingAddEditReminderSheet = false // Replaced by activeSheet
    // @State private var selectedReminderToEdit: EKReminder? // Replaced by activeSheet

    @State private var activeSheet: SheetContent? = nil // New state to manage sheet content

    // Access the UndoManager from the environment
    @Environment(\.undoManager) var undoManager: UndoManager?

    // For the 3-second delay (now managed primarily by EventKitManager, but keeping state vars for context)
    @State private var pendingCompletionTimers: [String: Timer] = [:]
    @State private var pendingCompletionTasks: [String: Task<Void, Never>] = [:] // With Swift Concurrency

    // ADDED: State variable for date navigation
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    // ADDED: Computed property for formatted date display, mirroring CalendarTileView
    private var formattedSelectedDate: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDate) {
            return "Today"
        }
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US") // Matching CalendarTileView
        
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
                Label("Reminders", systemImage: "checkmark.circle")
                    .font(.headline)
                
                Spacer() // This Spacer will push the date navigation to the far right
                
                // Day navigation controls, mirroring CalendarTileView
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
                .frame(minWidth: 120, alignment: .center) // Match CalendarTileView frame

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
            
            if manager.remindersAccessGranted {
                if manager.reminders.isEmpty && manager.pendingCompletedReminders.isEmpty {
                    // MODIFIED: Message reflects selectedDate and the new logic for "Today"
                    if Calendar.current.isDateInToday(selectedDate) {
                        Text("No reminders for today or overdue.")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        Text("No reminders for \(formattedSelectedDate).")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(manager.reminders, id: \.calendarItemIdentifier) { reminder in
                                ReminderRow(
                                    reminder: reminder,
                                    manager: manager,
                                    onToggleCompletion: { toggleCompletion(for: reminder) },
                                    onEdit: { reminderToEdit in // Übergeben der Aktion an ReminderRow
                                        activeSheet = .editReminder(reminderToEdit) // Setzt activeSheet auf Bearbeiten
                                    }
                                )
                                // TapGesture and ContextMenu moved into ReminderRow for better hit testing
                            }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Access to reminders not granted.")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                    Button("Request Access") {
                        manager.requestAccessToReminders()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            
            Spacer() // This Spacer forces the VStack to fill all available vertical space
        }
        // .tileStyle() // REMOVED: DashboardTileView now applies the styling
        .onAppear {
            manager.fetchReminders(for: selectedDate) // MODIFIED: Pass selectedDate
            manager.fetchAvailableCalendars() // Also load calendars for Edit/Add View
        }
        // ADDED: Fetch reminders when selectedDate changes
        .onChange(of: selectedDate) { _, newDate in
            manager.fetchReminders(for: newDate)
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            // Reload reminders when Event Store changes (e.g., reminder saved/deleted in sheet or via context menu)
            manager.fetchReminders(for: selectedDate)
        }
        // Use sheet(item:) with our SheetContent enum
        .sheet(item: $activeSheet) { sheetContent in
            Group {
                switch sheetContent {
                case .newReminder:
                    ReminderEditView(eventKitManager: manager, reminderToEdit: nil)
                case .editReminder(let reminder):
                    ReminderEditView(eventKitManager: manager, reminderToEdit: reminder)
                }
            }
            .frame(minWidth: 400, minHeight: 600) // Minimum size for the sheet window
        }
        // ADDED: Plus button moved to bottom-right overlay
        .overlay(alignment: .bottomTrailing) {
            Button {
                activeSheet = .newReminder // Set activeSheet to create a new reminder
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
    
    private func toggleCompletion(for reminder: EKReminder) {
        // Check if the reminder is already marked as pending
        if manager.pendingCompletedReminders.contains(reminder.calendarItemIdentifier) {
            // If yes, revert the action (user clicked again on a pending reminder)
            manager.unmarkReminderAsCompleted(reminder)
            // Die Task-Abbrechung wird nun direkt vom EventKitManager gehandhabt
        } else {
            // If no, mark as pending and start timer
            
            // Registriere die Rückgängig-Aktion VOR der eigentlichen Änderung.
            // Diese Aktion wird sowohl temporäre als auch dauerhafte Erledigungen rückgängig machen können.
            undoManager?.registerUndo(withTarget: manager) { managerTarget in
                managerTarget.revertReminderCompletion(for: reminder, with: self.undoManager)
            }
            undoManager?.setActionName("Erinnerung erledigen") // Name für das "Bearbeiten"-Menü
            
            manager.markReminderAsCompletedTemporarily(reminder) // Der Manager verwaltet nun seine eigenen Tasks.
        }
    }
}

// Separate View for a single reminder row to encapsulate the logic
struct ReminderRow: View {
    let reminder: EKReminder // EKReminder is not an ObservableObject
    @ObservedObject var manager: EventKitManager
    var onToggleCompletion: () -> Void
    var onEdit: (EKReminder) -> Void // Closure to trigger edit in parent view

    // State variable for the visual representation of the strikethrough
    @State private var isVisuallyPendingCompletion: Bool = false

    // Computed property to determine if the reminder is overdue
    private var isOverdue: Bool {
        guard let dueDateComponents = reminder.dueDateComponents,
              let dueDate = Calendar.current.date(from: dueDateComponents) else {
            return false // No due date, so not overdue
        }

        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfDueDate = calendar.startOfDay(for: dueDate)

        // Überprüfen, ob es eine Ganztageserinnerung ist (keine Stunden-/Minutenkomponenten)
        if dueDateComponents.hour == nil && dueDateComponents.minute == nil {
            // Ganztageserinnerungen sind überfällig, wenn ihr Datum VOR dem heutigen Tag liegt.
            // (Eine Ganztageserinnerung für "heute" ist NICHT überfällig).
            return startOfDueDate < startOfToday
        } else {
            // Zeitspezifische Erinnerungen sind überfällig, wenn ihre genaue Fälligkeitszeit in der Vergangenheit liegt.
            return dueDate < Date()
        }
    }

    // Computed property to format the due date/time string
    private var formattedDueDate: String? {
        guard let dueDateComponents = reminder.dueDateComponents else { return nil }

        // Check if it's an all-day reminder (no hour/minute components)
        if dueDateComponents.hour == nil && dueDateComponents.minute == nil {
            return "All Day"
        } else if let date = dueDateComponents.date {
            // Format only time (hour and minute)
            return date.formatted(.dateTime.hour().minute())
        }
        return nil
    }

    var body: some View {
        HStack {
            // Farblicher Balken für den Kalender
            Rectangle()
                .fill(reminder.calendar.cgColor.map { Color(cgColor: $0) } ?? Color.gray) // Standardfarbe Grau, falls keine Kalenderfarbe verfügbar ist
                .frame(width: 5)
                .cornerRadius(2.5) // Leicht abgerundete Ecken für den Balken

            Image(systemName: isVisuallyPendingCompletion ? "checkmark.circle.fill" : "circle") // Geändert zu runden Kreisen
                .foregroundColor(isVisuallyPendingCompletion ? .accentColor : .secondary)
                .onTapGesture {
                    onToggleCompletion()
                }
            
            VStack(alignment: .leading, spacing: 2) { // VStack für Titel und Kalendername
                Text(reminder.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .strikethrough(isVisuallyPendingCompletion, color: .secondary) // Visueller Effekt
                    // Titel färbt sich NICHT rot, auch wenn überfällig.
                    .foregroundColor(.primary) // Titel bleibt immer primärfarben, es sei denn durchgestrichen
                
                // Kalendername unter der Erinnerung
                Text(reminder.calendar.title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Optional: Display due date if available, using the new formatter
            if let formattedDate = formattedDueDate {
                Text(formattedDate)
                    .font(.caption)
                    .foregroundColor(isOverdue ? .red : .secondary) // Datumstext rot färben, wenn überfällig
            }
        }
        .padding(.vertical, 2)
        .opacity(isVisuallyPendingCompletion ? 0.6 : 1.0) // Leichtes Ausblenden, wenn ausstehend
        .animation(.easeOut(duration: 0.2), value: isVisuallyPendingCompletion)
        .onAppear {
            isVisuallyPendingCompletion = manager.pendingCompletedReminders.contains(reminder.calendarItemIdentifier)
        }
        .onChange(of: manager.pendingCompletedReminders) { _, newValue in
            isVisuallyPendingCompletion = newValue.contains(reminder.calendarItemIdentifier)
        }
        .contentShape(Rectangle()) // Makes the entire row respond to gestures
        .onTapGesture { // Now the entire row opens the edit sheet
            onEdit(reminder)
        }
        .contextMenu { // Right-click menu for additional actions
            Button("Edit") {
                onEdit(reminder)
            }
            Button("Postpone to Tomorrow") {
                postponeReminderToTomorrow()
            }
            Button("Delete", role: .destructive) {
                deleteReminder()
            }
        }
    }

    private func postponeReminderToTomorrow() {
        let calendar = Calendar.current
        var newDueDateComponents: DateComponents?

        if let currentDueDateComponents = reminder.dueDateComponents,
           let existingDate = calendar.date(from: currentDueDateComponents),
           let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: existingDate) {
            
            // If the original reminder had time components, preserve them for tomorrow
            if currentDueDateComponents.hour != nil || currentDueDateComponents.minute != nil {
                newDueDateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: tomorrowDate)
            } else {
                // Otherwise, it's an all-day reminder for tomorrow
                newDueDateComponents = calendar.dateComponents([.year, .month, .day], from: tomorrowDate)
            }
        } else {
            // If no due date, set it for tomorrow, all day
            if let tomorrowDate = calendar.date(byAdding: .day, value: 1, to: Date()) {
                newDueDateComponents = calendar.dateComponents([.year, .month, .day], from: tomorrowDate)
            }
        }
        
        if let newComponents = newDueDateComponents {
            reminder.dueDateComponents = newComponents
            do {
                try manager.saveReminder(reminder, in: reminder.calendar)
            } catch {
                print("Failed to save postponed reminder: \(error.localizedDescription)")
                // Optionally, set an error message in the manager or a local state here
            }
        }
    }

    private func deleteReminder() {
        do {
            try manager.deleteReminder(reminder)
        } catch {
            print("Failed to delete reminder from context menu: \(error.localizedDescription)")
            // Optionally, set an error message in the manager or a local state here
        }
    }
}

#Preview {
    // Create a dummy EventKitManager for the Preview
    let manager = EventKitManager()
    
    manager.remindersAccessGranted = true
    
    // Create a dummy calendar for the preview
    let dummyCalendar1 = EKCalendar(for: .reminder, eventStore: manager.eventStore)
    dummyCalendar1.title = "Family Reminders"
    dummyCalendar1.cgColor = NSColor.systemBlue.cgColor // Beispiel: Blaue Farbe
    
    let dummyCalendar2 = EKCalendar(for: .reminder, eventStore: manager.eventStore)
    dummyCalendar2.title = "Work Reminders"
    dummyCalendar2.cgColor = NSColor.systemRed.cgColor // Beispiel: Rote Farbe

    // Create a few dummy reminders and assign them to calendars
    let dummyReminder1 = EKReminder(eventStore: manager.eventStore)
    dummyReminder1.title = "Buy milk"
    // Fällig heute um eine Stunde in der Zukunft (nicht überfällig)
    dummyReminder1.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date().addingTimeInterval(3600))
    dummyReminder1.calendar = dummyCalendar1 // Zugeordnet zu Family Reminders
    
    let dummyReminder2 = EKReminder(eventStore: manager.eventStore)
    dummyReminder2.title = "Submit report (Overdue)"
    // Fällig gestern mit Uhrzeit, sollte rot und überfällig sein
    dummyReminder2.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: Date().addingTimeInterval(-3600 * 24)) // Yesterday
    dummyReminder2.calendar = dummyCalendar2 // Zugeordnet zu Work Reminders
    
    let dummyReminder3 = EKReminder(eventStore: manager.eventStore)
    dummyReminder3.title = "Call client (All Day - Today)"
    // Ganztägige Erinnerung für HEUTE (nicht überfällig)
    dummyReminder3.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    dummyReminder3.notes = "Regarding the new project and specifications."
    dummyReminder3.calendar = dummyCalendar1 // Zugeordnet zu Family Reminders

    // Eine weitere überfällige ganztägige Erinnerung (von gestern)
    let dummyReminder4 = EKReminder(eventStore: manager.eventStore)
    dummyReminder4.title = "Check old files (Overdue & All Day - Yesterday)"
    dummyReminder4.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date().addingTimeInterval(-3600 * 24 * 1)) // Vor 1 Tag (Ganztägig)
    dummyReminder4.calendar = dummyCalendar2

    // Eine zukünftige Ganztageserinnerung
    let dummyReminder5 = EKReminder(eventStore: manager.eventStore)
    dummyReminder5.title = "Next Week Task (All Day)"
    dummyReminder5.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: Date().addingTimeInterval(3600 * 24 * 7)) // In 7 Tagen
    dummyReminder5.calendar = dummyCalendar1
    
    manager.reminders = [dummyReminder1, dummyReminder2, dummyReminder3, dummyReminder4, dummyReminder5]
    manager.allReminderCalendars = [dummyCalendar1, dummyCalendar2] // Dummy Calendars

    return RemindersTileView(manager: manager) // Renamed the Preview call
        .frame(width: 400, height: 300) // Appropriate size for the tile preview
}

