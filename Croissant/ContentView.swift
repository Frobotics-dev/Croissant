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

    var id: String { self.rawValue }

    @ViewBuilder
    func view(eventKitManager: EventKitManager, newsFeedViewModel: NewsFeedViewModel) -> some View {
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
            SystemInfoTileView()
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

    // Hilfsfunktion zur Berechnung des Index basierend auf der Drop-Position
    private func getIndex(for location: CGPoint) -> Int {
        // DropInfo.location ist relativ zur View, an die der `onDrop`-Modifizierer angehängt ist,
        // was in unserem Fall der LazyVGrid ist.
        // Wir müssen die Polsterung berücksichtigen, die auf den LazyVGrid angewendet wird.
        let xInGridContent = location.x - gridSpacing
        let yInGridContent = location.y - gridSpacing

        // Wenn die Position außerhalb des Grid-Inhaltsbereichs liegt (z.B. oberhalb oder links der ersten Kachel),
        // können wir Index 0 annehmen.
        guard xInGridContent >= 0, yInGridContent >= 0 else {
            return 0
        }

        let column = Int(floor(xInGridContent / (fixedTileWidth + gridSpacing)))
        let row = Int(floor(yInGridContent / (fixedTileHeight + gridSpacing)))
        
        // Berechne den theoretischen Index
        var index = row * numColumns + column
        
        // Beschränke den Index auf die Grenzen des aktuellen tileOrder-Arrays (0 bis count)
        index = min(max(0, index), tileOrder.count)
        
        return index
    }

    func dropEntered(info: DropInfo) {
        guard let draggedRawValue = info.itemProviders(for: [.text]).first else { return }
        
        _ = draggedRawValue.loadObject(ofClass: NSString.self) { (item, error) in
            DispatchQueue.main.async {
                guard let draggedRawValueString = item as? String,
                      let draggedTileType = TileType(rawValue: draggedRawValueString) else { return }
                
                // Setze draggingTile, wenn es noch nicht gesetzt ist oder sich geändert hat
                if self.draggingTile == nil || self.draggingTile != draggedTileType {
                    self.draggingTile = draggedTileType
                }
            }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let draggingTile = draggingTile else { return DropProposal(operation: .forbidden) }

        let calculatedIndex = getIndex(for: info.location)
        
        // Wenn über der ursprünglichen Position der gezogenen Kachel gezogen wird,
        // soll kein Platzhalter angezeigt werden.
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

                // Nur verschieben, wenn das Ziel vom Ursprung verschieden ist
                if sourceIndex != targetIndex {
                    var newOrder = tileOrder
                    let movedTile = newOrder.remove(at: sourceIndex)
                    newOrder.insert(movedTile, at: targetIndex)
                    tileOrder = newOrder // Aktualisiere das Binding
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

    @Environment(\.openWindow) private var openWindow

    // AppStorage zur Persistenz der Reihenfolge als String
    @AppStorage("tileOrder") private var storedTileOrderString: String = ""

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

    init(eventKitManager: EventKitManager, newsFeedViewModel: NewsFeedViewModel) {
        self.eventKitManager = eventKitManager
        self.newsFeedViewModel = newsFeedViewModel
        
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
            VStack(spacing: 20) {
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
                    .padding(.top, 8)
                    
                    Spacer()
                    
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
                        Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle")
                            .font(.title2)
                            // Monochrom: Nutze .primary und erzwinge .monochrome Rendering
                            .foregroundStyle(.primary)
                            .symbolRenderingMode(.monochrome)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 10) // Abstand zum nächsten Button

                    
                    // Settings Button
                    Button {
                        // Beim Öffnen der Einstellungen das NewsFeedViewModel übergeben
                        openWindow(id: "settings")
                    } label: {
                        // Monochrom: Nutze .secondary
                        Image(systemName: "gearshape.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .symbolRenderingMode(.monochrome)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(",", modifiers: .command) // Shortcut: Command + Komma
                }
                .padding(.horizontal)
                
                // Flexibles Raster der Kacheln mit LazyVGrid in einem ScrollView
                GeometryReader { geometry in
                    ScrollView([.horizontal, .vertical]) {
                        // Berechnung der Spaltenanzahl basierend auf der verfügbaren Breite
                        let availableWidth = geometry.size.width - (gridSpacing * 2) // Berücksichtigt das Padding der LazyVGrid
                        let numColumns = max(1, Int(floor(availableWidth / (fixedTileWidth + gridSpacing))))
                        let columns = Array(repeating: GridItem(.fixed(fixedTileWidth), spacing: gridSpacing), count: numColumns)

                        LazyVGrid(columns: columns, spacing: gridSpacing) {
                            // Iteriere über alle Indizes, um Platzhalter korrekt einzufügen
                            ForEach(0..<tileOrder.count + (draggingTile != nil && dropTargetIndex != nil ? 1 : 0), id: \.self) { index in
                                
                                let isPlaceholderVisible = isEditing && draggingTile != nil && dropTargetIndex == index
                                
                                // Füge einen visuellen Platzhalter für das gezogene Element ein (nur im Edit-Modus)
                                if isPlaceholderVisible {
                                    Color.clear
                                        .frame(width: fixedTileWidth, height: fixedTileHeight)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 15)
                                                .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [5]))
                                        )
                                        .transition(.opacity) // Animation für Erscheinen/Verschwinden
                                        .matchedGeometryEffect(id: "placeholder-\(draggingTile!.id)", in: animationNamespace)
                                }
                                
                                // Zeige die tatsächliche Kachel nur an, wenn sie nicht die gerade gezogene ist
                                if let actualTileIndex = tileOrder.firstIndex(where: { $0 == tileOrder[safe: index - (draggingTile != nil && dropTargetIndex != nil && index > dropTargetIndex! ? 1 : 0)] }),
                                   let tileType = tileOrder[safe: actualTileIndex],
                                   tileType != draggingTile {
                                    
                                    DashboardTileView(content: AnyView(tileType.view(eventKitManager: eventKitManager, newsFeedViewModel: newsFeedViewModel)), isEditing: $isEditing)
                                    .matchedGeometryEffect(id: tileType.id, in: animationNamespace)
                                    
                                    // Z-Index erhöhen, wenn sie gezogen wird
                                    .zIndex(draggingTile == tileType ? 1000 : 0)

                                    // Stellt sicher, dass die gesamte Kachelfläche als Drag-Ziel fungiert
                                    .contentShape(Rectangle())

                                    // Drag-Funktionalität nur im Bearbeitungsmodus aktivieren
                                    .onDrag {
                                        guard isEditing else { return NSItemProvider() }
                                        self.draggingTile = tileType // Setzt die gezogene Kachel
                                        return NSItemProvider(object: tileType.rawValue as NSString)
                                    }
                                    
                                    // WICHTIG: KEIN allowsHitTesting HIER!
                                    // Die Kachel muss Klick-Events zulassen, damit sie weiter an die DashboardTileView gesendet werden.
                                    // Die Drag-Geste hat Priorität vor normalen Klicks.
                                }
                            }
                        }
                        .padding(gridSpacing) // Polsterung um das gesamte Grid
                        // Zentriere das Grid, wenn es nicht die gesamte verfügbare Breite ausfüllt
                        .frame(minWidth: geometry.size.width)
                        
                        // Drop-Funktionalität nur im Bearbeitungsmodus aktivieren
                        .onDrop(of: isEditing ? [.text] : [], delegate: TileReorderDropDelegate(
                            tileOrder: $tileOrder,
                            draggingTile: $draggingTile,
                            dropTargetIndex: $dropTargetIndex,
                            fixedTileWidth: fixedTileWidth,
                            fixedTileHeight: fixedTileHeight,
                            gridSpacing: gridSpacing,
                            numColumns: numColumns
                        ))
                        
                        // Optimierte Feder-Animation für Positionswechsel
                        .animation(.interpolatingSpring(stiffness: 150, damping: 20, initialVelocity: 5), value: tileOrder)
                        
                        // Animiere Änderungen in draggingTile (für Deckkraft)
                        .animation(.easeOut(duration: 0.2), value: draggingTile)
                        
                        // NEU: Animation für das gesamte Grid, wenn der Bearbeitungsmodus wechselt.
                        .animation(.interpolatingSpring(stiffness: 120, damping: 25), value: isEditing)
                    }
                }
            } // Ende VStack

            // NEUER FOOTER: Schwebender Text am unteren Rand des ZStacks
            VStack {
                Spacer() // Schiebt den Inhalt ganz nach unten
                
                Text("Made with ❤️ in Germany by Frederik Mondel")
                    .font(.caption) // Kleinere Schriftgröße
                    .foregroundColor(.secondary)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 15)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.thinMaterial) // Transparenter Hintergrund
                            .shadow(radius: 5) // Leichter Schatten
                    )
                    .padding(.bottom, 20) // Abstand zum unteren Fensterrand
            }
            // Stellt sicher, dass der Footer keine Klicks aufnimmt, falls er transparent ist
            .allowsHitTesting(false)
            
        } // Ende ZStack
        // Sehr kleine Mindestgröße für das Fenster, damit es beliebig klein gezogen werden kann.
        .frame(minWidth: 100, minHeight: 100)
        .onAppear {
            eventKitManager.requestAccessToReminders()
            eventKitManager.requestAccessToEvents()
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
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow, state: .active)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        )
        .modifier(WindowConfigurator())
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
                if !isEditing {
                    isHovering = hovering
                }
            }
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
    ContentView(eventKitManager: EventKitManager(), newsFeedViewModel: NewsFeedViewModel())
        .frame(width: 900, height: 700)
}
