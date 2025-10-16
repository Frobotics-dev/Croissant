//
//  EventKitManager.swift
//  Dashboard
//
//  Created by Frederik Mondel on 15.10.25.
//

import Foundation
import EventKit
import SwiftUI
import Combine

class EventKitManager: ObservableObject {
    // Changed access level from 'private' to 'internal' for preview access.
    let eventStore = EKEventStore()

    // Published properties for reminders and calendar events
    @Published var reminders: [EKReminder] = []
    @Published var events: [EKEvent] = []
    
    // Published properties for access status
    @Published var remindersAccessGranted: Bool = false
    @Published var eventsAccessGranted: Bool = false
    
    // Published properties for available calendars and their selection
    @Published var allEventCalendars: [EKCalendar] = []
    @Published var selectedEventCalendarIDs: Set<String> {
        didSet {
            saveSelectedCalendarIDs() // Saves the selection when it changes
            if eventsAccessGranted { fetchEvents() } // Updates events when selection changes
        }
    }

    @Published var allReminderCalendars: [EKCalendar] = []
    @Published var selectedReminderCalendarIDs: Set<String> {
        didSet {
            saveSelectedCalendarIDs() // Saves the selection when it changes
            if remindersAccessGranted { fetchReminders() } // Updates reminders when selection changes
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    private let userDefaultsKeyEvents = "selectedEventCalendarIDs"
    private let userDefaultsKeyReminders = "selectedReminderCalendarIDs"

    // Add a state for reminders marked as 'completed' but not yet saved (for the delay)
    @Published var pendingCompletedReminders: Set<String> = []

    // EventKitManager now manages the pending completion tasks for better undo integration
    private var pendingCompletionTasks: [String: Task<Void, Never>] = [:]

    init() {
        // Initialize selected calendar IDs from UserDefaults
        if let savedEventIDs = UserDefaults.standard.array(forKey: userDefaultsKeyEvents) as? [String] {
            self.selectedEventCalendarIDs = Set(savedEventIDs)
        } else {
            self.selectedEventCalendarIDs = [] // Nothing selected by default
        }
        
        if let savedReminderIDs = UserDefaults.standard.array(forKey: userDefaultsKeyReminders) as? [String] {
            self.selectedReminderCalendarIDs = Set(savedReminderIDs)
        } else {
            self.selectedReminderCalendarIDs = [] // Nothing selected by default
        }
        
        // super.init() is not necessary as ObservableObject is a protocol and not a superclass with an initializer.

        // Observe changes in the Event Store
        NotificationCenter.default.publisher(for: .EKEventStoreChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.eventStoreChanged()
            }
            .store(in: &cancellables)
        
        checkAuthorizationStatus() // Check authorization status on initialization
    }
    
    // Method called when the Event Store changes or on startup
    private func eventStoreChanged() {
        checkAuthorizationStatus() // Recheck authorization status
        
        // Reload all calendars after changes in the Event Store
        fetchAvailableCalendars()
        
        // If access is granted, fetch data
        if remindersAccessGranted { fetchReminders() }
        else { reminders = [] } // Clear reminders if no access
        
        if eventsAccessGranted { fetchEvents() }
        else { events = [] } // Clear events if no access
    }

    // Saves the selected calendar IDs to UserDefaults
    private func saveSelectedCalendarIDs() {
        UserDefaults.standard.set(Array(selectedEventCalendarIDs), forKey: userDefaultsKeyEvents)
        UserDefaults.standard.set(Array(selectedReminderCalendarIDs), forKey: userDefaultsKeyReminders)
    }

    // Checks the current authorization status for reminders and calendars
    private func checkAuthorizationStatus() {
        remindersAccessGranted = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        eventsAccessGranted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        
        if remindersAccessGranted || eventsAccessGranted {
            fetchAvailableCalendars() // Fetch available calendars once access is granted
        }
    }
    
    // Fetches all available calendars for events and reminders
    func fetchAvailableCalendars() {
        if eventsAccessGranted {
            allEventCalendars = eventStore.calendars(for: .event).sorted { $0.title < $1.title }
            // If no selection has been made yet, select all (initially)
            if selectedEventCalendarIDs.isEmpty && !allEventCalendars.isEmpty {
                selectedEventCalendarIDs = Set(allEventCalendars.map { $0.calendarIdentifier })
            }
        } else {
            allEventCalendars = []
            selectedEventCalendarIDs = []
        }
        
        if remindersAccessGranted {
            allReminderCalendars = eventStore.calendars(for: .reminder).sorted { $0.title < $1.title }
            // If no selection has been made yet, select all (initially)
            if selectedReminderCalendarIDs.isEmpty && !allReminderCalendars.isEmpty {
                selectedReminderCalendarIDs = Set(allReminderCalendars.map { $0.calendarIdentifier })
            }
        } else {
            allReminderCalendars = []
            selectedReminderCalendarIDs = []
        }
    }

    // Requests full access to reminders
    func requestAccessToReminders() {
        let currentStatus = EKEventStore.authorizationStatus(for: .reminder)
        
        guard currentStatus != .fullAccess else {
            remindersAccessGranted = true
            fetchAvailableCalendars()
            fetchReminders()
            return
        }
        
        if currentStatus == .denied || currentStatus == .restricted {
            print("Reminder access denied or restricted. Please enable in System Settings.") // Console print, not UI
            return
        }

        eventStore.requestFullAccessToReminders { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.remindersAccessGranted = granted
                if granted {
                    self?.fetchAvailableCalendars() // Load calendars after access
                    self?.fetchReminders()
                } else if let error = error {
                    print("Error requesting reminder access: \(error.localizedDescription)") // Console print, not UI
                }
            }
        }
    }

    // Requests full access to calendar events
    func requestAccessToEvents() {
        let currentStatus = EKEventStore.authorizationStatus(for: .event)
        
        guard currentStatus != .fullAccess else {
            eventsAccessGranted = true
            fetchAvailableCalendars()
            fetchEvents()
            return
        }
        
        if currentStatus == .denied || currentStatus == .restricted {
            print("Calendar access denied or restricted. Please enable in System Settings.") // Console print, not UI
            return
        }

        eventStore.requestFullAccessToEvents { [weak self] granted, error in
            DispatchQueue.main.async {
                self?.eventsAccessGranted = granted
                if granted {
                    self?.fetchAvailableCalendars() // Load calendars after access
                    self?.fetchEvents()
                } else if let error = error {
                    print("Error requesting calendar access: \(error.localizedDescription)") // Console print, not UI
                }
            }
        }
    }

    // Fetches reminders that are due today or overdue, but not yet completed
    func fetchReminders() {
        guard remindersAccessGranted else {
            reminders = []
            return
        }
        
        let calendar = Calendar.current
        let today = Date()
        
        // Calculate the start of tomorrow to include all reminders up to the end of today
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
              let startOfTomorrow = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: tomorrow) else {
            reminders = []
            print("Error: Could not calculate start of tomorrow.") // Console print, not UI
            return
        }
        
        // Filter calendars based on user selection
        let calendarsToFetch = allReminderCalendars.filter { selectedReminderCalendarIDs.contains($0.calendarIdentifier) }
        
        // If no calendars are selected, there are no reminders to fetch
        guard !calendarsToFetch.isEmpty else {
            reminders = []
            return
        }
        
        // Use a predicate that fetches all incomplete reminders (without specific due date restriction in the predicate itself)
        // Filtering for "today or overdue" happens manually afterwards.
        let predicateForIncomplete = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: calendarsToFetch)

