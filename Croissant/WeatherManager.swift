import Foundation

// MARK: - WeatherManager (Today-only)
struct WeatherManager {
    static let shared = WeatherManager()
    private init() {}

    enum WeatherError: Error, LocalizedError {
        case badURL
        case badResponse(status: Int, message: String?)

        var errorDescription: String? {
            switch self {
            case .badURL: return "Failed to build WeatherAPI URL"
            case .badResponse(let status, let message): return "WeatherAPI HTTP status: \(status)\(message.map { ": \($0)" } ?? "")"
            }
        }
    }

    // MARK: API
    @discardableResult
    func fetchForecast(lat: Double, lon: Double, days: Int = 3, includeAlerts: Bool = true) async throws -> ForecastResponse {
        var comps = URLComponents(string: "https://weatherapi.frobotics.workers.dev/api/weather")!
        comps.queryItems = [
            URLQueryItem(name: "lat", value: String(lat)),
            URLQueryItem(name: "lon", value: String(lon)),
            URLQueryItem(name: "days", value: String(days)),
            URLQueryItem(name: "alerts", value: includeAlerts ? "yes" : "no")
        ]
        guard let url = comps.url else { throw WeatherError.badURL }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            struct APIErrorEnvelope: Decodable { struct APIE: Decodable { let code: Int; let message: String }; let error: APIE }
            let msg: String?
            if let parsed = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                msg = "[\(parsed.error.code)] \(parsed.error.message)"
            } else {
                msg = String(data: data, encoding: .utf8)
            }
            throw WeatherError.badResponse(status: http.statusCode, message: msg)
        }

        let decoder = JSONDecoder()
        return try decoder.decode(ForecastResponse.self, from: data)
    }

    /// Gibt die heutige Vorhersage in einem kompakten Format aus (angelehnt an dein Beispiel-JSON)
    func logToday(_ r: ForecastResponse) {
        guard let today = r.forecast.forecastday.first else {
            print("Keine heutig Vorhersage gefunden")
            return
        }
        print("\n===== Today's Forecast =====")
        print("Location:", r.location.name, "|", r.location.region, "|", r.location.country)
        print("Date:", today.date)
        if let d = today.day {
            let maxT = d.maxtemp_c ?? .nan
            let minT = d.mintemp_c ?? .nan
            let avgT = d.avgtemp_c ?? .nan
            print(String(format: "Day: max %.1f°C / min %.1f°C / avg %.1f°C", maxT, minT, avgT))
            print("Condition:", d.condition.text)
            if let chance = d.daily_chance_of_rain { print("Chance of rain:", "\(chance)%") }
            if let hum = d.avghumidity { print("Avg Humidity:", "\(hum)%") } // Log helper update
        }
        // FIX: Use Astro.moon_illumination directly since it is now a non-optional Int and the computed property was removed.
        if let astro = today.astro {
            print("Moon:", "\(astro.moon_illumination)%")
        }
        if let hours = today.hour {
            print("-- Hourly --")
            for h in hours { print("\(h.time): \(h.temp_c)°C | \(h.condition.text)") }
        }
        print("============================\n")
    }
}

// MARK: - Models (subset, tolerant to extra fields)
struct ForecastResponse: Decodable {
    let location: Location
    let current: Current
    let forecast: Forecast
    let alerts: Alerts? // wird ignoriert, kommt aber in der API oft vor
}

struct Location: Decodable {
    let name: String
    let region: String
    let country: String
    let lat: Double
    let lon: Double
    let tz_id: String
}

struct Condition: Decodable {
    let text: String
    let icon: String?
    let code: Int?
}

struct Current: Decodable { // minimal
    let temp_c: Double
    let temp_f: Double?
    let is_day: Int?
    let condition: Condition
}

struct Forecast: Decodable { let forecastday: [ForecastDay] }

struct ForecastDay: Decodable {
    let date: String
    let day: Day?
    let hour: [Hour]?
    let astro: Astro?
}

struct Astro: Decodable {
    let sunrise: String?
    let sunset: String?
    let moonrise: String?
    let moonset: String?
    let moon_phase: String
    let moon_illumination: Int
    let is_moon_up: Int?
    let is_sun_up: Int?
}

// Decode an integer that may come as a number or a string
struct IntOrString: Decodable {
    let intValue: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let i = try? container.decode(Int.self) {
            intValue = i
        } else if let s = try? container.decode(String.self) {
            intValue = Int(s)
        } else if let d = try? container.decode(Double.self) {
            intValue = Int(d)
        } else {
            intValue = nil
        }
    }
}

struct Day: Decodable {
    let maxtemp_c: Double?
    let mintemp_c: Double?
    let avgtemp_c: Double?
    let avghumidity: Double? // ADDED: Required by WeatherViewModel
    let daily_chance_of_rain: Int?
    let condition: Condition
}

struct Hour: Decodable {
    let time: String
    let temp_c: Double
    let condition: Condition
    let chanceOfRain: Int?

    private enum CodingKeys: String, CodingKey {
        case time
        case temp_c
        case condition
        case chanceOfRain = "chance_of_rain"
    }
}

struct Alerts: Decodable { let alert: [Alert] }
struct Alert: Decodable { let headline: String? }

// MARK: - Debug helper
#if DEBUG
@discardableResult
func testWeatherAPIConsole(lat: Double = 48.137, lon: Double = 11.575) -> Task<Void, Never> {
    Task {
        do {
            let r = try await WeatherManager.shared.fetchForecast(lat: lat, lon: lon, days: 3, includeAlerts: true)
            WeatherManager.shared.logToday(r)
        } catch {
            print("Weather error 2:", error.localizedDescription)
        }
    }
}
#endif
