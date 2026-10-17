import Combine
import CoreLocation
import Foundation

/// Answers "where am I?" with one spoken sentence. Asks for permission the first time,
/// takes a single fix, and reverse geocodes it. Never crashes when the Simulator has no location.
@MainActor
final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// The last street-level description, kept for the emergency message.
    @Published private(set) var lastKnownDescription: String?

    static let timeoutSeconds: Double = 10
    static let demoLandmarks = "In demo mode, nearby landmarks would be: a pharmacy on your right and a bus stop ahead."
    static let deniedMessage = "Location is turned off for ECHO. You can turn it on in Settings."

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    private var authorizationContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?
    private var locationContinuation: CheckedContinuation<CLLocation?, Never>?
    private var authorizationTimeout: Task<Void, Never>?
    private var locationTimeout: Task<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    // MARK: - Public

    /// One or two plain sentences saying where the user is, or why ECHO could not find out.
    func whereAmI() async -> String {
        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await requestAuthorization()
        }

        switch status {
        case .denied, .restricted:
            return Self.deniedMessage
        case .notDetermined:
            return "I did not get an answer about location permission. Please try again, or turn on location for ECHO in Settings."
        case .authorizedAlways, .authorizedWhenInUse:
            break
        @unknown default:
            return Self.deniedMessage
        }

        guard let location = await requestOneLocation() else {
            return "I could not find your location right now. Please try again in a moment. \(Self.demoLandmarks)"
        }

        let place = await describe(location)
        lastKnownDescription = place
        return "You are near \(place). \(Self.demoLandmarks)"
    }

    // MARK: - Permission

    private func requestAuthorization() async -> CLAuthorizationStatus {
        if let pending = authorizationContinuation {
            // A previous request is still waiting; do not stack another one.
            authorizationContinuation = nil
            pending.resume(returning: .notDetermined)
        }
        return await withCheckedContinuation { continuation in
            authorizationContinuation = continuation
            authorizationTimeout?.cancel()
            authorizationTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.timeoutSeconds * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.finishAuthorization(with: self.manager.authorizationStatus)
            }
            manager.requestWhenInUseAuthorization()
        }
    }

    private func finishAuthorization(with status: CLAuthorizationStatus) {
        authorizationTimeout?.cancel()
        authorizationTimeout = nil
        guard let continuation = authorizationContinuation else { return }
        authorizationContinuation = nil
        continuation.resume(returning: status)
    }

    // MARK: - One location fix

    private func requestOneLocation() async -> CLLocation? {
        if let pending = locationContinuation {
            locationContinuation = nil
            pending.resume(returning: nil)
        }
        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationTimeout?.cancel()
            locationTimeout = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.timeoutSeconds * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.finishLocation(with: nil)
            }
            manager.requestLocation()
        }
    }

    private func finishLocation(with location: CLLocation?) {
        locationTimeout?.cancel()
        locationTimeout = nil
        guard let continuation = locationContinuation else { return }
        locationContinuation = nil
        continuation.resume(returning: location)
    }

    // MARK: - Geocoding

    /// "12 Maple Street, Springfield", falling back to whatever the placemark offers, or coordinates.
    private func describe(_ location: CLLocation) async -> String {
        let placemark = try? await geocoder.reverseGeocodeLocation(location).first
        var street = [placemark?.subThoroughfare, placemark?.thoroughfare]
            .compactMap { $0 }
            .joined(separator: " ")
        if street.isEmpty {
            street = placemark?.name ?? ""
        }
        let town = placemark?.locality ?? placemark?.subAdministrativeArea ?? placemark?.administrativeArea ?? ""

        let parts = [street, town].filter { !$0.isEmpty }
        if !parts.isEmpty {
            return parts.joined(separator: ", ")
        }
        let lat = location.coordinate.latitude.formatted(.number.precision(.fractionLength(3)))
        let lon = location.coordinate.longitude.formatted(.number.precision(.fractionLength(3)))
        return "latitude \(lat), longitude \(lon)"
    }

    // MARK: - CLLocationManagerDelegate (called off the main actor)

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        Task { @MainActor in
            self.finishAuthorization(with: status)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let latest = locations.last
        Task { @MainActor in
            self.finishLocation(with: latest)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.finishLocation(with: nil)
        }
    }
}
