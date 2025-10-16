//
//  ReminderEditView.swift
//  Dashboard
//
//  Created by Frederik Mondel on 15.10.25.
//

import SwiftUI
import EventKit

struct ReminderEditView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var eventKitManager: EventKitManager

    @State private var reminderTitle: String
    @State private var reminderNotes: String
    @State private var reminderDueDate: Date?
    @State private var isDueDateEnabled: Bool
    @State private var selectedCalendar: EKCalendar?
    
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    // Binding, um zu wissen, ob wir eine neue Erinnerung erstellen oder eine bestehende bearbeiten
    var reminderToEdit: EKReminder?

    init(eventKitManager: EventKitManager, reminderToEdit: EKReminder? = nil) {
        self._eventKitManager = ObservedObject(wrappedValue: eventKitManager)
        self.reminderToEdit = reminderToEdit

        _reminderTitle = State(initialValue: reminderToEdit?.title ?? "")
        _reminderNotes = State(initialValue: reminderToEdit?.notes ?? "")
        _reminderDueDate = State(initialValue: reminderToEdit?.dueDateComponents?.date)
        _isDueDateEnabled = State(initialValue: reminderToEdit?.dueDateComponents?.date != nil)
        
        // Initialisiere selectedCalendar. Wenn bearbeiten, den Kalender der Erinnerung verwenden.
        // Sonst den ersten verfügbaren Erinnerungskalender.
        _selectedCalendar = State(initialValue: reminderToEdit?.calendar ?? eventKitManager.allReminderCalendars.first)
    }

    var body: some View {
        VStack(spacing: 20) {
            Text(reminderToEdit == nil ? "Neue Erinnerung" : "Erinnerung bearbeiten")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Divider()
            
            Form {
                Section("Details") {
                    TextField("Titel", text: $reminderTitle)
                    TextField("Notizen (optional)", text: $reminderNotes)
                }
                
                Section("Fälligkeitsdatum") {
                    Toggle("Fälligkeitsdatum aktivieren", isOn: $isDueDateEnabled)
                    if isDueDateEnabled {
                        DatePicker("Datum", selection: Binding(get: {
                            reminderDueDate ?? Date() // Standardwert, wenn nil
                        }, set: { newDate in
                            reminderDueDate = newDate
                        }), displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.graphical)
                        .padding(.horizontal, -20) // Kleiner Hack für macOS, um den DatePicker besser auszurichten
                    }
                }
                
                Section("Kalender") {
                    Picker("Kalender auswählen", selection: $selectedCalendar) {
                        ForEach(eventKitManager.allReminderCalendars, id: \.calendarIdentifier) { calendar in
                            Text(calendar.title)
                                .tag(calendar as EKCalendar?) // Verwende optionalen EKCalendar als Tag
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                if let errorMessage = errorMessage {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            
            Divider()
            
            HStack {
                if reminderToEdit != nil {
                    Button("Löschen", role: .destructive) { // Changed .buttonStyle(.destructive) to role: .destructive
                        showingDeleteConfirmation = true
                    }
                }
                
                Spacer()
                
                Button("Abbrechen") {
                    dismiss()
                }
                
                Button("Speichern") {
                    saveReminder()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction) // Speichern mit Enter
            }
            .padding(.bottom, 10)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 600) // Angepasste Mindestgröße für Bearbeitung
        .alert("Erinnerung löschen?", isPresented: $showingDeleteConfirmation) {
            Button("Löschen", role: .destructive) {
                deleteReminder()
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Möchten Sie diese Erinnerung wirklich unwiderruflich löschen?")
        }
        .onAppear {
            if eventKitManager.allReminderCalendars.isEmpty {
                eventKitManager.fetchAvailableCalendars() // Sicherstellen, dass Kalender geladen sind
            }
            // Wenn der ausgewählte Kalender nicht mehr existiert oder keiner ausgewählt ist, den ersten nehmen
            if selectedCalendar == nil, let firstCalendar = eventKitManager.allReminderCalendars.first {
                selectedCalendar = firstCalendar
            }
        }
    }

    private func saveReminder() {
        guard let targetCalendar = selectedCalendar else {
            errorMessage = "Bitte wählen Sie einen Kalender für die Erinnerung aus."
            return
        }
        
        do {
            let reminder: EKReminder
            if let existingReminder = reminderToEdit {
                reminder = existingReminder
            } else {
                reminder = EKReminder(eventStore: eventKitManager.eventStore)
            }
            
            reminder.title = reminderTitle
            reminder.notes = reminderNotes.isEmpty ? nil : reminderNotes

            if isDueDateEnabled, let dueDate = reminderDueDate {
                // Erstelle Datumskomponenten ohne Zeitzone für Fälligkeitsdatum
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
                reminder.dueDateComponents = components
            } else {
                reminder.dueDateComponents = nil
            }
            
            try eventKitManager.saveReminder(reminder, in: targetCalendar)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            print("Fehler beim Speichern der Erinnerung: \(error.localizedDescription)")
        }
    }
    
    private func deleteReminder() {
        guard let reminder = reminderToEdit else { return }
        do {
            try eventKitManager.deleteReminder(reminder)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            print("Fehler beim Löschen der Erinnerung: \(error.localizedDescription)")
        }
    }
}
