//
//  ContentView.swift
//  Dashboard
//
//  Created by Frederik Mondel on 15.10.25.
//

import SwiftUI
import EventKit
import UniformTypeIdentifiers // Import for UTType.text
import AppKit
import Combine

// MARK: - TileType Enum
// Definiert die verschiedenen Kacheltypen und ihre Darstellung.
enum TileType: String, CaseIterable, Identifiable, Equatable {
    case reminders
    case calendar
    case weather
    case news
    case systemInfo
    case transit // NEU: ÖPNV-Kachel

    var id: String { self.rawValue }

    @ViewBuilder
    // Alle Abhängigkeiten müssen hier als Parameter hinzugefügt werden
    func view(eventKitManager: EventKitManager, newsFeedViewModel: NewsFeedViewModel, locationManager: LocationManager, transitViewModel: TransitViewModel, systemInfoManager: SystemInfoManager) -> some View {
        switch self {
        case .reminders:
            RemindersTileView(manager: eventKitManager)
        case .calendar:
            CalendarTileView(manager: eventKitManager)
        case .weather:
            WeatherTileView()
        case .news:
            NewsTileView(viewModel: newsFeedViewModel)
        case .systemInfo:
            SystemInfoTileView(manager: systemInfoManager)
        case .transit:
            // NEU: Transit Kachel einfügen
            TransitTileView(viewModel: transitViewModel, locationManager: locationManager)
        }
    }
}

// MARK: - TileReorderDropDelegate
// Ein benutzerdefinierter DropDelegate, um die Kachelreihenfolge zu handhaben.
struct TileReorderDropDelegate: DropDelegate {
    @Binding var tileOrder: [TileType]
    @Binding var draggingTile: TileType?
    @Binding var dropTargetIndex: Int?

    let fixedTileWidth: CGFloat
    let fixedTileHeight: CGFloat
    let gridSpacing: CGFloat
    let numColumns: Int // Anzahl der Spalten im LazyVGrid
    let isVerticalScroll: Bool // NEU: Flag für vertikales Scrollen
    
    // Hilfsfunktion zur Berechnung des Index basierend auf der Drop-Position
    private func getIndex(for location: CGPoint) -> Int {
        let xInGridContent = location.x - gridSpacing
        let yInGridContent = location.y - gridSpacing

        guard xInGridContent >= 0, yInGridContent >= 0 else {
            return 0
        }

        let column = Int(floor(xInGridContent / (fixedTileWidth + gridSpacing)))
        let row = Int(floor(yInGridContent / (fixedTileHeight + gridSpacing)))
        
        var index: Int
        if isVerticalScroll {
            // Bei vertikalem Scrollen mit LazyVGrid: Index = row * numColumns + column
            index = row * numColumns + column
        } else {
            // Bei horizontalem Scrollen mit LazyHGrid: Index = column * numRows + row
            // Da wir LazyVGrid verwenden, aber horizontal scrollen lassen,
            // ist die Logik immer noch auf Spalten basierend.
            // Die Berechnung des Index bleibt gleich, da die Spalten die primäre Anordnung sind.
            index = row * numColumns + column
        }
        
        index = min(max(0, index), tileOrder.count)
        return index
    }

