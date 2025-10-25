//
//  CroissantApp.swift
//  Croissant
//
//  Created by Frederik Mondel on 17.10.25.
//

import SwiftUI
import Combine

@main
struct CroissantApp: App {
    @State private var lastRoundedCoord: (Double, Double)? = nil
    // Instantiate the managers using StateObject
    @StateObject private var eventKitManager = EventKitManager()
    @StateObject private var newsFeedViewModel = NewsFeedViewModel()
    
    // NEU: Location Manager für Core Location
    @StateObject private var locationManager: LocationManager
    
    // NEU: Transit View Model, benötigt den Location Manager
    @StateObject private var transitViewModel: TransitViewModel
    
    // NEU: Weather View Model
    @StateObject private var weatherViewModel = WeatherViewModel()
    
    init() {
        // Initialisiere den Location Manager
        let locManager = LocationManager()
        // Initialisiere das Transit ViewModel ohne Parameter; LocationManager wird später gesetzt
        // FIX: Explizite Angabe des generischen Typs StateObject<T> zur Vermeidung des Compiler-Fehlers.
        self._locationManager = StateObject<LocationManager>(wrappedValue: locManager)
        self._transitViewModel = StateObject<TransitViewModel>(wrappedValue: TransitViewModel())
        
        // Die anderen Managers werden über die @StateObject Deklaration instanziiert, 
        // da sie keine speziellen initialen Abhängigkeiten haben.
    }


    var body: some Scene {
        WindowGroup {
            // Übergebe alle notwendigen Abhängigkeiten
            ContentView(
                eventKitManager: eventKitManager,
                newsFeedViewModel: newsFeedViewModel,
                locationManager: locationManager,
                transitViewModel: transitViewModel,
                weatherViewModel: weatherViewModel
            )
            .onAppear {
                // Stelle sicher, dass beim Start eine Standortabfrage erfolgt
                locationManager.requestLocation()
            }
            .onReceive(locationManager.$currentLocation.compactMap { $0 }) { loc in
                // Runde auf 4 Dezimalstellen (~11 m) und dedupliziere manuell
                let lat = (loc.latitude * 10_000).rounded() / 10_000
                let lon = (loc.longitude * 10_000).rounded() / 10_000
                if let last = lastRoundedCoord, last.0 == lat && last.1 == lon { return }
                lastRoundedCoord = (lat, lon)

                Task {
                    // Verwende das zentrale weatherViewModel zum Laden, um den Status zu aktualisieren
                    await weatherViewModel.load(lat: lat, lon: lon)
                }
            }
        }
        .defaultSize(width: 800, height: 600) // Applying default size as seen in DashboardApp.swift
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        
        // Include the Settings WindowGroup if it's required for the application structure
        WindowGroup(id: "settings") {
            // Übergebe alle notwendigen Abhängigkeiten an die SettingsView
            SettingsView(
                eventKitManager: eventKitManager, 
                newsFeedViewModel: newsFeedViewModel,
                locationManager: locationManager,
                transitViewModel: transitViewModel,
                weatherViewModel: weatherViewModel // NEU
            )
        }
        .defaultSize(width: 500, height: 600)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
    }
}
