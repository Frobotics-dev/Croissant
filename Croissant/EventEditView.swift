//
//  EventEditView.swift
//  Dashboard
//
//  Created by Frederik Mondel on 15.10.25.
//

import SwiftUI
import EventKit

struct EventEditView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var eventKitManager: EventKitManager
    @Environment(\.undoManager) var undoManager: UndoManager? // Inject UndoManager

    // Consistent trailing control width for right column
    private let trailingControlWidth: CGFloat = 220

    // MARK: - State Variables
    @State private var eventTitle: String
    @State private var eventNotes: String
    @State private var eventLocation: String
    
    @State private var isAllDay: Bool
    @State private var startDate: Date
    @State private var endDate: Date
    
    @State private var selectedCalendar: EKCalendar?
    
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    var eventToEdit: EKEvent?
    
    // MARK: - Initializer
    init(eventKitManager: EventKitManager, eventToEdit: EKEvent? = nil) {
        self._eventKitManager = ObservedObject(wrappedValue: eventKitManager)
        self.eventToEdit = eventToEdit

        // Basic Info
        _eventTitle = State(initialValue: eventToEdit?.title ?? "")
        _eventNotes = State(initialValue: eventToEdit?.notes ?? "")
        _eventLocation = State(initialValue: eventToEdit?.location ?? "")
        
        // Date and Time
        _isAllDay = State(initialValue: eventToEdit?.isAllDay ?? false)
        _startDate = State(initialValue: eventToEdit?.startDate ?? Date())
        _endDate = State(initialValue: eventToEdit?.endDate ?? Date().addingTimeInterval(3600)) // Default 1 hour duration
        
        // Organization
        // --- START MODIFICATION ---
        let initialCalendar: EKCalendar?
        if let existingCalendar = eventToEdit?.calendar {
            // If editing an existing event, use its calendar
            initialCalendar = existingCalendar
        } else {
            // For a new event, use the user's default calendar for new events
            // as configured in the Calendar app settings.
            // Fallback to the first available calendar if no default is set or accessible.
            initialCalendar = eventKitManager.eventStore.defaultCalendarForNewEvents ?? eventKitManager.allEventCalendars.first
        }
        _selectedCalendar = State(initialValue: initialCalendar)
        // --- END MODIFICATION ---
    }

    // Computed property for the window title
    private var viewTitle: String {
        eventToEdit == nil ? "New Event" : "Details"
    }

    // MARK: - Body
    var body: some View {
        // Main container with custom background
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Main content in a ScrollView
            ScrollView {
                VStack(spacing: 16) {
                    // Section 1: Title, Notes, Location
                    detailsSection
                    
                    // Section 2: Date & Time
                    dateTimeSection
                    
                    // Section 3: Organization
                    organizationSection
                    
                    if let errorMessage = errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .padding()
                    }
                }
                .padding()
            }
            
            // Footer with action buttons
            footerView
        }
        .background(Color(.windowBackgroundColor)) // Dark background similar to Reminders app
        .frame(minWidth: 380, idealWidth: 420, maxWidth: 500, minHeight: 450, idealHeight: 600)
        .alert("Delete Event?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive, action: deleteEvent)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Do you really want to permanently delete this event?")
        }
        .onAppear(perform: setupInitialCalendar)
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            reloadEventFromStore()
        }
        .environment(\.locale, Locale(identifier: "en_US"))
        // Watch for startDate changes to automatically adjust endDate if it's before startDate
        .onChange(of: startDate) { _, newStartDate in
            if newStartDate > endDate {
                endDate = newStartDate.addingTimeInterval(3600) // Default 1 hour duration
            }
        }
        // Watch for isAllDay changes
        .onChange(of: isAllDay) { _, newValue in
            // When switching to all-day, set start/end to start/end of the day
            if newValue {
                startDate = Calendar.current.startOfDay(for: startDate)
                endDate = Calendar.current.date(byAdding: .day, value: 1, to: startDate)!
                                            .addingTimeInterval(-1) // End of day
            } else {
                // When switching off all-day, set default times if currently at start/end of day
                let calendar = Calendar.current
                if calendar.isDate(startDate, inSameDayAs: endDate) && calendar.isDate(startDate, equalTo: calendar.startOfDay(for: startDate), toGranularity: .hour) {
                    // If it was an all-day event and now switching off, give it a default 9 AM - 10 AM time
                    var comps = calendar.dateComponents([.year, .month, .day], from: startDate)
                    comps.hour = 9
                    startDate = calendar.date(from: comps) ?? startDate
                    endDate = startDate.addingTimeInterval(3600)
                }
            }
        }
    }

    // MARK: - Subviews
    private var headerView: some View {
        HStack {
            Text(viewTitle)
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
            if eventToEdit != nil {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
            }
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var detailsSection: some View {
        VStack(spacing: 0) {
            // Title TextField
            TextField("Title", text: $eventTitle)
                .textFieldStyle(.plain)
                .font(.system(.body, weight: .semibold))
                .padding(10)

            Divider()

            // Notes TextField
            TextField("Notes", text: $eventNotes, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(5)
                .padding(10)

            Divider()

            // Location TextField
            TextField("Location", text: $eventLocation)
                .textFieldStyle(.plain)
                .padding(10)
        }
        .background(Material.regular, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var dateTimeSection: some View {
        VStack(spacing: 16) {
            // Section Header
            Text("Date & Time")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
            
            // Main content box
            VStack(spacing: 0) {
                // All-day Toggle
                HStack {
                    Label("All Day", systemImage: "clock.badge.fill")
                    Spacer()
                    Toggle("All Day", isOn: $isAllDay)
                        .labelsHidden()
                        .frame(width: trailingControlWidth, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .frame(height: 44)

                Divider().padding(.leading, 45)

                // Start Date/Time
                HStack {
                    Label("Starts", systemImage: "calendar.badge.clock")
                    Spacer()
                    DatePicker("Starts", selection: $startDate, displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .frame(width: isAllDay ? 160 : 200) // Adjust width for time component
                        .frame(width: trailingControlWidth, alignment: .trailing) // Adjust frame to match
                }
                .padding(.horizontal, 10)
                .frame(height: 44)

                Divider().padding(.leading, 45)

                // End Date/Time
                HStack {
                    Label("Ends", systemImage: "calendar.badge.clock")
                    Spacer()
                    DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                        .labelsHidden()
                        .datePickerStyle(.field)
                        .frame(width: isAllDay ? 160 : 200) // Adjust width for time component
                        .frame(width: trailingControlWidth, alignment: .trailing) // Adjust frame to match
                }
                .padding(.horizontal, 10)
                .frame(height: 44)
            }
            .background(Material.regular, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var organizationSection: some View {
        VStack(spacing: 16) {
            // Section Header
            Text("Organization")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 8)
                
            VStack(spacing: 0) {
                // Calendar Picker Row
                HStack {
                    Label("Calendar", systemImage: "calendar")
                        .padding(.leading, 10)
                    Spacer()
                    HStack {
                        Picker("Calendar", selection: $selectedCalendar) {
                            ForEach(eventKitManager.allEventCalendars, id: \.self) { calendar in
                                HStack {
                                    Circle()
                                        .fill(calendar.cgColor.map { Color(cgColor: $0) } ?? .gray)
                                        .frame(width: 8, height: 8)
                                    Text(calendar.title)
                                }
                                .tag(calendar as EKCalendar?)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    .frame(width: trailingControlWidth, alignment: .trailing)
                }
                .frame(height: 44)
            }
            .background(Material.regular, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    
    private var footerView: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            
            Button(eventToEdit == nil ? "Add" : "Done") {
                saveEvent()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Helper Functions
    
    private func reloadEventFromStore() {
        guard let id = eventToEdit?.calendarItemIdentifier else { return }
        if let item = eventKitManager.eventStore.calendarItem(withIdentifier: id) as? EKEvent {
            eventTitle = item.title
            eventNotes = item.notes ?? ""
            eventLocation = item.location ?? ""
            isAllDay = item.isAllDay
            startDate = item.startDate ?? Date()
            endDate = item.endDate ?? Date().addingTimeInterval(3600)
            selectedCalendar = item.calendar
        } else {
            // If the event was deleted externally, dismiss the sheet
            dismiss()
        }
    }

    private func setupInitialCalendar() {
        if eventKitManager.allEventCalendars.isEmpty {
            eventKitManager.fetchAvailableCalendars()
        }
        // This is primarily for cases where initialCalendar in init() might have been nil
        // due to no calendars being available at that exact moment (e.g., if EventKitManager hadn't fetched them yet).
        // If selectedCalendar is still nil here, attempt to set it to the default, or the first available.
        if selectedCalendar == nil {
            selectedCalendar = eventKitManager.eventStore.defaultCalendarForNewEvents ?? eventKitManager.allEventCalendars.first
        }
    }

    private func saveEvent() {
        guard let targetCalendar = selectedCalendar else {
            errorMessage = "Please select a calendar for the event."
            return
        }
        
        guard !eventTitle.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Title must not be empty."
            return
        }
        
        guard startDate <= endDate else {
            errorMessage = "End date must be after start date."
            return
        }
        
        do {
            let event = eventToEdit ?? EKEvent(eventStore: eventKitManager.eventStore)
            
            event.title = eventTitle
            event.notes = eventNotes.isEmpty ? nil : eventNotes
            event.location = eventLocation.isEmpty ? nil : eventLocation
            event.isAllDay = isAllDay
            event.startDate = startDate
            event.endDate = endDate
            // The calendar property is set inside saveEvent, but event.calendar needs to be set
            // so EventKitManager can correctly determine the original calendar for new events.
            event.calendar = targetCalendar 
            
            // Pass the undoManager to EventKitManager's saveEvent
            try eventKitManager.saveEvent(event, in: targetCalendar, with: undoManager)
            dismiss()
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }
    
    private func deleteEvent() {
        guard let event = eventToEdit else { return }
        do {
            // Pass the undoManager to EventKitManager's deleteEvent
            try eventKitManager.deleteEvent(event, with: undoManager)
            dismiss()
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }
}