    func dropEntered(info: DropInfo) {
        guard let draggedRawValue = info.itemProviders(for: [.text]).first else { return }
        
        _ = draggedRawValue.loadObject(ofClass: NSString.self) { (item, error) in
            DispatchQueue.main.async {
                guard let draggedRawValueString = item as? String,
                      let draggedTileType = TileType(rawValue: draggedRawValueString) else { return }
                
                if self.draggingTile == nil || self.draggingTile != draggedTileType {
                    self.draggingTile = draggedTileType
                }
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let draggingTile = draggingTile else { return DropProposal(operation: .forbidden) }

        let calculatedIndex = getIndex(for: info.location)
        
        if let draggedOriginalIndex = tileOrder.firstIndex(of: draggingTile), calculatedIndex == draggedOriginalIndex {
            dropTargetIndex = nil
        } else {
            if calculatedIndex != dropTargetIndex {
                dropTargetIndex = calculatedIndex
            }
        }
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        dropTargetIndex = nil
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let itemProvider = info.itemProviders(for: [.text]).first else { return false }

        itemProvider.loadObject(ofClass: NSString.self) { (item, error) in
            DispatchQueue.main.async {
                guard let draggedRawValue = item as? String,
                      let draggedTileType = TileType(rawValue: draggedRawValue),
                      let sourceIndex = tileOrder.firstIndex(of: draggedTileType),
                      let targetIndex = self.dropTargetIndex else { return }

                if sourceIndex != targetIndex {
                    var newOrder = tileOrder
                    let movedTile = newOrder.remove(at: sourceIndex)
                    newOrder.insert(movedTile, at: targetIndex)
                    tileOrder = newOrder
                }
                
                self.draggingTile = nil
                self.dropTargetIndex = nil
            }
        }
        return true
    }
}


struct ContentView: View {
    @ObservedObject var eventKitManager: EventKitManager
    @ObservedObject var newsFeedViewModel: NewsFeedViewModel
    
    // NEU: Transit Abhängigkeiten
    @ObservedObject var locationManager: LocationManager
    @ObservedObject var transitViewModel: TransitViewModel

    // NEU: SystemInfoManager für Batteriestatus
    @StateObject private var systemInfoManager = SystemInfoManager()

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    // AppStorage zur Persistenz der Reihenfolge als String
    @AppStorage("tileOrder") private var storedTileOrderString: String = ""
    // NEU: AppStorage für die Scrollrichtung
    @AppStorage("tileScrollDirectionVertical") private var tileScrollDirectionVertical: Bool = false
    // Hintergrunddarstellung (für Settings vorbereitet)
    @AppStorage("useTranslucentBackground") private var useTranslucentBackground: Bool = true

    // @State für das mutable Array von TileType, das in der UI verwendet wird
    @State private var tileOrder: [TileType] = []
    
    // @State, um zu verfolgen, welche Kachel gerade gezogen wird (für visuelles Feedback)
    @State private var draggingTile: TileType?
    // @State, um den potenziellen Ablagezielindex für visuelles Feedback zu verfolgen
    @State private var dropTargetIndex: Int?

    // Zustand für den Bearbeitungsmodus
    @State private var isEditing: Bool = false

    // State-Variable für die aktuelle Uhrzeit
    @State private var currentDateTime: Date = Date()
    
    // State-Variablen für den Hover-Effekt der Buttons
    @State private var isHoveringCoffeeButton: Bool = false
    @State private var isHoveringEditButton: Bool = false
    @State private var isHoveringSettingsButton: Bool = false

    // Namespace für matchedGeometryEffect Animationen
    @Namespace private var animationNamespace

    // Da die Kachelgröße fest ist, können wir ein festes Spaltenlayout definieren.
    let fixedTileWidth: CGFloat = 370
    let fixedTileHeight: CGFloat = 270
    let gridSpacing: CGFloat = 20 // Abstand zwischen Kacheln
    
    // Helper function to parse the stored string into the tileOrder array
    private func updateTileOrder(from storedString: String) {
        // FIX: Wir parsen nur die Elemente, die im String enthalten sind.
        // Dies spiegelt die explizite Auswahl des Benutzers in den Einstellungen wider.
        let parsedTiles = storedString
                            .split(separator: ",")
                            .compactMap { TileType(rawValue: String($0)) }
        
        self.tileOrder = parsedTiles
    }

    init(eventKitManager: EventKitManager, newsFeedViewModel: NewsFeedViewModel, locationManager: LocationManager, transitViewModel: TransitViewModel) {
        self.eventKitManager = eventKitManager
        self.newsFeedViewModel = newsFeedViewModel
        self.locationManager = locationManager // NEU
        self.transitViewModel = transitViewModel // NEU
        
        // Berechne den Standard-Reihenfolgen-String
        let defaultOrderString = TileType.allCases.map(\.rawValue).joined(separator: ",")

        let loadedOrderString = UserDefaults.standard.string(forKey: "tileOrder") ?? ""

        // Initialisiere storedTileOrderString und den State
        if loadedOrderString.isEmpty {
            _storedTileOrderString.wrappedValue = defaultOrderString
            _tileOrder = State(initialValue: TileType.allCases)
        } else {
            // Beim Start laden wir nur die Kacheln, die in der gespeicherten Liste sind.
            // Die Logik, um neue Kacheltypen hinzuzufügen, muss beibehalten werden, falls die App neue Typen enthält,
            // die noch nicht in der AppStorage gespeichert sind (z.B. nach einem Update).
            
            let initialParsedTiles = loadedOrderString
                                        .split(separator: ",")
                                        .compactMap { TileType(rawValue: String($0)) }
            
            var mergedTiles = initialParsedTiles
            
            // Füge neue, noch nicht gespeicherte Kacheltypen am Ende hinzu, falls sie fehlen
            for newTile in TileType.allCases {
                if !mergedTiles.contains(newTile) {
                    mergedTiles.append(newTile)
                }
            }
            _tileOrder = State(initialValue: mergedTiles)
        }
    }

    var body: some View {
        ZStack(alignment: .top) { // Wechsel zu ZStack, um den Footer über dem Grid zu platzieren
            VStack(spacing: 8) {
                // Obere Leiste mit Titel, Datum/Uhrzeit und Einstellungen
                HStack {
                    // Kaffeetassen-Icon wurde entfernt.
                    
                    VStack(alignment: .leading) {
                        Text("Croissant") // Titel vereinfacht
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        
                        // Aktuelles Datum und Uhrzeit mit Sekunden
                        Text(currentDateTime, format: .dateTime.day(.twoDigits).month(.twoDigits).year(.padded(4)).hour().minute().second().locale(Locale(identifier: "de_DE")))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                    
                    Spacer()
                    
                    // NEU: "Support the developer" Button
                    Button {
                        if let url = URL(string: "https://www.buymeacoffee.com/frobotics") {
                            openURL(url)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "cup.and.saucer.fill")
                            
                            if isHoveringCoffeeButton {
                                Text("Support the developer")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .transition(.opacity.combined(with: .move(edge: .leading)))
                            }
                        }
                    }
                    .buttonStyle(TahoeToolbarButtonStyle())
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isHoveringCoffeeButton = hovering
                        }
                    }
                    .padding(.trailing, 10)
                    
                    // Edit Button (Pencil Icon)
                    Button {
                        // Toggle Edit Mode
                        withAnimation {
                            isEditing.toggle()
                        }
                        // Wenn wir den Bearbeitungsmodus verlassen, lösche den Drag-Status
                        if !isEditing {
                            draggingTile = nil
                            dropTargetIndex = nil
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle")
                                .foregroundStyle(.primary)
                                .symbolRenderingMode(.monochrome)
                            
                            if isHoveringEditButton {
                                Text(isEditing ? "Done" : "Edit")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .transition(.opacity.combined(with: .move(edge: .leading)))
                            }
                        }
                    }
                    .buttonStyle(TahoeToolbarButtonStyle())
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isHoveringEditButton = hovering
                        }
                    }
                    .padding(.trailing, 10) // Abstand zum nächsten Button
                    
                    // Settings Button
                    Button {
                        // Reuse existing Settings window if already open; otherwise open a new one
                        if let win = NSApp.windows.first(where: { $0.identifier?.rawValue == "settingsWindow" }) {
                            win.makeKeyAndOrderFront(nil)
                            NSApp.activate(ignoringOtherApps: true)
                        } else {
                            openWindow(id: "settings")
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "gearshape")
                                .foregroundStyle(.primary)
                                .symbolRenderingMode(.monochrome)
                            
                            if isHoveringSettingsButton {
                                Text("Settings")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .transition(.opacity.combined(with: .move(edge: .leading)))
                            }
                        }
                    }
                    .buttonStyle(TahoeToolbarButtonStyle())
                    .onHover { hovering in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            isHoveringSettingsButton = hovering
                        }
                    }
                    .keyboardShortcut(",", modifiers: .command) // Shortcut: Command + Komma
                }
                .padding(.horizontal)
                
                // Flexibles Raster der Kacheln mit LazyVGrid in einem ScrollView
                GeometryReader { geometry in
                    if tileScrollDirectionVertical { // NEU: Vertikales Scrollen
                        ScrollView(.vertical) {
                            let availableWidth = geometry.size.width - (gridSpacing * 2)
                            let numColumns = max(1, Int(floor(availableWidth / (fixedTileWidth + gridSpacing))))
                            let columns = Array(repeating: GridItem(.fixed(fixedTileWidth), spacing: gridSpacing), count: numColumns)

                            LazyVGrid(columns: columns, spacing: gridSpacing) {
                                ForEachTile(
                                    tileOrder: $tileOrder,
                                    draggingTile: $draggingTile,
                                    dropTargetIndex: $dropTargetIndex,
                                    isEditing: $isEditing, // Changed from `isEditing` to `$isEditing`
                                    animationNamespace: animationNamespace,
                                    dependencies: (eventKitManager, newsFeedViewModel, locationManager, transitViewModel, systemInfoManager)
                                )
                            }
                            .padding(.horizontal, gridSpacing)
                            .padding(.top, 8)
                            .padding(.bottom, gridSpacing)
                            .frame(minWidth: geometry.size.width) // Stellt sicher, dass das Grid die gesamte Breite einnimmt, auch wenn nur eine Spalte vorhanden ist
                            .onDrop(of: isEditing ? [.text] : [], delegate: TileReorderDropDelegate(
                                tileOrder: $tileOrder,
                                draggingTile: $draggingTile,
                                dropTargetIndex: $dropTargetIndex,
                                fixedTileWidth: fixedTileWidth,
                                fixedTileHeight: fixedTileHeight,
                                gridSpacing: gridSpacing,
                                numColumns: numColumns,
                                isVerticalScroll: true // NEU
                            ))
                            .animation(.interpolatingSpring(stiffness: 150, damping: 20, initialVelocity: 5), value: tileOrder)
                            .animation(.easeOut(duration: 0.2), value: draggingTile)
                            .animation(.interpolatingSpring(stiffness: 120, damping: 25), value: isEditing)
                        }
                    } else { // Bestehendes horizontales Scrollen
                        ScrollView(.horizontal) {
                            // Dynamische Zeilenanzahl: kann auf 1 Zeile kollabieren, behält aber den geringen Header-Abstand bei
                            let availableHeight = geometry.size.height - (gridSpacing * 2)
                            let rowUnit = (fixedTileHeight + gridSpacing)
                            // Frühere Umschalt-Schwelle: 2 Zeilen schon bei geringerer Höhe erlauben (Bias 160pt)
                            let twoRowThreshold = (rowUnit * 2) - 160
                            let numRows = availableHeight >= twoRowThreshold ? 2 : 1
                            let rows = Array(repeating: GridItem(.fixed(fixedTileHeight), spacing: gridSpacing), count: numRows)

                            LazyHGrid(rows: rows, spacing: gridSpacing) {
                                ForEachTile(
                                    tileOrder: $tileOrder,
                                    draggingTile: $draggingTile,
                                    dropTargetIndex: $dropTargetIndex,
                                    isEditing: $isEditing, // Changed from `isEditing` to `$isEditing`
                                    animationNamespace: animationNamespace,
                                    dependencies: (eventKitManager, newsFeedViewModel, locationManager, transitViewModel, systemInfoManager)
                                )
                            }
                            .padding(.horizontal, gridSpacing)
                            .padding(.top, 8)
                            .padding(.bottom, gridSpacing)
                            .onDrop(of: isEditing ? [.text] : [], delegate: TileReorderDropDelegate(
                                tileOrder: $tileOrder,
                                draggingTile: $draggingTile,
                                dropTargetIndex: $dropTargetIndex,
                                fixedTileWidth: fixedTileWidth,
                                fixedTileHeight: fixedTileHeight,
                                gridSpacing: gridSpacing,
                                numColumns: numRows, // Hier sind numRows die "Spalten" im horizontalen Kontext
                                isVerticalScroll: false // NEU
                            ))
                            .animation(.interpolatingSpring(stiffness: 150, damping: 20, initialVelocity: 5), value: tileOrder)
                            .animation(.easeOut(duration: 0.2), value: draggingTile)
                            .animation(.interpolatingSpring(stiffness: 120, damping: 25), value: isEditing)
                        }
                    }
                }
            } // Ende VStack

            // (Footer removed)
            
        } // Ende ZStack
        // Mindestgröße für das Fenster, damit das Grid korrekt angezeigt wird.
        .frame(minWidth: 410, minHeight: 350)
        .onAppear {
            systemInfoManager.startMonitoring()
            eventKitManager.requestAccessToReminders()
            eventKitManager.requestAccessToEvents()
            // Standortanfrage wird bereits im TransitViewModel gestartet, aber hier können wir die Berechtigung anzeigen.
        }
        
        // WICHTIG: Wenn sich storedTileOrderString (aus SettingsView) ändert, aktualisiere tileOrder (das Array, das im ForEach verwendet wird).
        .onChange(of: storedTileOrderString) { _, newValue in
            // Aktualisiere das Array, welches das Layout steuert
            // Hier verwenden wir die vereinfachte Logik, die nur die tatsächlich gespeicherten Kacheln beibehält.
            self.updateTileOrder(from: newValue)
        }
        
        // Der onChange Handler für tileOrder bleibt, um Drag & Drop im Hauptfenster zu speichern.
        .onChange(of: tileOrder) { _, newValue in
            // Nur speichern, wenn die Änderung von Drag & Drop kam (oder wenn eine neue Kachel hinzugefügt/entfernt wurde, was onChange von storedTileOrderString triggert)
            storedTileOrderString = newValue.map(\.rawValue).joined(separator: ",")
        }
        
        // Timer, der jede Sekunde feuert, um die aktuelle Uhrzeit zu aktualisieren
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            self.currentDateTime = Date()
        }
        .background(
            Group {
                if useTranslucentBackground {
                    VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                } else {
                    Color(nsColor: .windowBackgroundColor)
                }
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
        .toolbar {
            ToolbarItem(placement: .principal) {
                TitlebarBannerView()
            }
            ToolbarItem(placement: .primaryAction) {
                // Batteriewarnung, nur bei niedrigem Akkustand (<20%) und wenn nicht geladen wird
                if let batteryLevel = systemInfoManager.batteryLevel, batteryLevel < 0.2, systemInfoManager.isCharging == false {
                    Image(systemName: "battery.25")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .symbolRenderingMode(.monochrome)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 10)
                }
            }
        }
        .modifier(WindowConfigurator())
    }
}

