import SwiftUI
import CoreLocation

struct ContentView: View {
    @StateObject var cameraManager = CameraManager()
    @StateObject var locationManager = LocationManager()
    
    // This state holds the current advice from the Director
    @State var currentAdvice: DirectorAdvice?
    
    var body: some View {
        ZStack {
            // 1. Camera Feed
            CameraPreview(cameraManager: cameraManager)
                .ignoresSafeArea()
            
            // 2. The Director Interface
            VStack {
                Spacer()
                
                // Only show advice if we have GPS data
                if let advice = currentAdvice {
                    DirectorHUD(advice: advice)
                        .padding(.bottom, 50)
                } else {
                    Text("Acquiring GPS Signal...")
                        .font(.caption)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(10)
                        .padding(.bottom, 50)
                }
            }
        }
        // This logic runs 30 times a second (or whenever sensors change)
        .onReceive(locationManager.$heading) { _ in
            updateAdvice()
        }
        .onReceive(locationManager.$location) { _ in
            updateAdvice()
        }
    }
    
    func updateAdvice() {
        guard let loc = locationManager.location else { return }
        
        // 1. Calculate Sun
        let sunPos = SunCalculator.compute(date: Date(), coordinate: loc.coordinate)
        
        // 2. Ask the Director for advice
        let advice = PhotoDirector.evaluate(
            sunPosition: sunPos,
            deviceHeading: locationManager.heading,
            isPersonDetected: cameraManager.isPersonDetected
        )
        
        // 3. Update the UI
        self.currentAdvice = advice
    }
}
