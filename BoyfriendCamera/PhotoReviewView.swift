import SwiftUI
import Photos

struct PhotoReviewView: View {
    @Environment(\.dismiss) var dismiss
    @State private var assets: [PHAsset] = []
    @State private var selectedIndex: Int = 0
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if assets.isEmpty {
                VStack {
                    ProgressView().tint(.white)
                    Text("Loading Album...")
                        .foregroundColor(.gray)
                        .font(.caption)
                }
            } else {
                // SWIPEABLE GALLERY
                TabView(selection: $selectedIndex) {
                    ForEach(0..<assets.count, id: \.self) { index in
                        // We map the index directly.
                        // Note: Assets are usually sorted Oldest -> Newest.
                        let asset = assets[index]
                        AssetImageView(asset: asset)
                            .tag(index)
                            .pinchToZoom()
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
            }

            // TOP CONTROLS (Counter & Close)
            VStack {
                HStack {
                    // Counter (e.g. 5/120)
                    if !assets.isEmpty {
                        Text("\(selectedIndex + 1) / \(assets.count)")
                            .font(.footnote.monospacedDigit())
                            .foregroundColor(.white.opacity(0.7))
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .cornerRadius(6)
                    }
                    
                    Spacer()
                    
                    // Close Button
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 30))
                            .foregroundColor(.gray)
                            .padding()
                    }
                }
                Spacer()
            }
        }
        .onAppear {
            fetchPhotos()
        }
    }
    
    private func fetchPhotos() {
        DispatchQueue.global(qos: .userInitiated).async {
            let albumName = "Boyfriend Camera"
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
            
            // 1. Find the Album
            let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
            
            if let album = collection.firstObject {
                // 2. Fetch Assets from Album
                let assetsOptions = PHFetchOptions()
                // Sort by creation date so newest is at the end
                assetsOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
                
                let result = PHAsset.fetchAssets(in: album, options: assetsOptions)
                var allAssets: [PHAsset] = []
                
                // Convert fetch result to array
                result.enumerateObjects { asset, _, _ in
                    allAssets.append(asset)
                }
                
                DispatchQueue.main.async {
                    self.assets = allAssets
                    // Jump to the last photo (the new one)
                    if !allAssets.isEmpty {
                        self.selectedIndex = allAssets.count - 1
                    }
                }
            }
        }
    }
}

// Helper: Loads a UIImage from a PHAsset efficiently
struct AssetImageView: View {
    let asset: PHAsset
    @State private var image: UIImage?
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    ProgressView()
                }
            }
            .onAppear {
                loadImage(targetSize: geo.size)
            }
        }
    }
    
    private func loadImage(targetSize: CGSize) {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true // Allow iCloud download
        
        // Request a slightly larger image for sharpness on Retina screens
        let scale = UIScreen.main.scale
        let size = CGSize(width: targetSize.width * scale, height: targetSize.height * scale)
        
        manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFit, options: options) { result, _ in
            self.image = result
        }
    }
}

// Helper: Pinch Zoom Logic
struct PinchToZoomModifier: ViewModifier {
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { val in
                        let delta = val / lastScale
                        lastScale = val
                        scale *= delta
                    }
                    .onEnded { _ in
                        lastScale = 1.0
                        withAnimation {
                            if scale < 1.0 { scale = 1.0 }
                        }
                    }
            )
    }
}

extension View {
    func pinchToZoom() -> some View {
        modifier(PinchToZoomModifier())
    }
}
