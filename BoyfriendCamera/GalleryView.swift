import SwiftUI
import ARKit
import Combine

/// A feature-rich photo gallery and 3D asset manager.
struct GalleryView: View {
    @Environment(\.dismiss) var dismiss
    
    // In a real app, this would be fetched from a PersistenceController (CoreData/SwiftData)
    // For the MVP, we simulate a library.
    @State private var assets: [MediaAsset] = [
        MediaAsset(type: .photo, title: "Portrait at Berkeley", date: Date().addingTimeInterval(-3600), thumbnail: "photo_sample_1"),
        MediaAsset(type: .splat, title: "Coffee Table Splat", date: Date().addingTimeInterval(-86400), points: 15420),
        MediaAsset(type: .photo, title: "Sunset Hero Shot", date: Date().addingTimeInterval(-172800), thumbnail: "photo_sample_2"),
        MediaAsset(type: .splat, title: "Nike Shoe 3D", date: Date().addingTimeInterval(-259200), points: 28900)
    ]
    
    @State private var selectedAsset: MediaAsset?
    @State private var isExporting = false
    
    let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 2) {
                        ForEach(assets) { asset in
                            AssetThumbnail(asset: asset)
                                .onTapGesture {
                                    selectedAsset = asset
                                }
                        }
                    }
                    .padding(.top, 10)
                }
            }
            .navigationTitle("LIBRARY")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Sort by Date", action: {})
                        Button("Photos Only", action: {})
                        Button("3D Assets Only", action: {})
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundColor(.yellow)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: $selectedAsset) { asset in
            AssetDetailView(asset: asset)
        }
    }
}

struct AssetThumbnail: View {
    let asset: MediaAsset
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Placeholder for real images
            Rectangle()
                .fill(Color(white: 0.15))
                .aspectRatio(1, contentMode: .fill)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: asset.type == .photo ? "camera.fill" : "cube.transparent.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white.opacity(0.3))
                        
                        if asset.type == .splat {
                            Text("\(asset.points / 1000)K PTS")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.yellow.opacity(0.8))
                        }
                    }
                )
            
            if asset.type == .splat {
                Image(systemName: "3d.circle.fill")
                    .foregroundColor(.yellow)
                    .padding(6)
            }
        }
        .clipped()
    }
}

struct AssetDetailView: View {
    let asset: MediaAsset
    @Environment(\.dismiss) var dismiss
    @State private var showShareSheet = false
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            if asset.type == .splat {
                // Reuse our high-fidelity renderer
                SplatPointRenderer(splatData: generateMockPoints(count: asset.points))
            } else {
                // Photo placeholder
                VStack {
                    Spacer()
                    Image(systemName: "photo")
                        .font(.system(size: 60))
                        .foregroundColor(.white.opacity(0.2))
                    Text(asset.title)
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                }
            }
            
            // Overlays
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    VStack {
                        Text(asset.title.uppercased())
                            .font(.system(size: 12, weight: .black))
                            .foregroundColor(.white)
                        Text(asset.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    
                    Spacer()
                    
                    Button(action: { showShareSheet = true }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.yellow)
                            .padding(12)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.top, 60)
                .padding(.horizontal)
                
                Spacer()
                
                if asset.type == .splat {
                    HStack(spacing: 20) {
                        ActionButton(icon: "arkit", label: "AR VIEW", color: .white)
                        ActionButton(icon: "arrow.down.circle.fill", label: "EXPORT PLY", color: .yellow)
                        ActionButton(icon: "trash", label: "DELETE", color: .red)
                    }
                    .padding(.bottom, 50)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: ["Check out this 3D Splat I captured with BoyfriendCamera!"])
        }
    }
    
    // Helper to generate visuals for stored assets without actual persistence yet
    func generateMockPoints(count: Int) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        for _ in 0..<min(count, 15000) {
            let x = Float.random(in: -0.5...0.5)
            let y = Float.random(in: -0.5...0.5)
            let z = Float.random(in: -0.5...0.5)
            points.append(SIMD3<Float>(x, y, z))
        }
        return points
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(color)
                .frame(width: 50, height: 50)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
            
            Text(label)
                .font(.system(size: 8, weight: .black))
                .foregroundColor(.white.opacity(0.8))
        }
    }
}

enum AssetType {
    case photo, video, splat
}

struct MediaAsset: Identifiable {
    let id = UUID()
    let type: AssetType
    let title: String
    let date: Date
    var thumbnail: String?
    var points: Int = 0
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
