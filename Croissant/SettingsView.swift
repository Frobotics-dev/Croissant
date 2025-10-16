import SwiftUI
import EventKit 
import AppKit 

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    
    @ObservedObject var eventKitManager: EventKitManager
    @ObservedObject var newsFeedViewModel: NewsFeedViewModel

    // AppStorage is read/written by ContentView, we track the final, filtered list here
    @AppStorage("tileOrder") private var storedTileOrderString: String = ""

    // Use base TileType (defined in ContentView)
    @State private var activeTiles: Set<TileType>

    // Use base TileType (defined in ContentView)
    @State private var displayedTileOrder: [TileType]
    
    init(eventKitManager: EventKitManager, newsFeedViewModel: NewsFeedViewModel) {
        self._eventKitManager = ObservedObject(wrappedValue: eventKitManager)
        self._newsFeedViewModel = ObservedObject(wrappedValue: newsFeedViewModel)
        
        let initialOrder: [TileType] = {
            let parsed = (UserDefaults.standard.string(forKey: "tileOrder") ?? "")
                            .split(separator: ",")
                            .compactMap { TileType(rawValue: String($0)) }
            // If the stored string is empty (first launch or reset), use all cases as default order
            // Note: TileType is defined in ContentView.swift
            return parsed.isEmpty ? TileType.allCases : parsed
        }()
        
        // Ensure activeTiles reflects all known tiles if the stored string contained an old subset
        let storedActiveTiles = Set(initialOrder)
        // Merge stored tiles with any new TileTypes that might have appeared in TileType.allCases
        self._activeTiles = State(initialValue: storedActiveTiles)
        
        // The displayed order should only contain the tiles that are currently active
        self._displayedTileOrder = State(initialValue: initialOrder.filter { storedActiveTiles.contains($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Dashboard Settings")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // MARK: - Tile Selection
                    Section(header: Text("Active Tiles").font(.title2).padding(.bottom, 5)) {
                        
                        VStack(alignment: .leading, spacing: 10) {
                            // Use TileType.allCases
                            ForEach(TileType.allCases, id: \.self) { tileType in
                                Toggle(tileType.rawValue.capitalized, isOn: Binding(
                                    get: { self.activeTiles.contains(tileType) },
                                    set: { isEnabled in
                                        if isEnabled {
                                            self.activeTiles.insert(tileType)
                                            // Add to the end of the display order only if it's not already present
                                            if !self.displayedTileOrder.contains(tileType) {
                                                self.displayedTileOrder.append(tileType)
                                            }
                                        } else {
                                            self.activeTiles.remove(tileType)
                                            // Remove from the display order
                                            self.displayedTileOrder.removeAll { $0 == tileType }
                                        }
                                    }
                                ))
                            }
                        }
                        .padding(.horizontal)
                    }
                    
                    Divider()

                    // MARK: - Tile Order Adjustment
                    Section(header: Text("Tile Order (Drag & Drop)").font(.title2).padding(.bottom, 5)) {
                        
                        Text("Drag active tiles to change their display order.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        List {
                            ForEach(displayedTileOrder, id: \.self) { tileType in
                                HStack {
                                    Image(systemName: "line.horizontal.3")
                                        .foregroundColor(.secondary)
                                    Text(tileType.rawValue.capitalized)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(.vertical, 5)
                                .contentShape(Rectangle())
                                .onDrag {
                                    // Use the raw value (String) as the transferable data
                                    return NSItemProvider(object: tileType.rawValue as NSString)
                                }
                            }
                            // Allows reordering (move closure)
                            .onMove { indices, newOffset in
                                displayedTileOrder.move(fromOffsets: indices, toOffset: newOffset)
                            }
                        }
                        // Dynamic height adjustment for List
                        .frame(height: CGFloat(displayedTileOrder.count) * 35 + 10)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                    Divider()
                    
                    // MARK: - Event Kit Configuration (Calendar Selection)
                    
                    Group {
                        Text("Calendar Settings").font(.title2).padding(.bottom, 5)
                        Text("Select which calendars to display events from:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 5)
                        
                        if eventKitManager.eventsAccessGranted {
                            
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
                            // Fixed height for scrolling list
                            .frame(height: min(200, CGFloat(eventKitManager.allEventCalendars.count) * 35 + 10))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        } else {
                            Text("Calendar access required to configure.")
                                .foregroundColor(.orange)
                        }
                    }

                    // MARK: - Reminder Kit Configuration (Reminder Selection)
                    Group {
                        Text("Reminder Settings").font(.title2).padding(.bottom, 5)
                        Text("Select which reminder lists to display reminders from:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 5)

                        if eventKitManager.remindersAccessGranted {
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
                            .frame(height: min(200, CGFloat(eventKitManager.allReminderCalendars.count) * 35 + 10))
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        } else {
                            Text("Reminder access required to configure.")
                                .foregroundColor(.orange)
                        }
                    }
                    
                    Divider()

                    // MARK: - News Feed Configuration
                    Group {
                        Text("News Feed Settings").font(.title2).padding(.bottom, 5)

                        Picker("Select RSS Feed", selection: $newsFeedViewModel.feedURLString) {
                            ForEach(newsFeedViewModel.availableFeedsForMenu, id: \.value) { displayName, urlString in
                                Text(displayName)
                                    .tag(urlString)
                            }
                        }
                    }
                    .padding(.bottom)
                }
                .padding()
            }
            
            // Footer: Apply changes and Close Button
            HStack {
                Spacer()
                
                Button("Close") {
                    // 1. Persist the final order of tiles that are currently active
                    let finalOrderString = self.displayedTileOrder
                        .filter { activeTiles.contains($0) } // Only include tiles that are checked
                        .map(\.rawValue)
                        .joined(separator: ",")
                    
                    self.storedTileOrderString = finalOrderString
                    
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding([.horizontal, .bottom])
            
        }
        .frame(minWidth: 480, minHeight: 580)
    }
}