// NEU: Eine Hilfsansicht, um den ForEach-Inhalt für LazyVGrid und LazyHGrid zu kapseln und Redundanz zu vermeiden.
private struct ForEachTile: View {
    @Binding var tileOrder: [TileType]
    @Binding var draggingTile: TileType?
    @Binding var dropTargetIndex: Int?
    @Binding var isEditing: Bool // Changed from `let isEditing: Bool` to `@Binding var isEditing: Bool`
    let animationNamespace: Namespace.ID
    let dependencies: (EventKitManager, NewsFeedViewModel, LocationManager, TransitViewModel, SystemInfoManager)
    
    let fixedTileWidth: CGFloat = 370
    let fixedTileHeight: CGFloat = 270

    var body: some View {
        ForEach(0..<tileOrder.count + (draggingTile != nil && dropTargetIndex != nil ? 1 : 0), id: \.self) { index in
            let isPlaceholderVisible = isEditing && draggingTile != nil && dropTargetIndex == index
            
            if isPlaceholderVisible {
                Color.clear
                    .frame(width: fixedTileWidth, height: fixedTileHeight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5]))
                    )
                    .transition(.opacity)
                    .matchedGeometryEffect(id: "placeholder-\(draggingTile!.id)", in: animationNamespace)
            }
            
            let offset = (draggingTile != nil && dropTargetIndex != nil && index > dropTargetIndex!) ? 1 : 0
            let lookupIndex = index - offset
            if let tileType = tileOrder[safe: lookupIndex],
               tileType != draggingTile {
                
                DashboardTileView(content: AnyView(tileType.view(
                    eventKitManager: dependencies.0,
                    newsFeedViewModel: dependencies.1,
                    locationManager: dependencies.2,
                    transitViewModel: dependencies.3,
                    systemInfoManager: dependencies.4
                )), isEditing: $isEditing)
                .matchedGeometryEffect(id: tileType.id, in: animationNamespace)
                .zIndex(draggingTile == tileType ? 1000 : 0)
                .contentShape(Rectangle())
                .onDrag {
                    guard isEditing else { return NSItemProvider() }
                    self.draggingTile = tileType
                    return NSItemProvider(object: tileType.rawValue as NSString)
                }
            }
        }
    }
}


