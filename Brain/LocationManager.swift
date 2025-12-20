import Foundation
import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    
    // These hold your live data. "Optional" (?) because we might not have a signal yet.
    @Published var location: CLLocation?
    @Published var heading: CLHeading?
    @Published var permissionGranted = false
    
    private let locationManager = CLLocationManager()
    
    override init() {
        super.init()
        locationManager.delegate = self
        
        // Settings for accuracy
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        
        // We start asking immediately
        requestPermission()
    }
    
    func requestPermission() {
        locationManager.requestWhenInUseAuthorization()
    }
    
    func startUpdates() {
        if locationManager.authorizationStatus == .authorizedWhenInUse ||
           locationManager.authorizationStatus == .authorizedAlways {
            
            locationManager.startUpdatingLocation()
            locationManager.startUpdatingHeading() // Critical for knowing where "North" is
        }
    }
    
    // MARK: - Delegate Methods (The GPS talks back to us here)
    
    // 1. New Permission Status
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            self.permissionGranted = true
            startUpdates()
        } else {
            self.permissionGranted = false
        }
    }
    
    // 2. New Location Data (Lat/Long)
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        self.location = latest
    }
    
    // 3. New Compass Data (North/South)
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        self.heading = newHeading
    }
    
    // 4. Error Handling
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location Error: \(error.localizedDescription)")
    }
    
    
}
