import SwiftUI
import CoreLocation
import AVFoundation

// Helper for Aspect Ratios
enum AspectRatio: String, CaseIterable {
    case fourThree = "4:3"
    case sixteenNine = "16:9"
    case square = "1:1"
    
    var value: CGFloat {
        switch self {
        case .fourThree: return 4.0 / 3.0
        case .sixteenNine: return 16.0 / 9.0
        case .square: return 1.0
        }
    }
}

struct ContentView: View {
    @StateObject var cameraManager = CameraManager()
    @StateObject var locationManager = LocationManager()
    let smoother = CompassSmoother()
    
    @State var currentAdvice: DirectorAdvice?
    @State private var showMap = false
    
    // NEW: UI States for your requested features
    @State private var currentAspectRatio: AspectRatio = .fourThree
    @State private var currentZoom: CGFloat = 1.0
    @State private var showFlashAnimation = false
    
    // Target: The Campanile (Change to test!)
    @State var targetLandmark = Landmark(
        name: "The Campanile",
        coordinate: CLLocationCoordinate2D(latitude: 37.8720, longitude: -122.2578)
    )
    
    // Helper for Map binding
    var targetLandmarkBinding: Binding<MapLandmark> {
        Binding(
            get: { MapLandmark(name: targetLandmark.name, coordinate: targetLandmark.coordinate) },
            set: { new in targetLandmark = Landmark(name: new.name, coordinate: new.coordinate) }
        )
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                // --- LAYER 1: CAMERA (With Aspect Ratio) ---
                GeometryReader { geo in
                    let ratio = currentAspectRatio.value
                    let height = geo.size.width * ratio
                    
                    CameraPreview(cameraManager: cameraManager)
                        .frame(width: geo.size.width, height: height)
                        .clipped()
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                }
                .ignoresSafeArea(.all, edges: .top)
                
                // --- LAYER 2: OVERLAYS ---
                if let advice = currentAdvice {
                    FloatingTargetView(
                        angleDiff: advice.turnAngle,
                        isLocked: abs(advice.turnAngle) < 3
                    )
                }
                
                // --- LAYER 3: CONTROLS ---
                VStack {
                    // TOP BAR
                    HStack {
                        // GPS Status
                        Circle().fill(locationManager.permissionGranted ? Color.green : Color.red).frame(width: 8, height: 8)
                        Text(locationManager.permissionGranted ? "GPS ONLINE" : "OFFLINE")
                            .font(.caption2).bold().foregroundColor(.white)
                            .padding(4).background(.ultraThinMaterial).cornerRadius(4)
                        
                        Spacer()
                        
                        // Aspect Ratio Toggle
                        Button {
                            toggleAspectRatio()
                        } label: {
                            Text(currentAspectRatio.rawValue)
                                .font(.footnote.bold()).foregroundColor(.white)
                                .padding(8).background(.ultraThinMaterial).clipShape(Capsule())
                        }
                        
                        // Flip Camera
                        Button {
                            cameraManager.switchCamera()
                            currentZoom = 1.0 // Reset zoom
                        } label: {
                            Image(systemName: "camera.rotate.fill")
                                .font(.headline).foregroundColor(.white)
                                .padding(8).background(.ultraThinMaterial).clipShape(Circle())
                        }
                    }
                    .padding(.top, 50).padding(.horizontal)
                    
                    Spacer()
                    
                    // BOTTOM BAR
                    VStack(spacing: 20) {
                        
                        // Scope
                        if let advice = currentAdvice {
                            ScopeView(advice: advice)
                        } else {
                            Text("Calibrating...").font(.headline).foregroundColor(.white).padding().background(.ultraThinMaterial).cornerRadius(15)
                        }
                        
                        // Zoom Controls
                        HStack(spacing: 20) {
                            ZoomButton(label: "0.5x", factor: 0.5, currentZoom: $currentZoom, action: cameraManager.zoom)
                            ZoomButton(label: "1x", factor: 1.0, currentZoom: $currentZoom, action: cameraManager.zoom)
                            ZoomButton(label: "2x", factor: 2.0, currentZoom: $currentZoom, action: cameraManager.zoom)
                        }
                        .padding(10).background(.ultraThinMaterial).clipShape(Capsule())
                        
                        // Footer Actions
                        HStack {
                            // Map
                            Button { showMap = true } label: {
                                Image(systemName: "map.fill")
                                    .font(.title2).foregroundColor(.white).padding(15)
                                    .background(.ultraThinMaterial).clipShape(Circle())
                            }
                            
                            Spacer()
                            
                            // SHUTTER BUTTON (Large)
                            Button {
                                takePhoto()
                            } label: {
                                ZStack {
                                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 70, height: 70)
                                    Circle().fill(.white).frame(width: 60, height: 60)
                                }
                            }
                            
                            Spacer()
                            
                            // Placeholder (keeps shutter centered)
                            Color.clear.frame(width: 60, height: 60)
                        }
                        .padding(.horizontal, 30).padding(.bottom, 30)
                    }
                }
                
                // --- LAYER 4: ANIMATIONS ---
                if locationManager.isInterferenceHigh {
                    CalibrationView().transition(.opacity).zIndex(100)
                }
                if showFlashAnimation {
                    Color.white.ignoresSafeArea().transition(.opacity).zIndex(200)
                }
            }
            .navigationDestination(isPresented: $showMap) {
                MapScreen(locationManager: locationManager, landmark: targetLandmarkBinding)
            }
            .onReceive(locationManager.$heading) { _ in updateNavigationLogic() }
            .onReceive(locationManager.$location) { _ in updateNavigationLogic() }
        }
    }
    
    // MARK: - Logic
    
    func toggleAspectRatio() {
        let allCases = AspectRatio.allCases
        if let currentIndex = allCases.firstIndex(of: currentAspectRatio) {
            let nextIndex = (currentIndex + 1) % allCases.count
            currentAspectRatio = allCases[nextIndex]
        }
    }
    
    func takePhoto() {
        // 1. Flash Animation
        withAnimation(.easeOut(duration: 0.1)) { showFlashAnimation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeIn(duration: 0.2)) { showFlashAnimation = false }
        }
        
        // 2. Call Manager (Pass location!)
        cameraManager.capturePhoto(location: locationManager.location)
    }
    
    func updateNavigationLogic() {
        guard let userLoc = locationManager.location,
              let rawHeading = locationManager.heading?.trueHeading else { return }
        
        let smoothHeading = smoother.smooth(rawHeading)
        var newAdvice = PhotoDirector.guideToLandmark(
            userHeading: smoothHeading,
            userLocation: userLoc.coordinate,
            target: targetLandmark
        )
        
        if abs(newAdvice.turnAngle) < 3 {
            newAdvice = DirectorAdvice(message: newAdvice.message, icon: newAdvice.icon, isUrgent: newAdvice.isUrgent, lightingScore: newAdvice.lightingScore, turnAngle: 0)
        }
        withAnimation(.linear(duration: 0.1)) { self.currentAdvice = newAdvice }
    }
}

// Helper Button
struct ZoomButton: View {
    let label: String
    let factor: CGFloat
    @Binding var currentZoom: CGFloat
    let action: (CGFloat) -> Void
    
    var body: some View {
        Button {
            currentZoom = factor
            action(factor)
        } label: {
            Text(label)
                .font(.footnote.bold())
                .foregroundColor(currentZoom == factor ? .yellow : .white)
                .padding(8)
                .background(currentZoom == factor ? Color.white.opacity(0.2) : Color.clear)
                .clipShape(Circle())
        }
    }
}

#Preview {
    ContentView()
}
