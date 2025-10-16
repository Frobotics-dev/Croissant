//
//  WeatherTileView.swift
//  Dashboard
//
//  Created by Frederik Mondel on 15.10.25.
//

import SwiftUI

struct WeatherTileView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Weather", systemImage: "cloud.sun") // SFSymbol for weather
                .font(.headline)
            
            HStack(alignment: .bottom, spacing: 10) {
                Image(systemName: "sun.max.fill") // Sun symbol
                    .renderingMode(.original) // Retains original color
                    .font(.largeTitle)
                
                VStack(alignment: .leading) {
                    Text("20°C") // Temperature
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("Sunny") // Weather description
                        .font(.body)
                        .foregroundColor(.secondary)
                    Text("High: 22°C, Low: 12°C") // Min/Max temperature
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        // .tileStyle() // REMOVED: DashboardTileView now applies the styling
    }
}
