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

// Helper struct to capture EKEvent properties for undo/redo
struct EventSnapshot {
    let identifier: String // Use identifier to find the event later
    let title: String
    let notes: String?
    let location: String?
    let isAllDay: Bool
    let startDate: Date
    let endDate: Date
    let calendarIdentifier: String // Store calendar ID
    // Add other relevant properties if needed (e.g., recurrence rules, alarms)

    init(event: EKEvent) {
        // For new events, identifier might be empty initially. It's assigned on save.
        // We'll primarily use this for existing/deleted events.
        self.identifier = event.calendarItemIdentifier
        self.title = event.title
        self.notes = event.notes
        self.location = event.location
        self.isAllDay = event.isAllDay
        self.startDate = event.startDate ?? Date() // Fallback for safety
        self.endDate = event.endDate ?? Date()     // Fallback for safety
        self.calendarIdentifier = event.calendar?.calendarIdentifier ?? "" // Fallback for safety
    }

    // Applies this snapshot's data to an existing EKEvent
    func apply(to event: EKEvent, eventStore: EKEventStore) {
        event.title = self.title
        event.notes = self.notes
        event.location = self.location
        event.isAllDay = self.isAllDay
        event.startDate = self.startDate
        event.endDate = self.endDate
        
        // Find the calendar by identifier. Fallback to default or first if not found.
        if let calendar = eventStore.calendar(withIdentifier: self.calendarIdentifier) {
            event.calendar = calendar
        } else if let defaultCal = eventStore.defaultCalendarForNewEvents {
            event.calendar = defaultCal
            print("Warning: Original calendar not found for event \(event.title). Reverted to default calendar.")
        } else if let firstCal = eventStore.calendars(for: .event).first {
            event.calendar = firstCal
            print("Warning: Original calendar not found for event \(event.title). Reverted to first available calendar.")
        } else {
            print("Error: No calendar found to apply event snapshot for \(event.title).")
        }
    }
}

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
            // When calendar selection changes, refresh for today. RemindersTileView will then fetch for its selectedDate.
            if remindersAccessGranted { fetchReminders(for: Date()) } 
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
        if remindersAccessGranted { fetchReminders(for: Date()) } // Fetch for today
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
            fetchReminders(for: Date()) // Fetch for today
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
                    self?.fetchReminders(for: Date()) // Fetch for today
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

    // Fetches incomplete reminders for the targetDate, with special handling for "today" to include overdue.
    func fetchReminders(for targetDate: Date) {
        guard remindersAccessGranted else {
            reminders = []
            return
        }
        
        let calendar = Calendar.current
        let isToday = calendar.isDateInToday(targetDate)
        
        // Define a broad predicate range that covers any possible representation of 'targetDate'
        // and also includes all past reminders if it's "today".
        let predicateStartDate: Date? = nil // Start from the beginning of time
        
        // The predicate's ending date should be inclusive, so we need to fetch up to the end of the day *after* targetDate.
        // This ensures all-day reminders for targetDate are definitely captured.
        guard let endDateForPredicate = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: targetDate)) else {
            reminders = []
            print("Error: Could not calculate predicate end date.")
            return
        }
        
        // Filter calendars based on user selection
        let calendarsToFetch = allReminderCalendars.filter { selectedReminderCalendarIDs.contains($0.calendarIdentifier) }
        
        guard !calendarsToFetch.isEmpty else {
            reminders = []
            return
        }
        
        // Use a broad predicate to fetch all incomplete reminders up to the day AFTER the target date.
        // The precise filtering will happen in Swift.
        let predicateForIncomplete = eventStore.predicateForIncompleteReminders(withDueDateStarting: predicateStartDate, ending: endDateForPredicate, calendars: calendarsToFetch)

        eventStore.fetchReminders(matching: predicateForIncomplete) { [weak self] fetchedReminders in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Determine the end of the target day for filtering.
                guard let startOfNextDayAfterTarget = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: targetDate)) else {
                    self.reminders = []
                    print("Error: Could not calculate start of next day after target date for filtering.")
                    return
                }

                let filteredAndSortedReminders = fetchedReminders?
                    .filter { reminder in
                        // Filter out reminders that are already marked as pending
                        guard !self.pendingCompletedReminders.contains(reminder.calendarItemIdentifier) else { return false }
                        
                        // Ensure it's not already completed in the store
                        guard !reminder.isCompleted else { return false }
                        
                        // Get the due date from components. If no components, or no date can be formed, filter it out.
                        guard let dueDateComponents = reminder.dueDateComponents,
                              let reminderDueDate = calendar.date(from: dueDateComponents) else {
                            // If a reminder has no due date components, it should not be shown in this dated view.
                            return false 
                        }

                        // Apply final filter based on whether it's today's view
                        if isToday {
                            // For today's view, include reminders due today OR any date in the past (overdue)
                            // This means any reminder whose due date is *before* the start of the next day (tomorrow).
                            return reminderDueDate < startOfNextDayAfterTarget
                        } else {
                            // For any other day, strictly include only reminders due on that specific day.
                            // `isDate(_:inSameDayAs:)` is robust for all-day and time-specific events.
                            return calendar.isDate(reminderDueDate, inSameDayAs: targetDate)
                        }
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

    // Overloaded function for compatibility with existing calls, fetching for "today"
    func fetchReminders() {
        fetchReminders(for: Date())
    }

    // Fetches calendar events for today (maintains compatibility with existing calls)
    func fetchEvents() {
        fetchEvents(for: Date())
    }

    // Fetches calendar events for a specific date
    func fetchEvents(for date: Date) {
        guard eventsAccessGranted else {
            events = []
            return
        }

        let calendar = Calendar.current
        
        // Use the start of the provided day and the start of the next day for a robust 24-hour range
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
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

        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: calendarsToFetch)

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
                // Assuming this happens for "today" context, or needs a refresh for the currently selected date.
                // Call the parameter-less version, which defaults to today.
                self.fetchReminders(for: Date())
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
                self.fetchReminders(for: Date()) // Assuming redo also implies "today"
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
                        self.fetchReminders(for: Date()) // Reload the list to show the reminder again for today
                    } catch {
                        print("Error reverting temporary reminder completion: \(error.localizedDescription)")
                    }
                } else {
                    // If it was already false, just fetch to update the UI
                    self.fetchReminders(for: Date())
                }
            } else {
                print("Error: Could not find reminder with identifier \(reminder.calendarItemIdentifier) to unmark.")
                self.fetchReminders(for: Date()) // Still try to refresh the UI
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
                self.fetchReminders(for: Date()) // Reload the list to reflect the final state for today
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
                        self.fetchReminders(for: Date()) // Show it again in the UI for today
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
            self.fetchReminders(for: Date()) // Update the list after saving (for today)
        }
    }
    
    // Deletes a reminder
    func deleteReminder(_ reminder: EKReminder) throws {
        guard remindersAccessGranted else {
            throw EventKitError.accessDenied
        }
        try eventStore.remove(reminder, commit: true)
        DispatchQueue.main.async {
            self.fetchReminders(for: Date()) // Update the list after deleting (for today)
        }
    }

    // MARK: - Event Management (NEW)
    
    // Reverts an event update to a previous snapshot state and registers redo
    func revertEventUpdate(event: EKEvent, to snapshot: EventSnapshot, with undoManager: UndoManager?) {
        guard eventsAccessGranted else { return }

        // Capture current state for the redo operation
        let currentStateSnapshot = EventSnapshot(event: event)

        undoManager?.registerUndo(withTarget: self) { managerTarget in
            // Redo: Apply the current state back
            // The event instance itself might be stale, so fetch the latest.
            if let latestEvent = self.eventStore.calendarItem(withIdentifier: event.calendarItemIdentifier) as? EKEvent {
                managerTarget.revertEventUpdate(event: latestEvent, to: currentStateSnapshot, with: undoManager)
            } else {
                print("Error: Could not find event \(event.title) for redo update. Snapshot ID: \(event.calendarItemIdentifier)")
            }
        }
        undoManager?.setActionName("Edit Event") // Set action name for redo (which is undoing this undo)

        // Apply the snapshot's state to the event and save
        snapshot.apply(to: event, eventStore: eventStore)
        do {
            try eventStore.save(event, span: .thisEvent, commit: true)
            DispatchQueue.main.async {
                // Fetch events for the date of the event, as its date might have changed.
                self.fetchEvents(for: snapshot.startDate)
                self.fetchEvents(for: currentStateSnapshot.startDate) // Also refresh the previous date
            }
        } catch {
            print("Error reverting event update: \(error.localizedDescription)")
        }
    }

    // Undoes the addition of a new event (deletes it)
    func undoAddEvent(event: EKEvent, with undoManager: UndoManager?) {
        guard eventsAccessGranted else { return }

        // Register redo action: re-add the event
        let eventSnapshot = EventSnapshot(event: event) // Snapshot contains the state to re-add
        undoManager?.registerUndo(withTarget: self) { managerTarget in
            managerTarget.redoAddEvent(eventSnapshot: eventSnapshot, with: undoManager)
        }
        undoManager?.setActionName("Add Event")

        do {
            try eventStore.remove(event, span: .thisEvent, commit: true)
            DispatchQueue.main.async {
                self.fetchEvents(for: event.startDate ?? Date())
            }
        } catch {
            print("Error undoing add event: \(error.localizedDescription)")
        }
    }
    
    // Redoes the addition of an event (adds it back)
    func redoAddEvent(eventSnapshot: EventSnapshot, with undoManager: UndoManager?) {
        guard eventsAccessGranted else { return }

        // Create a new EKEvent and apply the snapshot
        let newEvent = EKEvent(eventStore: eventStore)
        eventSnapshot.apply(to: newEvent, eventStore: eventStore)

        // Register undo action: remove the re-added event
        undoManager?.registerUndo(withTarget: self) { managerTarget in
            managerTarget.undoAddEvent(event: newEvent, with: undoManager)
        }
        undoManager?.setActionName("Add Event")

        do {
            try eventStore.save(newEvent, span: .thisEvent, commit: true)
            DispatchQueue.main.async {
                self.fetchEvents(for: newEvent.startDate ?? Date())
            }
        } catch {
            print("Error redoing add event: \(error.localizedDescription)")
        }
    }

    // Undoes the deletion of an event (re-adds it)
    func undoDeleteEvent(eventSnapshot: EventSnapshot, with undoManager: UndoManager?) {
        guard eventsAccessGranted else { return }

        // Register redo action: re-delete the event
        undoManager?.registerUndo(withTarget: self) { managerTarget in
            managerTarget.redoDeleteEvent(eventSnapshot: eventSnapshot, with: undoManager)
        }
        undoManager?.setActionName("Delete Event")

        // Recreate event from snapshot and save
        let newEvent = EKEvent(eventStore: eventStore)
        eventSnapshot.apply(to: newEvent, eventStore: eventStore)
        
        do {
            try eventStore.save(newEvent, span: .thisEvent, commit: true)
            DispatchQueue.main.async {
                self.fetchEvents(for: newEvent.startDate ?? Date())
            }
        } catch {
            print("Error undoing delete event: \(error.localizedDescription)")
        }
    }

    // Redoes the deletion of an event (deletes it again)
    func redoDeleteEvent(eventSnapshot: EventSnapshot, with undoManager: UndoManager?) {
        guard eventsAccessGranted else { return }

        // Register undo action: re-add the event
        undoManager?.registerUndo(withTarget: self) { managerTarget in
            managerTarget.undoDeleteEvent(eventSnapshot: eventSnapshot, with: undoManager)
        }
        undoManager?.setActionName("Delete Event")

        // Find the event by identifier if possible.
        if let eventToDelete = eventStore.calendarItem(withIdentifier: eventSnapshot.identifier) as? EKEvent {
            do {
                try eventStore.remove(eventToDelete, span: .thisEvent, commit: true)
                DispatchQueue.main.async {
                    self.fetchEvents(for: eventToDelete.startDate ?? Date())
                }
            } catch {
                print("Error redoing delete event: \(error.localizedDescription)")
            }
        } else {
            print("Error: Could not find event with identifier \(eventSnapshot.identifier) to redo deletion. It might have been deleted externally.")
            // If the event isn't found, it's likely already gone from the store. Just refresh the view.
            DispatchQueue.main.async { self.fetchEvents(for: eventSnapshot.startDate) }
        }
    }

    // Saves a new or updated event, now accepting an UndoManager
    func saveEvent(_ event: EKEvent, in calendar: EKCalendar, with undoManager: UndoManager?) throws {
        guard eventsAccessGranted else {
            throw EventKitError.accessDenied
        }

        // Ensure the event is associated with the correct calendar
        if event.calendar != calendar {
            event.calendar = calendar
        }
        
        // --- UNDO REGISTRATION ---
        if event.calendarItemIdentifier.isEmpty { // It's a new event (identifier is empty before first save)
            // Register undo to delete this new event
            undoManager?.registerUndo(withTarget: self) { managerTarget in
                managerTarget.undoAddEvent(event: event, with: undoManager) // Pass the event just added
            }
            undoManager?.setActionName("Add Event")
        } else { // It's an existing event being updated
            // Capture the current state *before* modifications are saved
            let originalSnapshot = EventSnapshot(event: event)
            undoManager?.registerUndo(withTarget: self) { managerTarget in
                managerTarget.revertEventUpdate(event: event, to: originalSnapshot, with: undoManager)
            }
            undoManager?.setActionName("Edit Event")
        }
        // --- END UNDO REGISTRATION ---

        try eventStore.save(event, span: .thisEvent, commit: true)

        DispatchQueue.main.async {
            self.fetchEvents(for: event.startDate ?? Date())
        }
    }

    // Deletes an event, now accepting an UndoManager
    func deleteEvent(_ event: EKEvent, with undoManager: UndoManager?) throws {
        guard eventsAccessGranted else {
            throw EventKitError.accessDenied
        }

        // --- UNDO REGISTRATION ---
        // Capture the event's state *before* deletion
        let eventSnapshot = EventSnapshot(event: event)
        undoManager?.registerUndo(withTarget: self) { managerTarget in
            managerTarget.undoDeleteEvent(eventSnapshot: eventSnapshot, with: undoManager)
        }
        undoManager?.setActionName("Delete Event")
        // --- END UNDO REGISTRATION ---

        try eventStore.remove(event, span: .thisEvent, commit: true)

        DispatchQueue.main.async {
            self.fetchEvents(for: event.startDate ?? Date())
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

