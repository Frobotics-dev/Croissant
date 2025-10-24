//
//  ReminderEditView.swift
//  Dashboard
//
//  Created by Frederik Mondel on 15.10.25.
//

import SwiftUI
import EventKit

// Enum for managing reminder priorities in a user-friendly way
private enum ReminderPriority: Int, CaseIterable, Identifiable {
    case none = 0
    case low = 9
    case medium = 5
    case high = 1

    var id: Int { self.rawValue }

    var description: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}


struct ReminderEditView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var eventKitManager: EventKitManager

    // Consistent trailing control width for right column
    private let trailingControlWidth: CGFloat = 220

    // MARK: - State Variables
    @State private var reminderTitle: String
    @State private var reminderNotes: String
    
    @State private var hasDate: Bool
    @State private var hasTime: Bool
    @State private var dueDate: Date
    
    @State private var reminderPriority: ReminderPriority
    
    @State private var selectedCalendar: EKCalendar?
    
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    var reminderToEdit: EKReminder?
    
    // MARK: - Initializer
    init(eventKitManager: EventKitManager, reminderToEdit: EKReminder? = nil) {
        self._eventKitManager = ObservedObject(wrappedValue: eventKitManager)
        self.reminderToEdit = reminderToEdit

        // Basic Info
        _reminderTitle = State(initialValue: reminderToEdit?.title ?? "")
        _reminderNotes = State(initialValue: reminderToEdit?.notes ?? "")
        
        // Date and Time
        _hasDate = State(initialValue: reminderToEdit?.dueDateComponents != nil)
        _hasTime = State(initialValue: reminderToEdit?.dueDateComponents?.hour != nil)
        _dueDate = State(initialValue: reminderToEdit?.dueDateComponents?.date ?? Date())
        
        // Organization
        _reminderPriority = State(initialValue: ReminderPriority(rawValue: reminderToEdit?.priority ?? 0) ?? .none)
        _selectedCalendar = State(initialValue: reminderToEdit?.calendar ?? eventKitManager.allReminderCalendars.first)
    }

    // Computed property for the window title
    private var viewTitle: String {
        reminderToEdit == nil ? "New Reminder" : "Details"
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
                    // Section 1: Title, Notes
                    detailsSection
                    
                    // Section 2: Date & Time
                    dateTimeSection
                    
                    // Section 3: Recurrence, Alarms (API Limitations)
                    // Not implemented due to EventKit API limitations not perfectly matching the Reminders app UI.
                    // For example, EKRecurrenceRule is complex, and "Tags" or "Flagged" are not publicly available.
                    
                    // Section 4: Organization
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
        .alert("Delete Reminder?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive, action: deleteReminder)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Do you really want to permanently delete this reminder?")
        }
        .onAppear(perform: setupInitialCalendar)
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            reloadReminderFromStore()
        }
        .environment(\.locale, Locale(identifier: "en_US"))
    }

    // MARK: - Subviews
    private var headerView: some View {
        HStack {
            Text(viewTitle)
                .font(.headline)
                .foregroundColor(.secondary)
            Spacer()
            if reminderToEdit != nil {
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
            TextField("Title", text: $reminderTitle)
                .textFieldStyle(.plain)
                .font(.system(.body, weight: .semibold))
                .padding(10)

            Divider()

            // Notes TextField
            TextField("Notes", text: $reminderNotes, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(5)
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
                // Date Row (compact, single line)
                HStack {
                    Label("Date", systemImage: "calendar")
                    Spacer()
                    HStack(spacing: 8) {
                        if hasDate {
                            DatePicker("Due Date", selection: $dueDate, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.field)
                                .frame(width: 160)
                        }
                        Toggle("Date", isOn: $hasDate)
                            .labelsHidden()
                            .onChange(of: hasDate) { _, newValue in
                                if !newValue { hasTime = false }
                            }
                    }
                    .frame(width: trailingControlWidth, alignment: .trailing)
                }
                .padding(.horizontal, 10)
                .frame(height: 44)

                Divider().padding(.leading, 45)

                // Time Row (compact, single line)
                HStack {
                    Label("Time", systemImage: "clock")
                    Spacer()
                    HStack(spacing: 8) {
                        DatePicker("Time", selection: $dueDate, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.field)
                            .frame(width: 120)
                            .disabled(!(hasDate && hasTime))
                        Toggle("Time", isOn: $hasTime)
                            .labelsHidden()
                            .disabled(!hasDate)
                            .onChange(of: hasTime) { _, newValue in
                                if newValue { hasDate = true }
                            }
                    }
                    .frame(width: trailingControlWidth, alignment: .trailing)
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
                // List (Calendar) Picker Row
                HStack {
                    Label("List", systemImage: "list.bullet")
                        .padding(.leading, 10)
                    Spacer()
                    HStack {
                        Picker("List", selection: $selectedCalendar) {
                            ForEach(eventKitManager.allReminderCalendars, id: \.self) { calendar in
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

                Divider().padding(.leading, 45)

                // Priority Picker Row
                EditRow(icon: "exclamationmark.3", title: "Priority", width: trailingControlWidth) {
                    Picker("Priority", selection: $reminderPriority) {
                        ForEach(ReminderPriority.allCases) { priority in
                            Text(priority.description).tag(priority)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 200, alignment: .trailing)
                }
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
            
            Button(reminderToEdit == nil ? "Add" : "Done") {
                saveReminder()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Helper Functions
    
    private func reloadReminderFromStore() {
        guard let id = reminderToEdit?.calendarItemIdentifier else { return }
        if let item = eventKitManager.eventStore.calendarItem(withIdentifier: id) as? EKReminder {
            // Update fields from the latest store state
            reminderTitle = item.title
            reminderNotes = item.notes ?? ""

            if let comps = item.dueDateComponents, let date = comps.date {
                hasDate = true
                hasTime = comps.hour != nil
                dueDate = date
            } else {
                hasDate = false
                hasTime = false
            }
            reminderPriority = ReminderPriority(rawValue: item.priority) ?? .none
            selectedCalendar = item.calendar
        }
    }

    private func setupInitialCalendar() {
        if eventKitManager.allReminderCalendars.isEmpty {
            eventKitManager.fetchAvailableCalendars()
        }
        if selectedCalendar == nil, let firstCalendar = eventKitManager.allReminderCalendars.first {
            selectedCalendar = firstCalendar
        }
    }

    private func saveReminder() {
        guard let targetCalendar = selectedCalendar else {
            errorMessage = "Please select a list for the reminder."
            return
        }
        
        guard !reminderTitle.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Title must not be empty."
            return
        }
        
        do {
            let reminder = reminderToEdit ?? EKReminder(eventStore: eventKitManager.eventStore)
            
            reminder.title = reminderTitle
            reminder.notes = reminderNotes.isEmpty ? nil : reminderNotes
            reminder.priority = reminderPriority.rawValue
            reminder.calendar = targetCalendar

            if hasDate {
                let components: Set<Calendar.Component> = hasTime ?
                    [.year, .month, .day, .hour, .minute] :
                    [.year, .month, .day]
                reminder.dueDateComponents = Calendar.current.dateComponents(components, from: dueDate)
            } else {
                reminder.dueDateComponents = nil
            }
            
            try eventKitManager.saveReminder(reminder, in: targetCalendar)
            dismiss()
        } catch {
            errorMessage = "Save failed: \(error.localizedDescription)"
        }
    }
    
    private func deleteReminder() {
        guard let reminder = reminderToEdit else { return }
        do {
            try eventKitManager.deleteReminder(reminder)
            dismiss()
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }
    }
}


// A reusable view for a standard settings row (Icon, Title, Accessory Control)
private struct EditRow<Accessory: View>: View {
    let icon: String
    let title: String
    let width: CGFloat?
    let accessory: () -> Accessory

    init(icon: String, title: String, width: CGFloat? = nil, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.icon = icon
        self.title = title
        self.width = width
        self.accessory = accessory
    }

    var body: some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            if let width {
                HStack { accessory() }
                    .frame(width: width, alignment: .trailing)
            } else {
                accessory()
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
    }
}
