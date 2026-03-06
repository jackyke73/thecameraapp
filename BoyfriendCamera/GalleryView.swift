import SwiftUI
import Photos

struct GalleryView: View {
    @Environment(\.dismiss) var dismiss
    
    // State
    @State private var selectedTab: GalleryTab = .all
    @State private var assets: [AssetItem] = []
    @State private var selectedAsset: AssetItem? = nil
    @State private var isLoading = true
    
    // Grid Config
    private let columns = [
        GridItem(.adaptive(minimum: 110, maximum: 160), spacing: 2)
    ]
    
    // Theme Colors (Local definitions to ensure standalone preview works, 
    // ideally these come from Theme.swift but I'll hardcode for safety/speed)
    private let bgPrimary = Color(hex: "080808")
    private let bgSecondary = Color(hex: "121212")
    private let textPrimary = Color(hex: "EEEEEE")
    private let accentColor = Color.white
    
    enum GalleryTab: String, CaseIterable {
        case all = "All"
        case photos = "Photos"
        case splats = "3D Splats"
    }
    
    var body: some View {
        ZStack {
            bgPrimary.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // MARK: - Header
                HStack {
                    Text("Gallery")
                        .font(.system(size: 20, weight: .semibold, design: .default))
                        .foregroundColor(textPrimary)
                    
                    Spacer()
                    
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(8)
                            .background(Circle().fill(Color.white.opacity(0.1)))
                    }
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .padding(.bottom, 12)
                .background(bgPrimary.opacity(0.95))
                
                // MARK: - Filters
                HStack(spacing: 0) {
                    ForEach(GalleryTab.allCases, id: \.self) { tab in
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selectedTab = tab
                            }
                        } label: {
                            VStack(spacing: 8) {
                                Text(tab.rawValue)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(selectedTab == tab ? .white : .gray)
                                
                                Rectangle()
                                    .fill(selectedTab == tab ? .white : .clear)
                                    .frame(height: 2)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
                .background(bgPrimary)
                
                // MARK: - Grid
                ScrollView {
                    if isLoading {
                        VStack {
                            Spacer().frame(height: 100)
                            ProgressView()
                                .tint(.white)
                        }
                    } else if filteredAssets.isEmpty {
                        VStack(spacing: 16) {
                            Spacer().frame(height: 100)
                            Image(systemName: selectedTab == .splats ? "cube.transparent" : "photo.on.rectangle")
                                .font(.system(size: 40))
                                .foregroundColor(.gray.opacity(0.3))
                            Text("No content yet")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    } else {
                        LazyVGrid(columns: columns, spacing: 2) {
                            ForEach(filteredAssets) { asset in
                                Button {
                                    selectedAsset = asset
                                } label: {
                                    AssetThumbnail(asset: asset)
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipped()
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                }
            }
            
            // MARK: - Detail Viewer Overlay
            if let asset = selectedAsset {
                GalleryDetailView(asset: asset) {
                    selectedAsset = nil
                }
                .transition(.opacity)
                .zIndex(100)
            }
        }
        .onAppear {
            loadAssets()
        }
    }
    
    var filteredAssets: [AssetItem] {
        switch selectedTab {
        case .all: return assets
        case .photos: return assets.filter { $0.type == .photo }
        case .splats: return assets.filter { $0.type == .splat }
        }
    }
    
    func loadAssets() {
        isLoading = true
        
        // 1. Load PHAssets
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        // Filter for app-specific album ideally, but for MVP just recent
        fetchOptions.fetchLimit = 50
        
        let phAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        var newAssets: [AssetItem] = []
        
        phAssets.enumerateObjects { asset, _, _ in
            newAssets.append(AssetItem(id: asset.localIdentifier, type: .photo, phAsset: asset))
        }
        
        // 2. Add Dummy Splats for visualization (as requested by prompt: "placeholder for 3D splat thumbnails")
        // In a real app, this would scan the Documents directory
        let dummySplat1 = AssetItem(id: "splat-1", type: .splat, title: "Kitchen Scan", date: Date().addingTimeInterval(-3600))
        let dummySplat2 = AssetItem(id: "splat-2", type: .splat, title: "Skate Park", date: Date().addingTimeInterval(-86400))
        
        newAssets.insert(dummySplat1, at: 0) // Put a splat first to show it off
        newAssets.insert(dummySplat2, at: 3)
        
        // Sort combined list
        newAssets.sort { ($0.date ?? Date()) > ($1.date ?? Date()) }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.assets = newAssets
            self.isLoading = false
        }
    }
}

// MARK: - Models

struct AssetItem: Identifiable {
    let id: String
    enum AssetType { case photo, splat }
    let type: AssetType
    var phAsset: PHAsset?
    var title: String?
    var date: Date?
    
    init(id: String, type: AssetType, phAsset: PHAsset? = nil, title: String? = nil, date: Date? = nil) {
        self.id = id
        self.type = type
        self.phAsset = phAsset
        self.title = title
        self.date = date ?? phAsset?.creationDate
    }
}

// MARK: - Subviews

struct AssetThumbnail: View {
    let asset: AssetItem
    @State private var image: UIImage?
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(white: 0.1)
                
                if asset.type == .photo {
                    if let img = image {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                    } else {
                        ProgressView()
                    }
                } else {
                    // Splat Placeholder
                    ZStack {
                        // Cool gradient background for splats
                        LinearGradient(
                            colors: [Color.blue.opacity(0.4), Color.purple.opacity(0.4)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        
                        VStack(spacing: 4) {
                            Image(systemName: "cube.transparent.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                            
                            if let title = asset.title {
                                Text(title)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 4)
                            }
                            
                            Text("3D SPLAT")
                                .font(.system(size: 8, weight: .black))
                                .foregroundColor(.white.opacity(0.7))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.4))
                                .cornerRadius(4)
                        }
                    }
                }
                
                // Overlay Badge for type if needed
                if asset.type == .splat {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "cube")
                                .font(.system(size: 10))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                                .padding(4)
                        }
                        Spacer()
                    }
                }
            }
        }
        .onAppear {
            if asset.type == .photo, let phAsset = asset.phAsset {
                let manager = PHImageManager.default()
                let options = PHImageRequestOptions()
                options.deliveryMode = .opportunistic
                options.isNetworkAccessAllowed = true
                manager.requestImage(for: phAsset, targetSize: CGSize(width: 300, height: 300), contentMode: .aspectFill, options: options) { res, _ in
                    self.image = res
                }
            }
        }
    }
}

