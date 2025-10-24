import SwiftUI
import Combine

struct WeatherTileView: View {
    // FIX: Da WeatherTileView oft in ContentView neu erstellt wird, 
    // sollte locationManager als @EnvironmentObject oder @ObservedObject 
    // übergeben oder geteilt werden. Hier verwenden wir LocationManager.shared
    // und fügen eine @StateObject für das ViewModel hinzu.
    @ObservedObject private var locationManager = LocationManager.shared
    @StateObject private var vm = WeatherViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Label(vm.locationTitle.isEmpty ? "Weather" : vm.locationTitle, systemImage: "cloud.sun")
                .font(.headline)

            HStack(alignment: .bottom, spacing: 10) {
                Image(systemName: vm.currentSymbol)
                    .renderingMode(.original)
                    .font(.system(size: 42))
                VStack(alignment: .leading, spacing: 2) {
                    // NEU: HStack für Temperatur und die separat formatierte Regenwahrscheinlichkeit
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(vm.currentTemp)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        // Regenwahrscheinlichkeit: kleiner und grau
                        Text(vm.currentRainChanceSuffix)
                            .font(.subheadline) // Kleiner als .title2, aber gut lesbar
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary) // Grau (secondary color)
                    }
                    
                    Text(vm.currentCondition)
                        .font(.body)
                        .foregroundColor(.secondary)
                    // Today details: Tmax / Tmin / Humidity
                    HStack(spacing: 8) {
                        Text("H: \(vm.todayMaxTemp)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("L: \(vm.todayMinTemp)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Humidity: \(vm.todayHumidity)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 12)

                // Sunrise / Sunset to the right with icons
                VStack(alignment: .trailing, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "sunrise.fill")
                            .symbolRenderingMode(.multicolor)
                            .frame(width: 35, alignment: .center) // Icon-Spalte, zentriert
                        Text(vm.todaySunrise)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .leading) // Text-Spalte, linksbündig
                    }
                    HStack(spacing: 6) {
                        Image(systemName: "sunset.fill")
                            .symbolRenderingMode(.multicolor)
                            .frame(width: 35, alignment: .center) // Icon-Spalte, zentriert
                        Text(vm.todaySunset)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .leading) // Text-Spalte, linksbündig
                    }
                    HStack(spacing: 6) {
                        Image(systemName: vm.moonSymbol)
                            .symbolRenderingMode(.multicolor)
                            .frame(width: 35, alignment: .center) // Icon-Spalte, zentriert
                        Text(vm.moonPercent)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.secondary)
                            .frame(width: 50, alignment: .leading) // Text-Spalte, linksbündig
                    }
                }
            }

            Divider().padding(.vertical, 4)

            // Hourly forecast (next 24h)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(vm.hourly) { hour in
                        VStack(spacing: 4) {
                            Text(hour.time)
                                .font(.caption2)
                                .monospacedDigit()
                            Image(systemName: hour.symbol)
                                .renderingMode(.original)
                            Text(hour.temp)
                                .font(.caption2)
                                .monospacedDigit()
                            Text(hour.rainChance)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            Divider().padding(.vertical, 4)

            // Daily forecast for the next 2 days (skip today)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(vm.daily.dropFirst().prefix(2))) { (day: WeatherViewModel.DailyItem) in
                    HStack(spacing: 12) {
                        Text(day.date)
                            .font(.subheadline)
                            .frame(width: 36, alignment: .leading)
                        Image(systemName: day.symbol)
                            .renderingMode(.original)
                            .frame(width: 22)
                        Spacer(minLength: 8)
                        // Extras column (placeholder for wind/humidity later)
                        Text("Rain: \(day.rainChance)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 88, alignment: .trailing)
                        // Temps aligned with monospaced digits
                        HStack(spacing: 4) {
                            Text(day.minTemp)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                            Text("/")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(day.maxTemp)
                                .font(.subheadline)
                                .monospacedDigit()
                        }
                        .frame(width: 80, alignment: .trailing)
                    }
                }
            }
        }
        .onAppear {
            if let loc = locationManager.currentLocation {
                Task { await vm.load(lat: loc.latitude, lon: loc.longitude) }
            } else {
                locationManager.requestLocation()
            }
        }
        .onReceive(locationManager.$currentLocation.compactMap { $0 }) { loc in
            Task { await vm.load(lat: loc.latitude, lon: loc.longitude) }
        }
        // Refresh every 15 minutes
        .onReceive(Timer.publish(every: 900, on: .main, in: .common).autoconnect()) { _ in
            if let loc = locationManager.currentLocation {
                Task { await vm.load(lat: loc.latitude, lon: loc.longitude) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
