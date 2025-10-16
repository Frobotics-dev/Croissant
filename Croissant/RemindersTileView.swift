//
//  RemindersTileView.swift
//  Dashboard
//
//  Created by Frederik Mondel on 15.10.25.
//

import SwiftUI
import EventKit

// Changed struct name from RemindersTileView2 to RemindersTileView to match ContentView
struct RemindersTileView: View { 
    @ObservedObject var manager: EventKitManager
    @State private var showingAddEditReminderSheet = false
    @State private var selectedReminderToEdit: EKReminder?

    // Access the UndoManager from the environment
    @Environment(\.undoManager) var undoManager: UndoManager?

    // For the 3-second delay (now managed primarily by EventKitManager, but keeping state vars for context)
    @State private var pendingCompletionTimers: [String: Timer] = [:]
    @State private var pendingCompletionTasks: [String: Task<Void, Never>] = [:] // With Swift Concurrency

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Reminders", systemImage: "checkmark.circle")
                    .font(.headline)
                
                Spacer()
                
                // Button to add a new reminder
                Button {
                    selectedReminderToEdit = nil // Ensure it's a new reminder
                    showingAddEditReminderSheet = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            }
            
            if manager.remindersAccessGranted {
                if manager.reminders.isEmpty && manager.pendingCompletedReminders.isEmpty {
                    Text("No reminders for today or overdue.")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(manager.reminders, id: \.calendarItemIdentifier) { reminder in
                                ReminderRow(reminder: reminder, manager: manager) { // Action for the checkbox toggle
                                    toggleCompletion(for: reminder)
                                }
                                .onTapGesture { // Action for editing the reminder
                                    selectedReminderToEdit = reminder
                                    showingAddEditReminderSheet = true
                                }
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
        }
        // .tileStyle() // REMOVED: DashboardTileView now applies the styling
        .onAppear {
            manager.fetchReminders()
            manager.fetchAvailableCalendars() // Also load calendars for Edit/Add View
        }
        .sheet(isPresented: $showingAddEditReminderSheet) {
            ReminderEditView(eventKitManager: manager, reminderToEdit: selectedReminderToEdit)
                .frame(minWidth: 400, minHeight: 600) // Minimum size for the sheet window
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