struct GalleryDetailView: View {
    let asset: AssetItem
    let onClose: () -> Void
    @State private var image: UIImage?
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            if asset.type == .photo {
                if let img = image {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ProgressView()
                }
            } else {
                // Splat Viewer Placeholder
                VStack(spacing: 20) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                        .symbolEffect(.pulse, options: .repeating)
                    
                    Text("3D Viewer Loading...")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("Interactive splat visualization would render here using Metal.")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            
            // UI Overlay
            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                }
                .padding(.top, 50)
                .padding(.horizontal)
                
                Spacer()
                
                // Bottom Bar
                HStack {
                    if asset.type == .splat {
                        Button("Export .PLY") { /* Export logic */ }
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.black)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white)
                            .cornerRadius(20)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "heart")
                        .font(.title3)
                        .foregroundColor(.white)
                        .padding()
                    
                    Image(systemName: "square.and.arrow.up")
                        .font(.title3)
                        .foregroundColor(.white)
                        .padding()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
        .onAppear {
            if asset.type == .photo, let phAsset = asset.phAsset {
                let manager = PHImageManager.default()
                let options = PHImageRequestOptions()
                options.deliveryMode = .highQualityFormat
                manager.requestImage(for: phAsset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) { res, _ in
                    self.image = res
                }
            }
        }
    }
}