        eventStore.fetchReminders(matching: predicateForIncomplete) { [weak self] fetchedReminders in
            DispatchQueue.main.async {
                guard let self = self else { return }
                let filteredAndSortedReminders = fetchedReminders?
                    .filter { reminder in
                        // Filter out reminders that are already marked as pending
                        // This check is crucial for the UI to immediately reflect the pending state
                        guard !self.pendingCompletedReminders.contains(reminder.calendarItemIdentifier) else { return false }
                        
                        // Check if the reminder is actually completed in the store (this should generally be false
                        // for fetched incomplete reminders, but good for robustness).
                        guard !reminder.isCompleted else { return false }
                        
                        // Check due date: today or overdue
                        if let dueDateComponents = reminder.dueDateComponents,
                           let dueDate = calendar.date(from: dueDateComponents) {
                            // A reminder is "today or overdue" if its due date is before the start of tomorrow.
                            return dueDate < startOfTomorrow
                        }
                        // If no due date is present, we exclude them by default,
                        // as the requirement "today or overdue" refers to dated reminders.
                        return false 
                    }
                    .sorted {
                        let date1 = $0.dueDateComponents?.date ?? .distantFuture
                        let date2 = $1.dueDateComponents?.date ?? .distantFuture
                        return date1 < date2
                    } ?? []
                
                self.reminders = filteredAndSortedReminders
            }
        }
    }

    // Fetches calendar events for today
    func fetchEvents() {
        guard eventsAccessGranted else {
            events = []
            return
        }

        let calendar = Calendar.current
        let today = Date()
        
        guard let startOfToday = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: today),
              let endOfToday = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: today) else {
            events = []
            return
        }
        
        // Filter calendars based on user selection
        let calendarsToFetch = allEventCalendars.filter { selectedEventCalendarIDs.contains($0.calendarIdentifier) }
        
        // If no calendars are selected, there are no events to fetch
        guard !calendarsToFetch.isEmpty else {
            events = []
            return
        }

        let predicate = eventStore.predicateForEvents(withStart: startOfToday, end: endOfToday, calendars: calendarsToFetch)

        let fetchedEvents = eventStore.events(matching: predicate)
        DispatchQueue.main.async {
            self.events = fetchedEvents.sorted { $0.startDate < $1.startDate }
        }
    }
    
    // MARK: - Reminder Management
    
    // Marks a reminder as completed temporarily, but does not save immediately
    func markReminderAsCompletedTemporarily(_ reminder: EKReminder) {
        guard remindersAccessGranted else { return }
        
        // Cancel any existing pending task for this reminder
        pendingCompletionTasks[reminder.calendarItemIdentifier]?.cancel()
        pendingCompletionTasks.removeValue(forKey: reminder.calendarItemIdentifier)

        do {
            // EKReminder is a reference type, modifying it directly affects the instance in eventStore.
            // Saving with commit: false stages the change without writing to persistent storage yet.
            reminder.isCompleted = true
            try eventStore.save(reminder, commit: false)
            
            DispatchQueue.main.async {
                self.pendingCompletedReminders.insert(reminder.calendarItemIdentifier)
                self.fetchReminders() // Update the list to visually remove the reminder
            }

            // Start the 3-second delay task
            let task = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(3)) // Wait 3 seconds
                    if !Task.isCancelled {
                        DispatchQueue.main.async {
                            // Only commit if it's still marked as pending
                            if self?.pendingCompletedReminders.contains(reminder.calendarItemIdentifier) == true {
                                self?.commitReminderChanges()
                            }
                        }
                    }
                } catch {
                    print("Completion task for reminder \(reminder.calendarItemIdentifier) was cancelled.")
                }
                DispatchQueue.main.async {
                    self?.pendingCompletionTasks.removeValue(forKey: reminder.calendarItemIdentifier)
                }
            }
            pendingCompletionTasks[reminder.calendarItemIdentifier] = task

        } catch {
            print("Error temporarily marking reminder as completed: \(error.localizedDescription)") // Console print, not UI
        }
    }
    
    // Helper for redo operation: marks a reminder as completed, including setting up the task
    // Similar to markReminderAsCompletedTemporarily but handles undo registration externally
    func markReminderAsCompletedForRedo(_ reminder: EKReminder) {
        // This method is called by the UndoManager's redo. It should re-mark the reminder as complete,
        // which includes the 3-second delay logic.
        guard remindersAccessGranted else { return }

        // Cancel any existing pending task for this reminder
        pendingCompletionTasks[reminder.calendarItemIdentifier]?.cancel()
        pendingCompletionTasks.removeValue(forKey: reminder.calendarItemIdentifier)

        do {
            reminder.isCompleted = true
            try eventStore.save(reminder, commit: false)
            DispatchQueue.main.async {
                self.pendingCompletedReminders.insert(reminder.calendarItemIdentifier)
                self.fetchReminders()
            }

            let task = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(3))
                    if !Task.isCancelled {
                        DispatchQueue.main.async {
                            if self?.pendingCompletedReminders.contains(reminder.calendarItemIdentifier) == true {
                                self?.commitReminderChanges()
                            }
                        }
                    }
                } catch {
                    print("Redo completion task for reminder \(reminder.calendarItemIdentifier) was cancelled.")
                }
                DispatchQueue.main.async {
                    self?.pendingCompletionTasks.removeValue(forKey: reminder.calendarItemIdentifier)
                }
            }
            pendingCompletionTasks[reminder.calendarItemIdentifier] = task

        } catch {
            print("Error re-marking reminder as completed for redo: \(error.localizedDescription)")
        }
    }


    // Reverts the temporary completion mark and cancels any pending task
    func unmarkReminderAsCompleted(_ reminder: EKReminder) {
        guard remindersAccessGranted else { return }
        
        // Cancel any pending task associated with this reminder
        pendingCompletionTasks[reminder.calendarItemIdentifier]?.cancel()
        pendingCompletionTasks.removeValue(forKey: reminder.calendarItemIdentifier)

        // Remove from pending list
        DispatchQueue.main.async {
            self.pendingCompletedReminders.remove(reminder.calendarItemIdentifier)
            
            // Crucial change: Explicitly set isCompleted to false and save (without commit)
            // to revert the in-memory state of the reminder in EventKit.
            if let latestReminder = self.eventStore.calendarItem(withIdentifier: reminder.calendarItemIdentifier) as? EKReminder {
                 if latestReminder.isCompleted { // Only revert if it was actually marked completed
                    latestReminder.isCompleted = false
                    do {
                        try self.eventStore.save(latestReminder, commit: false) // commit: false to only revert the temporary state
                        self.fetchReminders() // Reload the list to show the reminder again
                    } catch {
                        print("Error reverting temporary reminder completion: \(error.localizedDescription)")
                    }
                } else {
                    // If it was already false, just fetch to update the UI
                    self.fetchReminders()
                }
            } else {
                print("Error: Could not find reminder with identifier \(reminder.calendarItemIdentifier) to unmark.")
                self.fetchReminders() // Still try to refresh the UI
            }
        }
    }
    
    // Saves all pending changes (e.g., a reminder temporarily marked as completed)
    func commitReminderChanges() {
        guard remindersAccessGranted else { return }
        
        do {
            try eventStore.commit()
            DispatchQueue.main.async {
                self.pendingCompletedReminders.removeAll() // Clear all pending reminders after commit
                self.fetchReminders() // Reload the list to reflect the final state
            }
        } catch {
            print("Error saving reminder changes: \(error.localizedDescription)") // Console print, not UI
        }
    }

    // New method for undoing completion from any state (pending or committed)
    func revertReminderCompletion(for reminder: EKReminder, with undoManager: UndoManager?) {
        guard remindersAccessGranted else { return }

        // Register the redo action
        undoManager?.registerUndo(withTarget: self) { managerTarget in
            // When redo, we re-mark it as complete, potentially starting the 3-sec delay again.
            managerTarget.markReminderAsCompletedForRedo(reminder)
            // The redo action name is handled by the manager
        }
        undoManager?.setActionName("Erinnerung erledigen") // Set action name for redo (which is completing)

        // --- Actual undo logic ---

        // 1. If reminder is in pending state (was marked temporarily, not yet committed)
        if pendingCompletedReminders.contains(reminder.calendarItemIdentifier) {
            self.unmarkReminderAsCompleted(reminder) // This also cancels the task and now reverts isCompleted state
        } else {
            // 2. If reminder was already committed (isCompleted is true in EventKit)
            // Need to fetch the latest reminder object
            if let latestReminder = eventStore.calendarItem(withIdentifier: reminder.calendarItemIdentifier) as? EKReminder {
                // EKReminder is a reference type, modifying latestReminder directly affects it.
                latestReminder.isCompleted = false
                do {
                    // Save this change permanently
                    try eventStore.save(latestReminder, commit: true)
                    DispatchQueue.main.async {
                        self.fetchReminders() // Show it again in the UI
                    }
                } catch {
                    print("Error undoing committed reminder: \(error.localizedDescription)")
                }
            } else {
                print("Error: Could not find reminder with identifier \(reminder.calendarItemIdentifier) for undo.")
            }
        }
    }


    // Saves a new or updated reminder
    func saveReminder(_ reminder: EKReminder, in calendar: EKCalendar) throws {
        guard remindersAccessGranted else {
            throw EventKitError.accessDenied
        }

        // Ensure the reminder is associated with the correct calendar
        if reminder.calendar != calendar {
            reminder.calendar = calendar
        }
        
        // Check if it's a new reminder
        if reminder.calendarItemIdentifier.isEmpty { // Changed to check only isEmpty
            // New reminder
            // EKEventStore.save(EKCalendarItem) is for new reminders
            try eventStore.save(reminder, commit: true)
        } else {
            // Update existing reminder
            // EKEventStore.save(EKCalendarItem) for existing is also fine
            try eventStore.save(reminder, commit: true)
        }
        
        DispatchQueue.main.async {
            self.fetchReminders() // Update the list after saving
        }
    }
    
    // Deletes a reminder
    func deleteReminder(_ reminder: EKReminder) throws {
        guard remindersAccessGranted else {
            throw EventKitError.accessDenied
        }
        try eventStore.remove(reminder, commit: true)
        DispatchQueue.main.async {
            self.fetchReminders() // Update the list after deleting
        }
    }
    
    // Custom Error for EventKitManager
    enum EventKitError: Error, LocalizedError {
        case accessDenied
        case saveFailed(String)
        case deleteFailed(String)
        
        var errorDescription: String? {
            switch self {
            case .accessDenied:
                return "Access to EventKit was denied."
            case .saveFailed(let message):
                return "Save failed: \(message)"
            case .deleteFailed(let message):
                return "Delete failed: \(message)"
            }
        }
    }
}