// Extension zum sicheren Zugriff auf Array-Elemente
extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}


// Ein View, der einen konsistenten Stil für alle Kacheln gewährleistet und den Hover-Effekt handhabt.
struct DashboardTileView: View {
    let content: AnyView
    let fixedWidth: CGFloat = 370
    let fixedHeight: CGFloat = 270
    
    // Binding, um den Bearbeitungsmodus zu erkennen
    @Binding var isEditing: Bool

    @State private var isHovering: Bool = false // Zustand für den Hover-Effekt
    
    // AppStorage to read the setting for the hover effect
    @AppStorage("enableTileHoverEffect") private var enableTileHoverEffect: Bool = true

    init(content: AnyView, isEditing: Binding<Bool>) {
        self.content = content
        self._isEditing = isEditing
    }

    var body: some View {
        // HIER ist der Ort, an dem wir entscheiden, ob Klicks auf den Inhalt durchgelassen werden.
        content
            // Blockiert alle Klicks und Interaktionen im Edit-Modus
            .allowsHitTesting(!isEditing)
            .padding()
            // Feste Größe für die Kacheln
            .frame(width: fixedWidth, height: fixedHeight, alignment: .topLeading)
            .background(
                VisualEffectView(material: .sidebar, blendingMode: .withinWindow, state: .active)
                    .allowsHitTesting(false)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15)
                    // Roter Rahmen im Bearbeitungsmodus, Standardrahmen im Normalmodus
                    .stroke(isEditing ? Color.red : Color.white.opacity(0.15), lineWidth: isEditing ? 3 : 1)
            )
            // Runde Ecken hinzugefügt
            .cornerRadius(15)
            // Weicherer, diffuser Schatten für einen "schwebenden" Effekt
            // Schatten beim Hover verstärkt: y-Offset von 6 auf 10, Radius von 12 auf 16
            .shadow(color: .black.opacity((isHovering || isEditing) ? 0.35 : 0.15), radius: (isHovering || isEditing) ? 16 : 8, x: 0, y: (isHovering || isEditing) ? 10 : 4) // Schatten ändert sich beim Hover/Edit
            // Skalierung beim Hover verstärkt: von 1.01 auf 1.03
            .scaleEffect(isHovering ? 1.03 : 1.0) // Leichtes Skalieren beim Hover
            .animation(.easeOut(duration: 0.2), value: isHovering) // Sanfte Animation
            // Deaktiviere onHover im Bearbeitungsmodus, um Konflikte zu vermeiden
            .onHover { hovering in
                // Only apply the hover effect if it's enabled and not in edit mode.
                if !isEditing && enableTileHoverEffect {
                    isHovering = hovering
                }
            }
            .onChange(of: enableTileHoverEffect) { _, newValue in
                // If the effect is disabled while hovering, reset the hover state.
                if !newValue {
                    isHovering = false
                }
            }
    }
}

