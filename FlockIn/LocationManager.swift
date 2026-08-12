import Foundation
import CoreLocation

@MainActor
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    /// How close a student must be to an event's coordinate to check in.
    ///
    /// 250m from the centre of the Sequoia campus covers the whole site; at the
    /// previous 200m the far edges fell outside the fence. It is a constant
    /// rather than a per-event field because the app is the only thing that can
    /// enforce it — the dashboard could offer a radius box, but nothing
    /// server-side reads it, so the number would not mean anything.
    ///
    /// Referenced by the on-screen copy in EventDetailView so the number a
    /// student is told matches the one actually applied.
    static let checkInRadiusMeters: CLLocationDistance = 250

    func isWithinCheckInRadius(of coordinate: CLLocationCoordinate2D) -> Bool {
        guard let location = currentLocation else { return false }
        let target = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return location.distance(from: target) <= Self.checkInRadiusMeters
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
}
