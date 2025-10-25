import Foundation
import Combine
import CoreLocation // Hinzugefügt, um CLLocationDistance und CLLocationCoordinate2D nutzen zu können

// HINWEIS: Wir benötigen die Definition der erwarteten API-Antwortstrukturen
// Da diese fehlen, verwenden wir Platzhalter und konzentrieren uns auf Logging und URL-Generierung.

final class TransitViewModel: ObservableObject {
    
    // MARK: - State & Dependencies
    
    // Interne Flags zur Steuerung von Requests
    private var lastFetchCoordinate: CLLocationCoordinate2D?
    private let minimumDistanceForNewFetch: CLLocationDistance = 20.0 // 20 Meter
    private var hasRequestedLocation = false
    
    // Erforderlich, um Standortaktualisierungen zu verfolgen
    var locationManager: LocationManager? {
        didSet {
            print("🌐 [TransitVM] locationManager assigned (didSet). Setting up subscription…")
            setupLocationSubscription()
            // FIX 1: Entfernen des redundanten sofortigen Fetches/requestLocation() aus didSet,
            // da die Subscription das Event abfängt oder wir den Fallfback im setup regeln.
            if let loc = locationManager?.currentLocation {
                print("🌐 [TransitVM] currentLocation already available → trigger fetch.")
                fetchNearbyStops(lat: loc.latitude, lon: loc.longitude)
            } else {
                print("🌐 [TransitVM] No currentLocation yet → relying on subscription/request in setup.")
            }
        }
    }
    private var locationCancellable: AnyCancellable?
    private var minuteTimer: AnyCancellable?
    private var refreshTimer: AnyCancellable?
    private var departuresRefreshTimer: AnyCancellable?
    private var infrequentLocationTimer: AnyCancellable?
    
    // Timer for fallback checks in setupLocationSubscription
    private var fallbackLocationTimer5s: Timer?
    private var fallbackLocationTimer10s: Timer?
    
    // Guard set to prevent repeated after-midnight merges per cycle
    private var midnightMergeDoneForStop: Set<String> = []
    
    // Public state for SwiftUI
    @Published var selectedStop: Stop?
    @Published var nearbyStops: [Stop] = []
    @Published var departuresByStop: [String: [Departure]] = [:] // key: Stop.id
    @Published var departures: [Departure] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?
    var updatedLabel: String {
        guard let d = lastUpdated else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE_POSIX")
        f.timeZone = .current
        f.dateFormat = "HH:mm:ss"
        return "Updated: \(f.string(from: d))"
    }
    
    // Configuration
    // ACHTUNG: Derzeit ist dies eine Platzhalter-API.
    // In einer echten App müsste dies die URL des jeweiligen Verkehrsverbundes sein (z.B. VBB, MVV, VAG, etc.)
    let apiBaseURL: String = "https://v6.db.transport.rest"
    
    // Suchradius in Metern
    @Published var searchRadiusMeters: Double {
        didSet {
            UserDefaults.standard.set(searchRadiusMeters, forKey: "transitSearchRadiusMeters")
            print("⚙️ [TransitVM] Search radius updated to \(searchRadiusMeters)m and saved.")
            // Optionally trigger a re-fetch if location is known and radius changed significantly
            if let loc = locationManager?.currentLocation {
                fetchNearbyStops(lat: loc.latitude, lon: loc.longitude)
            }
        }
    }
    
    init(locationManager: LocationManager? = nil) {
        // Load search radius from UserDefaults or set default
        self.searchRadiusMeters = UserDefaults.standard.double(forKey: "transitSearchRadiusMeters")
        if self.searchRadiusMeters == 0 { // Default value if not set
            self.searchRadiusMeters = 3000.0
            UserDefaults.standard.set(self.searchRadiusMeters, forKey: "transitSearchRadiusMeters")
        }
        print("⚙️ [TransitVM] Initialized with search radius: \(self.searchRadiusMeters)m")
        
        let lm: LocationManager = {
            if let provided = locationManager {
                print("🌐 [TransitVM] init: locationManager provided → will wire explicitly (didSet not called during init)")
                return provided
            } else {
                print("🌐 [TransitVM] init: no locationManager provided → creating one")
                return LocationManager()
            }
        }()
        self.locationManager = lm
        
        // Wire subscription explicitly and trigger first fetch/request
        print("🌐 [TransitVM] init: wiring subscription explicitly…")
        setupLocationSubscription()
        
        // FIX 1: Entfernen des requestLocation() aus init. Das Abonnement oder der Fallback übernimmt.
        if let loc = lm.currentLocation {
            print("🌐 [TransitVM] init: cached currentLocation → immediate fetch (lat:\(loc.latitude), lon:\(loc.longitude))")
            fetchNearbyStops(lat: loc.latitude, lon: loc.longitude)
        } else {
            print("🌐 [TransitVM] init: no cached location → relying on subscription/request in setup.")
        }
        
        // Start periodic timers (minute ETA updates, 1-min refresh)
        startTimers()
        triggerInitialFetchIfNeeded()
    }
    
