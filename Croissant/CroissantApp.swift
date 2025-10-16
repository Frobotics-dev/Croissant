//
//  CroissantApp.swift
//  Croissant
//
//  Created by Frederik Mondel on 17.10.25.
//

import SwiftUI

@main
struct CroissantApp: App {
    // Instantiate the managers as StateObjects to ensure they live for the lifetime of the app
    @StateObject private var eventKitManager = EventKitManager()
    @StateObject private var newsFeedViewModel = NewsFeedViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(eventKitManager: eventKitManager, newsFeedViewModel: newsFeedViewModel)
        }
        .defaultSize(width: 800, height: 600) // Applying default size as seen in DashboardApp.swift
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        
        // Include the Settings WindowGroup if it's required for the application structure
        WindowGroup(id: "settings") {
            SettingsView(eventKitManager: eventKitManager, newsFeedViewModel: newsFeedViewModel)
        }
        .defaultSize(width: 500, height: 600)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
    }
}
