import SwiftUI
import EventKit
import AppKit
import CoreLocation // Needed for CLAuthorizationStatus

// Enum to define the different tabs for clean navigation
private enum SettingsTab: Hashable {
    case general
    case appearance
    case calendars
    case news
    // Removed .transit tab
    case debugging
    case about
}

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @State private var selectedTab: SettingsTab = .general
    
    // Dependencies that are passed to the sub-views
    @ObservedObject var eventKitManager: EventKitManager
    @ObservedObject var newsFeedViewModel: NewsFeedViewModel
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var transitViewModel: TransitViewModel
    
    // AppStorage for tile order
    @AppStorage("tileOrder") private var storedTileOrderString: String = ""

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 1: General Settings
            GeneralSettingsView(storedTileOrderString: $storedTileOrderString)
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(SettingsTab.general)

            // Tab 2: Appearance Settings
            AppearanceSettingsView()
                .tabItem {
                    Label("Appearance", systemImage: "paintbrush")
                }
                .tag(SettingsTab.appearance)
            
            // Tab 3: Calendars & Reminders
            CalendarsAndRemindersSettingsView(eventKitManager: eventKitManager)
                .tabItem {
                    Label("Calendars & Reminders", systemImage: "calendar")
                }
                .tag(SettingsTab.calendars)

            // Tab 4: News Feed
            NewsSettingsView(newsFeedViewModel: newsFeedViewModel)
                .tabItem {
                    Label("News", systemImage: "newspaper")
                }
                .tag(SettingsTab.news)
            
            // Removed TransitSettingsView tab item
            
            // Tab 5: Debugging (now includes Transit Search Radius and Location)
            DebuggingSettingsView(transitViewModel: transitViewModel, locationManager: locationManager) // Pass locationManager here
                .tabItem {
                    Label("Debugging", systemImage: "ladybug")
                }
                .tag(SettingsTab.debugging)

            // Tab 6: About
            AboutSettingsView()
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
                .tag(SettingsTab.about)
        }
        .tabViewStyle(.sidebarAdaptable) // Enables the macOS-style sidebar layout
        .frame(minWidth: 660, idealWidth: 660, maxWidth: 660,
               minHeight: 520, idealHeight: 520, maxHeight: 520)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Save") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .onAppear {
            if let win = NSApp.keyWindow {
                win.identifier = NSUserInterfaceItemIdentifier("settingsWindow")
            }
        }
    }
}

// MARK: - Sub-view for General Settings
private struct GeneralSettingsView: View {
    @Binding var storedTileOrderString: String
    
    @State private var activeTiles: Set<TileType>
    @State private var displayedTileOrder: [TileType]
    
    init(storedTileOrderString: Binding<String>) {
        self._storedTileOrderString = storedTileOrderString
        
        let initialOrder: [TileType] = {
            let parsed = (storedTileOrderString.wrappedValue)
                            .split(separator: ",")
                            .compactMap { TileType(rawValue: String($0)) }
            return parsed.isEmpty ? TileType.allCases : parsed
        }()
        
        self._activeTiles = State(initialValue: Set(initialOrder))
        self._displayedTileOrder = State(initialValue: initialOrder)
    }

