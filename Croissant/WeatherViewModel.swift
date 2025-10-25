import Foundation
import SwiftUI
import Combine

@MainActor
final class WeatherViewModel: ObservableObject {
    // MARK: - Output for the Tile
    @Published var locationTitle: String = "-"
    @Published var currentTemp: String = "--°C"
    @Published var currentRainChanceSuffix: String = "" // NEU: Für die separate, formatierte Anzeige (grau/klein)
    @Published var currentCondition: String = "-"
    @Published var currentSymbol: String = "cloud"
    @Published var hourly: [HourlyItem] = [] // next 12h
    @Published var todaySunrise: String = "—"
    @Published var todaySunset: String = "—"
    @Published var todayMinTemp: String = "--°"
    @Published var todayMaxTemp: String = "--°"
    @Published var todayRainChance: String = "–%"
    @Published var todayHumidity: String = "–%"
    @Published var moonPercent: String = "–%"
    @Published var moonSymbol: String = "moon"
    
    // MARK: - Debugging Properties (NEW)
    @Published var updatedLabel: String = ""
    @Published var errorMessage: String? = nil
    
    private static let debugDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
    
    // Computed property to match TransitVM's new implementation (time string only)
    var debugUpdatedLabel: String {
        return self.updatedLabel
    }

    @Published var daily: [DailyItem] = [] // next 3 days

    struct DailyItem: Identifiable, Equatable {
        let id = UUID()
        let date: String // e.g. Thu
        let minTemp: String
        let maxTemp: String
        let symbol: String
        let rainChance: String // e.g. 42%
    }

    struct HourlyItem: Identifiable, Equatable {
        let id = UUID()
        let time: String   // HH:mm
        let temp: String   // e.g., 11°
        let symbol: String // SF Symbol name
        let rainChance: String // e.g., 42%
    }

    // MARK: - Public API
    /// Lädt den 3‑Tage‑Forecast (inkl. Alerts) und bereitet nur "heute" + 12h vor
    func load(lat: Double, lon: Double) async {
        do {
            let response = try await WeatherManager.shared.fetchForecast(lat: lat, lon: lon, days: 3, includeAlerts: true)
            apply(response)
            
            // Update debug status on success
            self.errorMessage = nil
            self.updatedLabel = Self.debugDateFormatter.string(from: Date()) // Time string only
            
        } catch {
            print("WeatherViewModel.load error:", error.localizedDescription)
            self.errorMessage = error.localizedDescription
            // If this is the first failure, set updatedLabel to reflect it
            if self.updatedLabel.isEmpty || self.updatedLabel == "Update Failed" {
                self.updatedLabel = "Update Failed"
            }
        }
    }

    /// Wendet ein bereits geladenes ForecastResponse an (z. B. wenn CroissantApp schon geladen hat)
    func apply(_ r: ForecastResponse) {
        // Location
        locationTitle = [r.location.name, r.location.region].joined(separator: " · ")

        // Current
        currentTemp = "\(Int(round(r.current.temp_c)))°C"
        
        if let todayChance = r.forecast.forecastday.first?.day?.daily_chance_of_rain {
            // Store daily rain chance separately for UI formatting
            currentRainChanceSuffix = " (Rain: \(todayChance)%)"
        } else {
            currentRainChanceSuffix = ""
        }
        
        currentCondition = r.current.condition.text // Keep condition clean
        currentSymbol = Self.symbol(for: r.current.condition)

        // Today sunrise/sunset + moon from forecast.astro
        if let astro = r.forecast.forecastday.first?.astro {
            self.todaySunrise = astro.sunrise ?? "—"
            self.todaySunset  = astro.sunset  ?? "—"
            if let illum = Optional(astro.moon_illumination) {
                self.moonPercent = "\(illum)%"
            } else {
                self.moonPercent = "–%"
            }
            self.moonSymbol = Self.moonSymbol(for: astro.moon_phase ?? "")
        } else {
            self.todaySunrise = "—"
            self.todaySunset  = "—"
            self.moonPercent = "–%"
            self.moonSymbol = "moon"
        }

        // Hourly (next 24h, rolling across day boundary)
        var items: [HourlyItem] = []
        let forecastDays = r.forecast.forecastday
        let hours0 = forecastDays.first?.hour ?? []
        let hours1 = forecastDays.dropFirst().first?.hour ?? []
        let hours2 = forecastDays.dropFirst(2).first?.hour ?? []

        let nowHHmm = Self.hhmm(from: Date())
        let startIdx = hours0.firstIndex { ($0.time.suffix(5)) >= nowHHmm } ?? 0

        // Build a concatenated sequence from today[startIdx...] + next days
        let concatenated = Array(hours0.dropFirst(startIdx)) + hours1 + hours2
        let slice = concatenated.prefix(24)

        items = slice.map { h in
            HourlyItem(
                time: String(h.time.suffix(5)),
                temp: "\(Int(round(h.temp_c)))°",
                symbol: Self.symbol(for: h.condition),
                rainChance: (h.chanceOfRain.map { "\($0)%" }) ?? "–%"
            )
        }
        self.hourly = items

        if let hum = r.forecast.forecastday.first?.day?.avghumidity {
            // Since avghumidity is now Double? in Day, we round it to Int for display.
            self.todayHumidity = "\(Int(round(hum)))%"
        } else {
            self.todayHumidity = "–%"
        }

        // Daily (next 3 days)
        var days: [DailyItem] = []
        let formatterIn = DateFormatter()
        formatterIn.dateFormat = "yyyy-MM-dd"
        let formatterOut = DateFormatter()
        formatterOut.dateFormat = "EEE"

        for d in r.forecast.forecastday.prefix(3) {
            guard let day = d.day else { continue }
            let dateStr: String
            if let date = formatterIn.date(from: d.date) {
                dateStr = formatterOut.string(from: date)
            } else {
                dateStr = d.date
            }
            days.append(
                DailyItem(
                    date: dateStr,
                    minTemp: "\(Int(round(day.mintemp_c ?? .nan)))°",
                    maxTemp: "\(Int(round(day.maxtemp_c ?? .nan)))°",
                    symbol: Self.symbol(for: day.condition),
                    rainChance: day.daily_chance_of_rain.map { "\($0)%" } ?? "–%"
                )
            )
        }
        self.daily = days
        if let first = days.first {
            self.todayMinTemp = first.minTemp
            self.todayMaxTemp = first.maxTemp
            self.todayRainChance = first.rainChance
        } else {
            self.todayMinTemp = "--°"
            self.todayMaxTemp = "--°"
            self.todayRainChance = "–%"
        }
    }