    private func triggerInitialFetchIfNeeded() {
        if let loc = locationManager?.currentLocation {
            print("🚀 [TransitVM] Initial fetch using cached location (lat:\(loc.latitude), lon:\(loc.longitude))")
            fetchNearbyStops(lat: loc.latitude, lon: loc.longitude)
        } else if !hasRequestedLocation {
            print("🚀 [TransitVM] Initial fetch: requesting location…")
            locationManager?.requestLocation()
            hasRequestedLocation = true
        } else {
            print("🚀 [TransitVM] Initial fetch: location already requested, waiting for subscription update…")
        }
    }
    
    private func startTimers() {
        // Cancel previous timers if any
        minuteTimer?.cancel()
        refreshTimer?.cancel()
        departuresRefreshTimer?.cancel()
        infrequentLocationTimer?.cancel()
        
        // 1) Every minute: recalc ETAs (no network)
        minuteTimer = Timer.publish(every: 10, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.recalculateETAs()
            }
        // Do an immediate initial tick so UI updates without waiting a minute
        DispatchQueue.main.async { [weak self] in self?.recalculateETAs() }
        
        // 1b) Every 15 seconds: refresh departures for currently selected & top nearby stops
        departuresRefreshTimer = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                let stopsToRefresh: [Stop] = {
                    // Prefer the selected stop; if not available, use up to first two nearby stops
                    if let sel = self.selectedStop {
                        return [sel]
                    } else {
                        return Array(self.nearbyStops.prefix(2))
                    }
                }()
                if stopsToRefresh.isEmpty { return }
                Task {
                    // Ensure we merge midnight only once per cycle; keep behavior consistent with location-driven refresh
                    self.midnightMergeDoneForStop.removeAll()
                    await withTaskGroup(of: Void.self) { group in
                        for stop in stopsToRefresh {
                            group.addTask { [weak self] in
                                await self?.fetchDepartures(for: stop, storeUnder: stop.id)
                            }
                        }
                    }
                }
            }
        