    var body: some View {
        Form {
            Section(header: Text("Active Tiles").font(.title2)) {
                ForEach(TileType.allCases, id: \.self) { tileType in
                    Toggle(tileType.rawValue.capitalized, isOn: Binding(
                        get: { self.activeTiles.contains(tileType) },
                        set: { isEnabled in
                            if isEnabled {
                                self.activeTiles.insert(tileType)
                                if !self.displayedTileOrder.contains(tileType) {
                                    self.displayedTileOrder.append(tileType)
                                }
                            } else {
                                self.activeTiles.remove(tileType)
                                self.displayedTileOrder.removeAll { $0 == tileType }
                            }
                        }
                    ))
                }
            }
            
            Section(header: Text("Tile Order (Drag & Drop)").font(.title2)) {
                Text("Drag the tiles to change their display order.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                List {
                    ForEach(displayedTileOrder, id: \.self) { tileType in
                        HStack {
                            Image(systemName: "line.horizontal.3")
                                .foregroundColor(.secondary)
                            Text(tileType.rawValue.capitalized)
                        }
                    }
                    .onMove { indices, newOffset in
                        displayedTileOrder.move(fromOffsets: indices, toOffset: newOffset)
                    }
                }
                .frame(minHeight: CGFloat(displayedTileOrder.count) * 28)
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .onDisappear {
            // Save changes when the view disappears
            let finalOrderString = self.displayedTileOrder
                .filter { activeTiles.contains($0) }
                .map(\.rawValue)
                .joined(separator: ",")
            self.storedTileOrderString = finalOrderString
        }
    }
}

// MARK: - Sub-view for Appearance
private struct AppearanceSettingsView: View {
    @AppStorage("enableTileHoverEffect") private var enableTileHoverEffect: Bool = true
    @AppStorage("tileScrollDirectionVertical") private var tileScrollDirectionVertical: Bool = false // NEU: Einstellung für Scrollrichtung
    @AppStorage("useTranslucentBackground") private var useTranslucentBackground: Bool = true // Fensterhintergrund: transluzent vs. opak

    var body: some View {
        Form {
            Section(header: Text("Tile Behavior").font(.title2)) {
                Toggle("Enable tile hover effect", isOn: $enableTileHoverEffect)
                Text("Enables the scaling and shadow effect when hovering over a tile with the mouse.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section(header: Text("Tile Layout").font(.title2)) { // NEU: Abschnitt für Layout-Einstellungen
                Toggle("Scroll tiles vertically", isOn: $tileScrollDirectionVertical)
                Text("When enabled, tiles will scroll vertically in multiple columns. Otherwise, they scroll horizontally.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section(header: Text("Window Background").font(.title2)) {
                Toggle("Transparent background (translucent)", isOn: $useTranslucentBackground)
                Text("When enabled, the app uses a translucent material for the window background. When disabled, a standard opaque window background is used.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - Sub-view for Calendars & Reminders
private struct CalendarsAndRemindersSettingsView: View {
    @ObservedObject var eventKitManager: EventKitManager

    var body: some View {
        Form {
            Section(header: Text("Calendars").font(.title2)) {
                if eventKitManager.eventsAccessGranted {
                    Text("Select which calendars to display events from:")
                        .foregroundColor(.secondary)
                    List {
                        ForEach(eventKitManager.allEventCalendars, id: \.calendarIdentifier) { calendar in
                            Toggle(calendar.title, isOn: Binding(
                                get: { eventKitManager.selectedEventCalendarIDs.contains(calendar.calendarIdentifier) },
                                set: { isEnabled in
                                    if isEnabled {
                                        eventKitManager.selectedEventCalendarIDs.insert(calendar.calendarIdentifier)
                                    } else {
                                        eventKitManager.selectedEventCalendarIDs.remove(calendar.calendarIdentifier)
                                    }
                                }
                            ))
                        }
                    }
                    .frame(minHeight: 100)
                } else {
                    Text("Access to calendars has been denied. Please enable it in System Settings.")
                        .foregroundColor(.orange)
                }
            }
            Section(header: Text("Reminders").font(.title2)) {
                if eventKitManager.remindersAccessGranted {
                    Text("Select which reminder lists to display reminders from:")
                         .foregroundColor(.secondary)
                    List {
                        ForEach(eventKitManager.allReminderCalendars, id: \.calendarIdentifier) { calendar in
                            Toggle(calendar.title, isOn: Binding(
                                get: { eventKitManager.selectedReminderCalendarIDs.contains(calendar.calendarIdentifier) },
                                set: { isEnabled in
                                    if isEnabled {
                                        eventKitManager.selectedReminderCalendarIDs.insert(calendar.calendarIdentifier)
                                    } else {
                                        eventKitManager.selectedReminderCalendarIDs.remove(calendar.calendarIdentifier)
                                    }
                                }
                            ))
                        }
                    }
                    .frame(minHeight: 100)
                } else {
                    Text("Access to reminders has been denied. Please enable it in System Settings.")
                        .foregroundColor(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - Sub-view for News
private struct NewsSettingsView: View {
    @ObservedObject var newsFeedViewModel: NewsFeedViewModel
    @AppStorage("enableNewsScrollEffect") private var enableNewsScrollEffect: Bool = true
    
    var body: some View {
        Form {
            Section(header: Text("News Feed").font(.title2)) {
                Picker("Select RSS Feed", selection: $newsFeedViewModel.feedURLString) {
                    ForEach(newsFeedViewModel.availableFeedsForMenu, id: \.value) { displayName, urlString in
                        Text(displayName)
                            .tag(urlString)
                    }
                }
                
                if newsFeedViewModel.feedURLString == "custom" {
                    TextField("Enter custom RSS feed URL", text: $newsFeedViewModel.customFeedURLString)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            Section(header: Text("Behavior").font(.title2)) {
                Toggle("Scroll to headline on open", isOn: $enableNewsScrollEffect)
                Text("When a news headline is clicked to show the description, the view will automatically scroll to bring the headline to the top.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// Removed TransitSettingsView entirely, its contents moved to DebuggingSettingsView

// MARK: - Sub-view for Debugging
private struct DebuggingSettingsView: View {
    @AppStorage("isDebuggingEnabled") private var isDebuggingEnabled: Bool = false
    @ObservedObject var transitViewModel: TransitViewModel // Injected to access searchRadiusMeters
    @ObservedObject var locationManager: LocationManager // Injected for location settings

    var body: some View {
        Form {
            Section(header: Text("Developer").font(.title2)) {
                Toggle("Enable Debugging Mode", isOn: $isDebuggingEnabled)
                Text("Shows additional information in the UI, such as API update timestamps in the transit tile.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Section(header: Text("Transit Debugging").font(.title2)) {
                VStack(alignment: .leading) {
                    Text("Stop Search Radius: \(Int(transitViewModel.searchRadiusMeters)) meters")
                        .font(.subheadline)
                    Slider(value: $transitViewModel.searchRadiusMeters, in: 500...5000, step: 100) {
                        Text("Search Radius")
                    } minimumValueLabel: {
                        Text("500m")
                    } maximumValueLabel: {
                        Text("5000m")
                    }
                    .padding(.top, 5)
                    
                    Text("Controls how far around your current location the app searches for public transport stops. This is a developer setting to test different search distances.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Section(header: Text("Location Access").font(.title2)) {
                Button("Request Location Access") {
                    locationManager.requestLocationAuthorization()
                }
                .disabled(locationManager.authorizationStatus == .authorizedAlways)
                
                Text("Current Status: \(locationManager.authorizationStatusString)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let error = locationManager.locationError {
                    Text("Location Error: \(error.localizedDescription)")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - Sub-view for About
private struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section(header: Text("About the App").font(.title2)) {
                Text("The news feed defaults to the German-speaking area. The RSS feed link can be customized in the settings. The public transit feature is currently only available in Germany. Data is provided by a third party using an API from Deutsche Bahn AG.")
                    .font(.callout)
                    .foregroundColor(.secondary)

                Link(destination: URL(string: "mailto:frobotics@freenet.de?subject=Feedback%20to%20your%20App%20%22Croissaint%22&body=Hi%20Frederik%2C")!) {
                    Label("Send Feedback", systemImage: "envelope.fill")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top)
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// Helper extension for authorization status string conversion for CoreLocation
extension CLAuthorizationStatus {
    var stringValue: String {
        switch self {
        case .authorizedAlways: return "Authorized Always"
        case .authorizedWhenInUse: return "Authorized When In Use"
        case .denied: return "Denied"
        case .notDetermined: return "Not Determined"
        case .restricted: return "Restricted"
        @unknown default: return "Unknown"
        }
    }
}

// Helper extension for authorization status string conversion for EventKit
extension EKAuthorizationStatus {
    var stringValue: String {
        switch self {
        case .notDetermined: return "Not Determined"
        case .restricted: return "Restricted"
        case .denied: return "Denied"
        case .authorized: return "Authorized"
        case .fullAccess: return "Full Access" // Handle new cases for macOS 14+, iOS 17+
        case .writeOnly: return "Write Only"   // Handle new cases for macOS 14+, iOS 17+
        @unknown default: return "Unknown"
        }
    }
}

extension EventKitManager {
    var eventsAuthorizationStatusString: String {
        EKEventStore.authorizationStatus(for: .event).stringValue
    }
    
    var remindersAuthorizationStatusString: String {
        EKEventStore.authorizationStatus(for: .reminder).stringValue
    }
}

extension LocationManager {
    var authorizationStatusString: String {
        authorizationStatus?.stringValue ?? "Not Determined"
    }
}
