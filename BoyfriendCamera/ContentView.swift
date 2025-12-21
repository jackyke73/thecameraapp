import SwiftUI
import CoreLocation
import Darwin // Required for device detection (utsname)

// MARK: - Helper Enums
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

// MARK: - Main View
struct ContentView: View {
    // Managers
    @StateObject var cameraManager = CameraManager()
    @StateObject var locationManager = LocationManager()
    let smoother = CompassSmoother() // Assuming this exists in your project
    
    // MARK: - Device / Zoom Presets Logic
    struct DeviceZoomPresets {
        // Lightweight device identifier lookup
        private static func deviceIdentifier() -> String {
            var systemInfo = utsname()
            uname(&systemInfo)
            let mirror = Mirror(reflecting: systemInfo.machine)
            let identifier = mirror.children.reduce("") { identifier, element in
                guard let value = element.value as? Int8, value != 0 else { return identifier }
                return identifier + String(UnicodeScalar(UInt8(value)))
            }
            return identifier
        }

        // Logic to detect Ultra Wide support (iPhone 11+, excluding SE)
        static func supportsUltraWide() -> Bool {
            let id = deviceIdentifier()
            if id.contains("iPhone SE") { return false }
            if id.hasPrefix("iPhone") {
                let parts = id.dropFirst("iPhone".count).split(separator: ",")
                if let majorPart = parts.first, let major = Int(majorPart) {
                    return major >= 12 // iPhone 12,1 is iPhone 11
                }
            }
            return true // Default to true for Simulator/Newer
        }

        static func availableZoomFactors() -> [CGFloat] {
            var desired: [CGFloat] = [1.0, 2.0, 5.0] // Apple style 1, 2, 5 usually
            if supportsUltraWide() {
                desired.insert(0.5, at: 0)
            }
            return desired
        }
    }

    // State
    @State private var zoomPresets: [CGFloat] = DeviceZoomPresets.availableZoomFactors()
    @State private var currentAdvice: DirectorAdvice? // Assuming DirectorAdvice exists
    @State private var showMap = false
    @State private var showFlashAnimation = false
    @State private var isCapturing = false
    
    // Zoom UI State
    @State private var isZoomDialPresented = false
    @State private var currentAspectRatio: AspectRatio = .fourThree
    
    // Target Landmark
    @State var targetLandmark = Landmark(name: "The Campanile", coordinate: CLLocationCoordinate2D(latitude: 37.8720, longitude: -122.2578))
    
    // Binding for MapScreen
    var targetLandmarkBinding: Binding<MapLandmark> {
        Binding(
            get: { MapLandmark(name: targetLandmark.name, coordinate: targetLandmark.coordinate) },
            set: { new in targetLandmark = Landmark(name: new.name, coordinate: new.coordinate) }
        )
    }
    
    // MARK: - Body
    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                // 1. Configure Presets on Load
                Color.clear.frame(width: 0, height: 0)
                    .onAppear { configureZoomPresets() }
                
                // 2. Camera Preview (Masked)
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = w * currentAspectRatio.value
                    
