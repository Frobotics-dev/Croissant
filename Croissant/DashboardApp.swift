import SwiftUI

// @main removed here, as CroissantApp is already marked as the entry point.
struct DashboardApp: App {
    // Here we instantiate the EventKitManager once for the entire app
    // This allows it to be shared between ContentView and SettingsView
    @StateObject private var eventKitManager = EventKitManager()
    // New: Instance of NewsFeedViewModel for the entire app
    @StateObject private var newsFeedViewModel = NewsFeedViewModel() 

    var body: some Scene {
        WindowGroup {
            // Die Platzhalter werden durch die @StateObject Instanzen ersetzt
            ContentView(eventKitManager: eventKitManager, newsFeedViewModel: newsFeedViewModel)
        }
        .defaultSize(width: 800, height: 600) // Default size for the main window
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)

        // New window for settings
        WindowGroup(id: "settings") {
            SettingsView(eventKitManager: eventKitManager, newsFeedViewModel: newsFeedViewModel) // Pass manager and view model to SettingsView
        }
        .defaultSize(width: 500, height: 600) // Default size for the settings window
        .windowResizability(.contentSize) // The window cannot be freely scaled, only to fit the content
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
    }
}