    // MARK: - Symbol Mapping
    /// Mappt WeatherAPI-Condition auf SF Symbol
    static func symbol(for cond: Condition) -> String {
        if let code = cond.code { return symbol(forCode: code, fallbackText: cond.text) }
        return symbol(forText: cond.text)
    }

    private static func symbol(forCode code: Int, fallbackText: String) -> String {
        switch code {
        case 1000: return "sun.max.fill"               // Clear/Sunny
        case 1003: return "cloud.sun.fill"             // Partly cloudy
        case 1006: return "cloud.fill"                 // Cloudy
        case 1009: return "smoke.fill"                 // Overcast
        case 1030, 1135, 1147: return "cloud.fog.fill" // Mist/Fog
        case 1063, 1180, 1183, 1186, 1189, 1192, 1195: return "cloud.rain.fill"
        case 1150, 1153: return "cloud.drizzle.fill"
        case 1198, 1201: return "cloud.hail.fill"
        case 1066, 1210, 1213, 1216, 1219, 1222, 1225: return "cloud.snow.fill"
        case 1069, 1204, 1207, 1249, 1252: return "cloud.sleet.fill"
        case 1240, 1243, 1246: return "cloud.rain.fill"
        case 1255, 1258: return "cloud.snow.fill"
        case 1273, 1276: return "cloud.bolt.rain.fill" // Thunder + rain
        case 1279, 1282: return "cloud.bolt.fill"      // Thunder + snow
        default:
            return symbol(forText: fallbackText)
        }
    }

    private static func symbol(forText text: String) -> String {
        let t = text.lowercased()
        if t.contains("thunder") { return "cloud.bolt.rain.fill" }
        if t.contains("drizzle") { return "cloud.drizzle.fill" }
        if t.contains("rain") { return "cloud.rain.fill" }
        if t.contains("snow") { return "cloud.snow.fill" }
        if t.contains("sleet") { return "cloud.sleet.fill" }
        if t.contains("overcast") { return "smoke.fill" }
        if t.contains("cloud") { return "cloud.fill" }
        if t.contains("fog") || t.contains("mist") { return "cloud.fog.fill" }
        if t.contains("sun") || t.contains("clear") { return "sun.max.fill" }
        return "cloud"
    }

    // MARK: - Helpers
    private static func hhmm(from date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "HH:mm"
        return df.string(from: date)
    }

    // MARK: - Moon Symbol Mapping
    private static func moonSymbol(for phase: String) -> String {
        let p = phase.lowercased()
        if p.contains("new") { return "moonphase.new.moon" }
        if p.contains("waxing crescent") { return "moonphase.waxing.crescent" }
        if p.contains("first quarter") { return "moonphase.first.quarter" }
        if p.contains("waxing gibbous") { return "moonphase.waxing.gibbous" }
        if p.contains("full") { return "moonphase.full.moon" }
        if p.contains("waning gibbous") { return "moonphase.waning.gibbous" }
        if p.contains("last quarter") || p.contains("third quarter") { return "moonphase.last.quarter" }
        if p.contains("waning crescent") { return "moonphase.waning.crescent" }
        return "moon" // fallback
    }
}