                    CameraPreview(cameraManager: cameraManager)
                        .frame(width: w, height: h)
                        .clipped()
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                        // Pinch to Zoom
                        .gesture(
                            MagnificationGesture()
                                .onChanged { val in
                                    let newZoom = cameraManager.currentZoomFactor * val
                                    cameraManager.setZoom(newZoom)
                                }
                        )
                        // Tap to focus could go here
                }
                .ignoresSafeArea()
                
                // 3. Overlays (AR/Advice)
                if let advice = currentAdvice {
                    FloatingTargetView(angleDiff: advice.turnAngle, isLocked: abs(advice.turnAngle) < 3)
                }
                
                // 4. UI Layer
                VStack {
                    // --- TOP BAR ---
                    HStack {
                        // GPS Status Pill
                        HStack(spacing: 6) {
                            Circle()
                                .fill(locationManager.permissionGranted ? Color.green : Color.red)
                                .frame(width: 6, height: 6)
                            Text(locationManager.permissionGranted ? "GPS" : "NO GPS")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.4))
                        .cornerRadius(12)
                        
                        Spacer()
                        
                        // Aspect Ratio Toggle
                        Button {
                            toggleAspectRatio()
                        } label: {
                            Text(currentAspectRatio.rawValue)
                                .font(.footnote.bold())
                                .foregroundColor(.white)
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
                    }
                    .padding(.top, 50)
                    .padding(.horizontal)
                    
                    Spacer()
                    
                    // --- ADVICE PILL ---
                    if let advice = currentAdvice {
                        ScopeView(advice: advice).padding(.bottom, 10)
                    }
                    
                    // --- ZOOM CONTROLS (Apple Style) ---
                    // This section swaps between the presets and the ruler
                    VStack(spacing: 0) {
                        ZStack(alignment: .bottom) {
                            
                            // A. The Dial (The Ruler)
                            if isZoomDialPresented {
                                ZoomDialView(
                                    zoomFactor: Binding(
                                        get: { cameraManager.currentZoomFactor },
                                        set: { cameraManager.setZoom($0) }
                                    ),
                                    minZoom: cameraManager.minZoomFactor,
                                    maxZoom: cameraManager.maxZoomFactor
                                )
                                .frame(height: 50)
                                .padding(.bottom, 10)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                                .zIndex(2) // Ensure it sits on top
                            }
                            
                            // B. The Presets (0.5, 1, 2, 5)
                            // Hidden when dial is present
                            if !isZoomDialPresented {
                                HStack(spacing: 20) {
                                    ForEach(zoomPresets, id: \.self) { preset in
                                        ZoomPresetButton(
                                            value: preset,
                                            currentZoom: cameraManager.currentZoomFactor,
                                            action: {
                                                // Tap: Snap to zoom
                                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                    cameraManager.setZoom(preset)
                                                }
                                            },
                                            longPressAction: {
                                                // Long Press: Engage Dial
                                                engageDial()
                                            }
                                        )
                                    }
                                }
                                .padding(.bottom, 20)
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                                .zIndex(1)
                            } else {
                                // When dial is open, show the "Active Zoom" readout button
                                // that allows closing the dial
                                Button {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        isZoomDialPresented = false
                                    }
                                } label: {
                                    Text(labelForZoom(cameraManager.currentZoomFactor))
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(.yellow)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 12)
                                        .background(Capsule().fill(Color.black.opacity(0.5)))
                                }
                                .padding(.bottom, 80) // Push it up above the dial
                                .zIndex(3)
                            }
                        }
                    }
                    
                    // --- BOTTOM SHUTTER AREA ---
                    HStack {
                        // Map Button
                        Button { showMap = true } label: {
                            Image(systemName: "map.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                                .frame(width: 44, height: 44)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        
                        Spacer()
                        
                        // Shutter Button
                        Button { takePhoto() } label: {
                            ZStack {
                                Circle()
                                    .stroke(.white, lineWidth: 4)
                                    .frame(width: 72, height: 72)
                                Circle()
                                    .fill(.white)
                                    .frame(width: 62, height: 62)
                                    .scaleEffect(isCapturing ? 0.85 : 1.0)
                            }
                        }
                        
                        Spacer()
                        
                        // Spacer for balance
                        Color.clear.frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 40)
                }
                
                // 5. Flash Animation
                if showFlashAnimation {
                    Color.white.ignoresSafeArea()
                        .transition(.opacity)
                        .zIndex(100)
                }
            }
            .navigationDestination(isPresented: $showMap) {
                MapScreen(locationManager: locationManager, landmark: targetLandmarkBinding)
            }
            .onReceive(locationManager.$heading) { _ in updateNavigationLogic() }
            .onReceive(locationManager.$location) { _ in updateNavigationLogic() }
            .onReceive(cameraManager.captureDidFinish) { _ in isCapturing = false }
            // Tap background to dismiss dial
            .onTapGesture {
                if isZoomDialPresented {
                    withAnimation { isZoomDialPresented = false }
                }
            }
        }
    }
    
    // MARK: - Logic & Helpers
    
    func engageDial() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.prepare()
        generator.impactOccurred()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            isZoomDialPresented = true
        }
    }
    
    func configureZoomPresets() {
        let minZ = cameraManager.minZoomFactor
        let maxZ = cameraManager.maxZoomFactor
        let desired = DeviceZoomPresets.availableZoomFactors()
        
        // Filter presets to what the current camera actually supports
        var filtered: [CGFloat] = []
        for z in desired {
            // Include 0.5x only if supported, otherwise standard check
            if abs(z - 0.5) < 0.001 {
                if DeviceZoomPresets.supportsUltraWide() { filtered.append(0.5) }
            } else if z >= minZ && z <= maxZ {
                filtered.append(z)
            }
        }
        
        if !filtered.isEmpty {
            zoomPresets = filtered
        } else {
            zoomPresets = [minZ, maxZ].sorted()
        }
    }
    
    func labelForZoom(_ value: CGFloat) -> String {
        if abs(value - 0.5) < 0.01 { return ".5" } // Apple style drops the 'x' usually in the button
        if abs(value.rounded() - value) < 0.01 { return "\(Int(value))" }
        return String(format: "%.1f", value)
    }
    
    func toggleAspectRatio() {
        let allCases = AspectRatio.allCases
        if let currentIndex = allCases.firstIndex(of: currentAspectRatio) {
            let nextIndex = (currentIndex + 1) % allCases.count
            currentAspectRatio = allCases[nextIndex]
        }
    }
    
    func takePhoto() {
        isCapturing = true
        withAnimation(.easeOut(duration: 0.1)) { showFlashAnimation = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation { showFlashAnimation = false }
        }
        cameraManager.capturePhoto(location: locationManager.location, aspectRatioValue: currentAspectRatio.value)
    }
    
    func updateNavigationLogic() {
        guard let userLoc = locationManager.location,
              let rawHeading = locationManager.heading?.trueHeading else { return }
        
        let smooth = smoother.smooth(rawHeading)
        let advice = PhotoDirector.guideToLandmark(
            userHeading: smooth,
            userLocation: userLoc.coordinate,
            target: targetLandmark
        )
        withAnimation { currentAdvice = advice }
    }
}

// MARK: - Subview: Zoom Preset Button
struct ZoomPresetButton: View {
    let value: CGFloat
    let currentZoom: CGFloat
    let action: () -> Void
    let longPressAction: () -> Void
    
    var isSelected: Bool {
        abs(currentZoom - value) < 0.2
    }
    
    var label: String {
        if abs(value - 0.5) < 0.01 { return ".5" }
        return "\(Int(value))"
    }
    
    var body: some View {
        Button {
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 40, height: 40)
                
                if isSelected {
                    Circle()
                        .stroke(Color.yellow, lineWidth: 1.5) // Thin yellow ring for active
                        .frame(width: 48, height: 48) // Floating outside
                        .scaleEffect(1.0)
                }
                
                Text(label)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundColor(isSelected ? .yellow : .white)
                
                // Tiny "x" suffix
                Text("x")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(isSelected ? .yellow : .white)
                    .offset(x: 10, y: 4)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .onEnded { _ in longPressAction() }
        )
    }
}