        // 2) Every 30 seconds: refresh location + departures (lightweight)
        refreshTimer = Timer.publish(every: 30, on: .main, in: .common) // Changed from 60 to 30
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                print("⏱️ [TransitVM] 30 seconds refresh triggered (departures only).") // Updated log message
                self.midnightMergeDoneForStop.removeAll()
                // Do not force a location refresh every minute; departuresRefreshTimer handles data freshness.
            }
        
        // 3) Every 10 minutes: request a fresh location (if available)
        infrequentLocationTimer = Timer.publish(every: 600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                print("🛰️ [TransitVM] 10 minute location refresh triggered.")
                // Only request if not already waiting for an update
                self.locationManager?.requestLocation()
            }
    }
    
    private func recalculateETAs() {
        let now = Date()
        
        // Update flat list (if used directly by UI, e.g. for a mixed view)
        self.departures = self.departures.map { dep in
            var d = dep
            if let t = (dep.actualWhen ?? dep.plannedWhen) {
                let mins = max(0, Int(t.timeIntervalSince(now) / 60.0))
                d.minutesUntilDeparture = mins
            }
            return d
        }
        
        // Update per-stop lists (primary source)
        var updated: [String: [Departure]] = [:]
        for (key, list) in self.departuresByStop {
            updated[key] = list.map { dep in
                var d = dep
                if let t = (dep.actualWhen ?? dep.plannedWhen) {
                    let mins = max(0, Int(t.timeIntervalSince(now) / 60.0))
                    d.minutesUntilDeparture = mins
                }
                return d
            }
        }
        self.departuresByStop = updated
    }
    
    private func setupLocationSubscription() {
        // Abonnieren der Standort-Updates des LocationManagers
        locationCancellable?.cancel()
        print("🌐 [TransitVM] setupLocationSubscription: cancelled previous subscription (if any)")
        
        // Cancel any existing fallback timers to avoid duplicates
        fallbackLocationTimer5s?.invalidate()
        fallbackLocationTimer10s?.invalidate()
        fallbackLocationTimer5s = nil
        fallbackLocationTimer10s = nil
        
        guard let lm = locationManager else {
            print("⚠️ [TransitVM] setupLocationSubscription: locationManager is nil → no subscription created")
            return
        }
        
        print("🌐 [TransitVM] setupLocationSubscription: creating subscription on $currentLocation…")
        
        // FIX 2: Entfernen des debounce aus Combine und stattdessen manuelle Prüfung in sink
        // Wir brauchen den ersten Wert so schnell wie möglich.
        locationCancellable = lm.$currentLocation
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] location in
                guard let self = self else { return }
                
                self.errorMessage = nil
                
                print("✅ [TransitVM] Subscription fired: new location lat=\(location.latitude), lon=\(location.longitude)")
                
                let newCoord = CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude)
                
                // Debounce-Prüfung: Ist die neue Koordinate zu nah an der zuletzt gefetchten?
                if let lastCoord = self.lastFetchCoordinate {
                    let lastCL = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
                    let newCL = CLLocation(latitude: newCoord.latitude, longitude: newCoord.longitude)
                    let distance = newCL.distance(from: lastCL)
                    
                    if distance < self.minimumDistanceForNewFetch {
                        print("🚫 [TransitVM] Location Debounced: Distance (\(String(format: "%.1f", distance))m) below minimum \(self.minimumDistanceForNewFetch)m.")
                        return
                    }
                }
                
                // Received new location - cancel fallback timers as we have a valid update
                self.fallbackLocationTimer5s?.invalidate()
                self.fallbackLocationTimer10s?.invalidate()
                self.fallbackLocationTimer5s = nil
                self.fallbackLocationTimer10s = nil
                
                self.errorMessage = nil
                
                self.fetchNearbyStops(lat: location.latitude, lon: location.longitude)
            }
        
        // FIX 1: Nur einmal Location anfordern (via hasRequestedLocation)
        if lm.currentLocation == nil && !self.hasRequestedLocation {
            print("🌐 [TransitVM] setupLocationSubscription: no cached location → requesting now…")
            lm.requestLocation()
            self.hasRequestedLocation = true
            
            // Start 5s fallback timer to check for cached location if no new location arrives
            fallbackLocationTimer5s = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if let cachedLoc = self.locationManager?.currentLocation {
                    print("⏳ [TransitVM] 5s fallback: using cached location (lat:\(cachedLoc.latitude), lon:\(cachedLoc.longitude)).")
                    // Check debounce to avoid redundant fetch
                    let currentCoord = CLLocationCoordinate2D(latitude: cachedLoc.latitude, longitude: cachedLoc.longitude)
                    if let lastCoord = self.lastFetchCoordinate {
                        let lastCL = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
                        let currentCL = CLLocation(latitude: currentCoord.latitude, longitude: currentCoord.longitude) // KORREKTUR: Verwende currentCoord
                        let distance = currentCL.distance(from: lastCL)
                        if distance >= self.minimumDistanceForNewFetch {
                            self.fetchNearbyStops(lat: cachedLoc.latitude, lon: cachedLoc.longitude)
                        } else {
                            print("🚫 [TransitVM] 5s fallback skipped fetch: cached location too close to last fetched location.")
                        }
                    } else {
                        self.fetchNearbyStops(lat: cachedLoc.latitude, lon: cachedLoc.longitude)
                    }
                } else {
                    print("⏳ [TransitVM] 5s fallback: no cached location available yet.")
                }
            }
            
            // Start 10s fallback timer to warn if still no location
            fallbackLocationTimer10s = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                if self.locationManager?.currentLocation == nil {
                    print("⚠️ [TransitVM] 10s fallback: still no location from LocationManager.")
                    DispatchQueue.main.async {
                        if self.locationManager?.currentLocation == nil {
                            self.errorMessage = "Location update delayed. Please ensure location permissions are granted."
                        }
                    }
                }
                // Invalidate timers to clean up
                self.fallbackLocationTimer5s?.invalidate()
                self.fallbackLocationTimer10s?.invalidate()
                self.fallbackLocationTimer5s = nil
                self.fallbackLocationTimer10s = nil
            }
            
        } else if let loc = lm.currentLocation {
            let lat = loc.latitude
            let lon = loc.longitude
            print("🌐 [TransitVM] setupLocationSubscription: cached location exists (lat:\(lat), lon:\(lon)) → immediate fetch.")
            // Starte den Fetch mit der vorhandenen Position, falls wir noch keinen hatten.
            // Der sink wird diesen Wert ohnehin sofort ausgeben, falls er existiert.
            // Check debounce to avoid duplicate fetch
            let currentCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            if let lastCoord = self.lastFetchCoordinate {
                let lastCL = CLLocation(latitude: lastCoord.latitude, longitude: lastCoord.longitude)
                let currentCL = CLLocation(latitude: currentCoord.latitude, longitude: currentCoord.longitude)
                let distance = currentCL.distance(from: lastCL)
                if distance >= self.minimumDistanceForNewFetch {
                    fetchNearbyStops(lat: lat, lon: lon)
                } else {
                    print("🚫 [TransitVM] setupLocationSubscription skipped fetch: cached location too close to last fetched location.")
                }
            } else {
                fetchNearbyStops(lat: lat, lon: lon)
            }
        } else {
            print("🌐 [TransitVM] setupLocationSubscription: Location already requested or cached.")
        }
    }
    
    
    // Builds the search URL for nearby stops
    func generateSearchURL(lat: Double, lon: Double) -> URL? {
        print("🚇 [TransitVM] Generating search URL for Lat: \(lat), Lon: \(lon), Radius: \(searchRadiusMeters)m")
        
        guard var urlComponents = URLComponents(string: "\(apiBaseURL)/locations/nearby") else {
            self.errorMessage = "Invalid API URL."
            return nil
        }
        
        urlComponents.queryItems = [
            URLQueryItem(name: "latitude", value: "\(lat)"),
            URLQueryItem(name: "longitude", value: "\(lon)"),
            URLQueryItem(name: "distance", value: "\(Int(searchRadiusMeters))"), // Use configurable radius
            URLQueryItem(name: "results", value: "5"),
            URLQueryItem(name: "stops", value: "true"),
            URLQueryItem(name: "poi", value: "false")
        ]
        
        guard let url = urlComponents.url else {
            self.errorMessage = "Failed to finalize URL construction."
            return nil
        }
        
        print("🚇 [TransitVM] Generated URL: \(url.absoluteString)")
        return url
    }
    
    // MARK: - API Models (v6.db.transport.rest)
    
    private struct APIGeoLocation: Decodable {
        let type: String?
        let id: String?
        let latitude: Double
        let longitude: Double
    }
    
    private struct APIProducts: Decodable {
        let nationalExpress: Bool?
        let national: Bool?
        let regionalExpress: Bool?
        let regional: Bool?
        let suburban: Bool?
        let bus: Bool?
        let ferry: Bool?
        let subway: Bool?
        let tram: Bool?
        let taxi: Bool?
    }
    
    private struct APINearbyItem: Decodable {
        let type: String
        let id: String?
        let name: String?
        let location: APIGeoLocation?
        let products: APIProducts?
        let distance: Double?
    }
    
    private struct APILine: Decodable {
        let type: String?
        let id: String?
        let name: String
        let mode: String?
        let product: String?
    }
    
    private struct APIDeparture: Decodable {
        let tripId: String?
        let direction: String?
        let line: APILine
        let when: Date?
        let plannedWhen: Date?
        let delay: Int?
        let platform: String?
        let plannedPlatform: String?
    }
    
    private struct APIDeparturesResponse: Decodable {
        let departures: [APIDeparture]
        // Some deployments also add realtimeDataUpdatedAt etc., which we don't need here
    }
    
    // Mapping helpers
    private func productToSystemIconName(_ product: String?) -> String {
        switch product {
        case "subway": return "tram.fill" // closest SF Symbol replacement; adjust if you prefer
        case "suburban": return "tram.fill"
        case "tram": return "tram.fill"
        case "bus": return "bus.fill"
        case "ferry": return "ferry.fill"
        case "nationalExpress", "national", "regional", "regionalExpress": return "train.side.front.car"
        default: return "tram.fill"
        }
    }
    
    // MARK: - API Fetching
    
    // Führt den API-Aufruf für nahegelegene Haltestellen durch
    private func fetchNearbyStops(lat: Double, lon: Double) {
        let currentCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        
        // FIX 3: Parallel-Fetch verhindern
        if self.isLoading {
            // Wenn isLoading true ist, prüfen wir, ob wir bereits an dieser Stelle gesucht haben (toleranz 1m für isLoading Check)
            if let last = self.lastFetchCoordinate {
                let lastCL = CLLocation(latitude: last.latitude, longitude: last.longitude)
                let currentCL = CLLocation(latitude: currentCoord.latitude, longitude: currentCoord.longitude) // KORREKTUR: Verwende currentCoord
                if currentCL.distance(from: lastCL) < 1.0 {
                    print("🚫 🚇 [TransitVM] Skipping fetch: Already loading near the same location.")
                    return
                }
            }
        }
        
        self.lastFetchCoordinate = currentCoord
        
        print("🚇 [TransitVM] fetchNearbyStops called (lat:\(lat), lon:\(lon))")
        guard let url = generateSearchURL(lat: lat, lon: lon) else {
            self.errorMessage = "Failed to create request URL."
            return
        }
        
        // FIX 3: isLoading direkt setzen
        self.isLoading = true
        self.errorMessage = nil
        
        Task {
            do {
                print("🚇 [TransitVM] Starting network request...")
                let (data, response) = try await URLSession.shared.data(from: url)
                
                // HTTP Response Check
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    print("❌ 🚇 [TransitVM] Request failed with HTTP Status Code: \(statusCode)")
                    if let errorBody = String(data: data, encoding: .utf8) {
                        print("❌ 🚇 [TransitVM] Error response body: \(errorBody.prefix(1000)))")
                    }
                    await MainActor.run { [weak self] in // self? in closure
                        self?.errorMessage = "API request failed (Status \(statusCode))"
                        self?.isLoading = false
                    }
                    return
                }
                
                print("✅ 🚇 [TransitVM] Request successful. Data size: \(data.count) bytes.")
                
                // Logge die empfangenen Daten (optional, kann bei großen Datenmengen zu viel Output erzeugen)
                if let jsonString = String(data: data, encoding: .utf8) {
                    print("🚇 [TransitVM] Received JSON: \(jsonString.prefix(500))...")
                }
                
                // Decode nearby locations (stops only)
                let decoder = JSONDecoder()
                let decodedItems = try decoder.decode([APINearbyItem].self, from: data)
                print("🔎 🚇 [TransitVM] Nearby items count: \(decodedItems.count)")
                for (idx, it) in decodedItems.enumerated() {
                    let dist = it.distance.map { String(format: "%.0f m", $0) } ?? "—"
                    print("   #\(idx+1): type=\(it.type), id=\(it.id ?? "—"), name=\(it.name ?? "—"), distance=\(dist)")
                }
                let stopsOnly: [Stop] = decodedItems.compactMap { item in
                    guard (item.type == "stop" || item.type == "station"),
                          let id = item.id, let name = item.name else { return nil }
                    return Stop(id: id, name: name)
                }
                print("✅ 🚇 [TransitVM] Stops-only count: \(stopsOnly.count)")
                if let s = stopsOnly.first {
                    print("✅ 🚇 [TransitVM] First stop: \(s.name) (id: \(s.id))")
                }
                
                if stopsOnly.isEmpty {
                    await MainActor.run { [weak self] in
                        self?.errorMessage = "No transit stops found nearby (Search Radius: \(Int(self?.searchRadiusMeters ?? 0))m)."
                        self?.selectedStop = nil
                        self?.isLoading = false
                    }
                    return
                }
                
                let topTwo = Array(stopsOnly.prefix(2))
                
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.nearbyStops = stopsOnly
                    
                    // Nur selectedStop aktualisieren, wenn er noch nicht gesetzt ist ODER der neue Stopp signifikant anders/näher ist.
                    // Für das Dashboard reicht es, einfach den nächsten Stopp zu nehmen.
                    self.selectedStop = topTwo.first
                    
                    self.errorMessage = nil
                    // isLoading stays true until departures are fetched
                }
                
                // Fetch departures for up to two stops in parallel
                await withTaskGroup(of: Void.self) { group in
                    for stop in topTwo {
                        group.addTask { [weak self] in
                            await self?.fetchDepartures(for: stop, storeUnder: stop.id)
                        }
                    }
                }
                
                await MainActor.run { [weak self] in
                    // Only set loading to false after all departure fetches are done
                    self?.isLoading = false
                }
                
            } catch { // FIX: #error durch catch { ersetzt
                if Task.isCancelled { return }
                print("❌ 🚇 [TransitVM] Network error: \(error.localizedDescription)")
                await MainActor.run { [weak self] in
                    self?.errorMessage = "Network error: \(error.localizedDescription)"
                    self?.isLoading = false
                }
            }
        }
    }
    
    // Wrapper to make the completion handler style synchronous for TaskGroup
    func fetchDepartures(for stop: Stop, storeUnder key: String) async -> Void {
        await withCheckedContinuation { cont in
            self.fetchDepartures(for: stop, when: nil) { dep in
                Task {
                    // First batch already in `dep`
                    var all = dep
                    
                    // If less than 5, fetch from next local midnight, but only once per stop per refresh cycle
                    let canMidnightMerge = !self.midnightMergeDoneForStop.contains(key)
                    if all.count < 5 && canMidnightMerge {
                        let cal = Calendar.current
                        let now = Date()
                        // Berechne die nächste lokale Mitternacht (00:00 Uhr des Folgetages)
                        var comps = cal.dateComponents(in: TimeZone.current, from: now)
                        comps.day = (comps.day ?? 0) + 1
                        comps.hour = 0; comps.minute = 0; comps.second = 0; comps.nanosecond = 0
                        let nextMidnight = cal.date(from: comps) ?? now.addingTimeInterval(24*3600)
                        
                        print("🌙 🚇 [TransitVM] Fewer than 5 departures (\(all.count)). Fetching after-midnight window starting \(nextMidnight)…")
                        await withCheckedContinuation { innerCont in
                            self.fetchDepartures(for: stop, when: nextMidnight) { more in
                                all.append(contentsOf: more)
                                innerCont.resume()
                            }
                        }
                        self.midnightMergeDoneForStop.insert(key)
                    }
                    
                    // Keep only future departures from now
                    let now = Date()
                    all = all.filter { (($0.actualWhen ?? $0.plannedWhen) ?? .distantPast) >= now }
                    
                    // De-duplicate by tripId or (line+timestamp)
                    var uniq: [String: Departure] = [:]
                    for d in all {
                        let ts = (d.actualWhen ?? d.plannedWhen)?.timeIntervalSince1970 ?? 0
                        let key = d.tripId ?? "\(d.line.name)-\(ts)"
                        if uniq[key] == nil { uniq[key] = d }
                    }
                    
                    // Sort and keep top 10
                    let sorted = uniq.values.sorted {
                        let ta = ($0.actualWhen ?? $0.plannedWhen) ?? Date.distantFuture
                        let tb = ($1.actualWhen ?? $1.plannedWhen) ?? Date.distantFuture
                        return ta < tb
                    }
                    let nextTen = Array(sorted.prefix(10))
                    
                    await MainActor.run {
                        // Update departuresByStop dictionary
                        self.departuresByStop[key] = nextTen
                        print("🗂️ 🚇 [TransitVM] Stored \(nextTen.count)/\(sorted.count) departures (top 10, merged) under stop id=\(key)")
                        
                        // Update flat 'departures' list if this is the currently selected stop
                        if self.selectedStop?.id == stop.id {
                            self.departures = nextTen
                            print("🔢 🚇 [TransitVM] Updated flat list for selected stop.")
                        }
                    }
                    cont.resume()
                }
            }
        }
    }
    
    // Real departures fetching
    // NOTE: This uses an outdated completion handler structure inside an async environment.
    // It should ideally be converted fully to async/await, but for now we keep the structure.
    func fetchDepartures(for stop: Stop, when: Date? = nil, completion: (([Departure]) -> Void)? = nil) {
        print("🚇 [TransitVM] fetchDepartures called for stop: \(stop.name) (id: \(stop.id))" + (when != nil ? " (Mode: Midnight Merge)" : ""))
        
        guard var urlComponents = URLComponents(string: "\(apiBaseURL)/stops/\(stop.id)/departures") else {
            self.errorMessage = "Invalid departures URL."
            completion?([])
            return
        }
        urlComponents.queryItems = [
            URLQueryItem(name: "duration", value: "30"), // Increased duration for better results
            URLQueryItem(name: "results", value: "15"), // Increased results
            URLQueryItem(name: "remarks", value: "false"),
            URLQueryItem(name: "stopovers", value: "false")
        ]
        if let when = when {
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let whenStr = f.string(from: when)
            urlComponents.queryItems?.append(URLQueryItem(name: "when", value: whenStr))
        }
        guard let url = urlComponents.url else {
            self.errorMessage = "Failed to build departures URL."
            completion?([])
            return
        }
        print("🚇 [TransitVM] Departures URL: \(url.absoluteString)")
        
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                    print("❌ 🚇 [TransitVM] Departures failed with HTTP Status Code: \(statusCode)")
                    if let errorBody = String(data: data, encoding: .utf8) {
                        print("❌ 🚇 [TransitVM] Departures error body: \(errorBody.prefix(1000)))")
                    }
                    await MainActor.run { [weak self] in
                        self?.errorMessage = "Departures request failed (Status \(statusCode))"
                        completion?([])
                    }
                    return
                }
                
                let decoder = JSONDecoder()
                // Accept ISO-8601 with and without fractional seconds
                let isoWithMs = ISO8601DateFormatter()
                isoWithMs.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let isoNoMs = ISO8601DateFormatter()
                isoNoMs.formatOptions = [.withInternetDateTime]
                decoder.dateDecodingStrategy = .custom { decoder in
                    let c = try decoder.singleValueContainer()
                    let s = try c.decode(String.self)
                    if let d = isoWithMs.date(from: s) ?? isoNoMs.date(from: s) { return d }
                    throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported ISO-8601 date: \(s)")
                }
                
                // Accept both object {departures:[...]} and bare array [...]
                var apiDepartures: [APIDeparture]
                do {
                    let resp = try decoder.decode(APIDeparturesResponse.self, from: data)
                    apiDepartures = resp.departures
                } catch let objErr {
                    do {
                        apiDepartures = try decoder.decode([APIDeparture].self, from: data)
                    } catch let arrErr {
                        if let raw = String(data: data, encoding: .utf8) {
                            print("❌ 🚇 [TransitVM] Decoding failed as object & array. objErr=\(objErr), arrErr=\(arrErr)\nRAW: \(raw.prefix(1200))")
                        } else {
                            print("❌ 🚇 [TransitVM] Decoding failed (non-UTF8). objErr=\(objErr), arrErr=\(arrErr)")
                        }
                        await MainActor.run { [weak self] in
                            self?.errorMessage = "Departures: Unexpected response format"
                        }
                        completion?([])
                        return
                    }
                }
                
                let mapped: [Departure] = apiDepartures.map { d in
                    let systemIcon = productToSystemIconName(d.line.product)
                    let line = Line(name: d.line.name, systemIconName: systemIcon)
                    
                    var minutes: Int? = nil
                    if let when = d.when ?? d.plannedWhen {
                        minutes = Int(max(0, when.timeIntervalSinceNow / 60.0))
                    }
                    
                    return Departure(
                        line: line,
                        plannedWhen: d.plannedWhen,
                        actualWhen: d.when,
                        delay: d.delay.map { TimeInterval($0) },
                        minutesUntilDeparture: minutes,
                        direction: d.direction,
                        stopId: stop.id,
                        tripId: d.tripId
                    )
                }
                print("🧾 🚇 [TransitVM] Mapped departures for stop \(stop.name) (id: \(stop.id)): total=\(mapped.count)")
                let sample = mapped.prefix(5).map { "\($0.line.name)→\($0.direction ?? "—") @ \($0.timeString) (\($0.minutesUntilDeparture ?? -1)m)" }.joined(separator: " | ")
                print("🧾 🚇 [TransitVM] Sample (top 5): \(sample)")
                
                await MainActor.run {
                    // FIX: Fehlermeldung bei erfolgreichem Fetch löschen
                    self.errorMessage = nil
                    
                    // Mark time of the last successful API fetch
                    self.lastUpdated = Date()
                    // WICHTIGE ÄNDERUNG: Die Aktualisierung von self.departures wurde entfernt.
                    completion?(mapped)
                }
            } catch {
                if Task.isCancelled { return }
                print("❌ 🚇 [TransitVM] Departures error: \(error.localizedDescription)")
                await MainActor.run { [weak self] in
                    self?.errorMessage = "Network error (departures): \(error.localizedDescription)"
                }
                completion?([])
            }
        }
    }
    
    func fetchDepartures(for stop: Stop, completion: (([Departure]) -> Void)? = nil) {
        fetchDepartures(for: stop, when: nil, completion: completion)
    }
    deinit {
        locationCancellable?.cancel()
        minuteTimer?.cancel()
        refreshTimer?.cancel()
        departuresRefreshTimer?.cancel()
        infrequentLocationTimer?.cancel()
        fallbackLocationTimer5s?.invalidate()
        fallbackLocationTimer10s?.invalidate()
    }
}

