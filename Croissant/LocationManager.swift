import Foundation
import CoreLocation
import MapKit
import Combine

// Struktur zur Speicherung der relevanten Standortdaten
struct UserLocation {
    let latitude: Double
    let longitude: Double
    let accuracy: Double // Meter
}

final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    private var locationManager: CLLocationManager?

    // Veröffentlichte Zustände
    @Published var authorizationStatus: CLAuthorizationStatus?
    @Published var currentLocation: UserLocation?
    @Published var locationError: Error?
    @Published var isLoading = false

    private var isAwaitingLocationUpdate = false

    override init() {
        super.init()
        self.locationManager = CLLocationManager()
        self.locationManager?.delegate = self
        self.locationManager?.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.authorizationStatus = locationManager?.authorizationStatus

        print("🌍 [LocationManager] Initializing manager.")
        print("🌍 [LocationManager] Initial authorization status: \(authorizationStatusString(for: authorizationStatus ?? .notDetermined))")
        print("🌍 [LocationManager] Manager initialized.")
    }

    deinit { print("🔥 [LocationManager] DEINIT (destroyed)") }

    // MARK: - Authorization
    func requestLocationAuthorization() {
        print("🌍 [LocationManager] Requesting location authorization (Always).")
        print("🌍 [LocationManager] Current authorization status before requesting: \(authorizationStatusString(for: authorizationStatus ?? .notDetermined))")
        locationManager?.requestAlwaysAuthorization()
    }

    private func isAuthorized(status: CLAuthorizationStatus?) -> Bool {
        guard let status = status else { return false }
        return status == .authorizedAlways
    }

    private func authorizationStatusString(for status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways: return "authorizedAlways"
        case .denied: return "denied"
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        @unknown default: return "unknown (\(status.rawValue))"
        }
    }

    // MARK: - Request Location
    func requestLocation() {
        print("🌍 [LocationManager] requestLocation() called.")
        guard let locationManager = self.locationManager else {
            print("🚨 [LocationManager] Fatal error: CLLocationManager instance is nil!")
            return
        }
        guard !isLoading else {
            print("🚫 🌍 [LocationManager] requestLocation() guard failed: isLoading == true.")
            return
        }
        guard !isAwaitingLocationUpdate else {
            print("🚫 🌍 [LocationManager] requestLocation() guard failed: isAwaitingLocationUpdate == true.")
            return
        }
        guard isAuthorized(status: authorizationStatus) else {
            print("🌍 [LocationManager] Not authorized yet. Requesting authorization…")
            requestLocationAuthorization()
            return
        }

        isLoading = true
        isAwaitingLocationUpdate = true
        print("🌍 [LocationManager] Requesting current location from CLLocationManager instance…")
        locationManager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        let oldStatus = authorizationStatus
        authorizationStatus = status
        print("🌍 [LocationManager] Authorization changed from \(authorizationStatusString(for: oldStatus ?? .notDetermined)) to \(authorizationStatusString(for: status))")

        let wasUnauthorized = !isAuthorized(status: oldStatus)
        let isNowAuthorized = isAuthorized(status: status)
        if isNowAuthorized && wasUnauthorized && currentLocation == nil {
            requestLocation()
        }

        switch status {
        case .denied, .restricted:
            locationError = NSError(domain: "LocationError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Location access denied."])
            isLoading = false
            isAwaitingLocationUpdate = false
            currentLocation = nil
            print("🌍 [LocationManager] Location access denied or restricted.")
        case .notDetermined, .authorizedAlways:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        print("🌍 [LocationManager] didUpdateLocations called with \(locations.count) location(s).")
        for (index, location) in locations.enumerated() {
            print("🌍 [LocationManager] #\(index): Lat=\(location.coordinate.latitude), Lon=\(location.coordinate.longitude), Acc=\(location.horizontalAccuracy)m")
        }
        guard let location = locations.first else {
            isLoading = false
            isAwaitingLocationUpdate = false
            print("🚫 🌍 [LocationManager] Empty locations array.")
            return
        }
        DispatchQueue.main.async {
            self.currentLocation = UserLocation(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                accuracy: location.horizontalAccuracy
            )
            self.locationError = nil
            self.isLoading = false
            self.isAwaitingLocationUpdate = false
            print("✅ 🌍 [LocationManager] Location updated: Lat=\(location.coordinate.latitude), Lon=\(location.coordinate.longitude)")
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let nsError = error as NSError
        print("❌ [LocationManager] didFailWithError: \(error.localizedDescription) (Domain: \(nsError.domain), Code: \(nsError.code))")
        DispatchQueue.main.async {
            self.locationError = error
            self.isLoading = false
            self.isAwaitingLocationUpdate = false
        }
    }
}