// MARK: - Tahoe-like toolbar button style
struct TahoeToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.title2) // Icon-Größe angepasst für bessere Lesbarkeit
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                // KORREKTUR: ZStack entfernt, um doppelten Hintergrund zu vermeiden
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(configuration.isPressed ? 0.15 : 0.25), radius: configuration.isPressed ? 4 : 8, x: 0, y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}


// MARK: - Titlebar Banner View

// MARK: - Titlebar Banner View
struct TitlebarBannerView: View {
    var body: some View {
        Text("Croissant: Your Daily Essential.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
            .padding(.horizontal, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )
    }
}

// MARK: - VisualEffectView (AppKit bridge)
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let state: NSVisualEffectView.State

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = state
        v.isEmphasized = true
        return v
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

// MARK: - WindowConfigurator (round corners + modern chrome)
struct WindowConfigurator: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(WindowAccessor { window in
            guard let window = window else { return }
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            // WICHTIG: Dies bleibt FALSE, damit Kacheln gezogen werden können, anstatt das Fenster zu verschieben.
            window.isMovableByWindowBackground = false

            window.isOpaque = false
            window.backgroundColor = .clear

            if let contentView = window.contentView {
                contentView.wantsLayer = true
                contentView.layer?.cornerRadius = 18
                contentView.layer?.maskedCorners = [
                    .layerMinXMinYCorner, .layerMaxXMinYCorner,
                    .layerMinXMaxYCorner, .layerMaxXMaxYCorner
                ]
                contentView.layer?.masksToBounds = true
            }

            window.hasShadow = true
        })
    }
}

// MARK: - WindowAccessor
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        Resolver(onResolve: onResolve)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Resolver: NSView {
        let onResolve: (NSWindow?) -> Void
        init(onResolve: @escaping (NSWindow?) -> Void) {
            self.onResolve = onResolve
            super.init(frame: .zero)
        }
        @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onResolve(window)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            // Make this overlay view completely passthrough for mouse/gesture events
            return nil
        }
    }
}

#Preview {
    // Dummy-Instanzen für die Vorschau
    let locationManager = LocationManager()
    let transitViewModel = TransitViewModel(locationManager: locationManager)
    
    ContentView(
        eventKitManager: EventKitManager(),
        newsFeedViewModel: NewsFeedViewModel(),
        locationManager: locationManager,
        transitViewModel: transitViewModel
    )
        .frame(width: 900, height: 700)
}