// MARK: - Models expected by TransitTileView
struct Stop: Identifiable, Hashable, Decodable {
    // DB/HAFAS stop ID is a string (e.g., EVA/IBNR like "8010159")
    let id: String
    let name: String
}

struct Line: Hashable {
    let name: String
    let systemIconName: String // e.g., "tram.fill"
}
struct Departure: Identifiable, Hashable {
    let id = UUID()
    let line: Line
    let plannedWhen: Date?
    var actualWhen: Date?
    var delay: TimeInterval?
    var minutesUntilDeparture: Int?
    var direction: String?
    var stopId: String?
    var tripId: String?
    
    // NEU: Berechnete Eigenschaft, um anzuzeigen, ob eine Verspätung vorliegt.
    var isDelayed: Bool {
        // delay ist die Verspätung in Sekunden (TimeInterval).
        // Wir prüfen, ob die Verspätung positiv ist.
        return (delay ?? 0) > 0.0
    }
    
    var timeString: String {
        let d = actualWhen ?? plannedWhen
        guard let d else { return "--:--" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE_POSIX")
        f.timeZone = .current
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
    
    // FIX: Hinzufügen von plannedTimeString, um den Fehler in TransitTileView.swift zu beheben.
    var plannedTimeString: String {
        guard let d = plannedWhen else { return "--:--" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE_POSIX")
        f.timeZone = .current
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
    
    // NEU: tatsächliche Zeit als String (wird in TransitTileView erwartet, falls actualWhen != nil)
    var actualTimeString: String {
        guard let d = actualWhen else { return "--:--" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE_POSIX")
        f.timeZone = .current
        f.dateFormat = "HH:mm"
        return f.string(from: d)
    }
    
    // NEU: Minuten bis zur geplanten Abfahrt (wird in TransitTileView erwartet)
    var plannedMinutesUntilDeparture: Int? {
        guard let planned = plannedWhen else { return nil }
        let now = Date()
        return Int(max(0, planned.timeIntervalSince(now) / 60.0))
    }
    
    // Offset der Verspätung in Minuten; positiv = verspätet, negativ = verfrüht
    var delayMinutesOffset: Int? {
        if let actual = actualWhen, let planned = plannedWhen {
            return Int(round(actual.timeIntervalSince(planned) / 60.0))
        }
        if let d = delay { return Int(round(d / 60.0)) }
        return nil
    }
    
    // Kompakte Darstellung wie "+3" oder "-1"; leer bei 0 oder unbekannt
    var delayOffsetLabel: String {
        guard let off = delayMinutesOffset, off != 0 else { return "" }
        return String(format: "%+d", off)
    }
}
