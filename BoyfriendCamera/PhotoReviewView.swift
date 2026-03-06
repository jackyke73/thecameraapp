import SwiftUI
import Photos

// MARK: - Gallery View
struct PhotoReviewView: View {
    @Environment(\.dismiss) var dismiss
    @State private var assets: [PHAsset] = []
    @State private var selectedAsset: PHAsset? = nil
    @Namespace private var galleryNamespace
    
    // Grid Configuration
    private let columns = [
        GridItem(.adaptive(minimum: 100, maximum: 150), spacing: 2)
    ]
    
    @State private var selectedTab = 0
    
    var body: some View {
        ZStack {
            Theme.bgPrimary.ignoresSafeArea()
            
            // Only show grid when no asset is selected
            if selectedAsset == nil {
                VStack(spacing: 0) {
                    // Header with Tabs
                    VStack(spacing: 16) {
                        HStack {
                            Text("GALLERY")
                                .font(.system(size: 14, weight: .black, design: .monospaced))
                                .tracking(2)
                                .foregroundColor(Theme.textPrimary)
                            Spacer()
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(Theme.textSecondary)
                                    .padding(8)
                                    .background(Theme.bgTertiary.opacity(0.5))
                                    .clipShape(Circle())
                            }
                        }
                        .padding(.horizontal)
                        
                        // Custom Segmented Control
                        HStack(spacing: 0) {
                            TabButton(title: "PHOTOS", isSelected: selectedTab == 0) { selectedTab = 0 }
                            TabButton(title: "SPATIAL", isSelected: selectedTab == 1) { selectedTab = 1 }
                        }
                        .padding(4)
                        .background(Theme.bgTertiary)
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                    .background(Theme.bgPrimary.opacity(0.95))
                    
                    if selectedTab == 0 {
                        if assets.isEmpty {
                            Spacer()
                            VStack(spacing: 12) {
                                ProgressView().tint(Theme.accent)
                                Text("Loading Gallery...")
                                    .font(.caption.monospaced())
                                    .foregroundColor(Theme.textSecondary)
                            }
                            Spacer()
                        } else {
                            ScrollView {
                                LazyVGrid(columns: columns, spacing: 2) {
                                    ForEach(assets, id: \.localIdentifier) { asset in
                                        Button {
                                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                                selectedAsset = asset
                                            }
                                        } label: {
                                            AssetThumbnailView(asset: asset)
                                                .aspectRatio(1, contentMode: .fill)
                                                .clipped()
                                                .matchedGeometryEffect(id: asset.localIdentifier, in: galleryNamespace)
                                        }
                                    }
                                }
                                .padding(.bottom, 20)
                            }
                        }
                    } else {
                        // Spatial Tab Placeholder
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: "cube.transparent")
                                .font(.system(size: 40))
                                .foregroundColor(Theme.textSecondary)
                            Text("NO SPATIAL CAPTURES")
                                .font(.caption.monospaced().bold())
                                .foregroundColor(Theme.textSecondary)
                        }
                        Spacer()
                    }
                }
            }
            
            // Detail Overlay (remains same)
            if let asset = selectedAsset {
                DetailView(
                    asset: asset,
                    namespace: galleryNamespace,
                    onClose: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            selectedAsset = nil
                        }
                    }
                )
                .zIndex(2)
            }
        }
        .onAppear {
            fetchPhotos()
        }
    }
}

struct TabButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(isSelected ? Theme.bgPrimary : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(isSelected ? Theme.accent : Color.clear)
                .cornerRadius(6)
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}
    
    private func fetchPhotos() {
        DispatchQueue.global(qos: .userInitiated).async {
            let albumName = "Boyfriend Camera"
            let fetchOptions = PHFetchOptions()
            fetchOptions.predicate = NSPredicate(format: "title = %@", albumName)
            
            let collection = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: fetchOptions)
            
            if let album = collection.firstObject {
                let assetsOptions = PHFetchOptions()
                assetsOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)] // Newest first
                
                let result = PHAsset.fetchAssets(in: album, options: assetsOptions)
                var allAssets: [PHAsset] = []
                result.enumerateObjects { asset, _, _ in
                    allAssets.append(asset)
                }
                
                DispatchQueue.main.async {
                    self.assets = allAssets
                }
            }
        }
    }
}

// MARK: - Thumbnail Component
struct AssetThumbnailView: View {
    let asset: PHAsset
    @State private var image: UIImage?
    
    var body: some View {
        GeometryReader { geo in
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
            } else {
                Rectangle()
                    .fill(Theme.bgSecondary)
                    .overlay(ProgressView())
                    .onAppear {
                        requestImage(size: geo.size)
                    }
            }
        }
    }
    
    private func requestImage(size: CGSize) {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.isNetworkAccessAllowed = true
        
        manager.requestImage(for: asset, targetSize: CGSize(width: size.width * 2, height: size.height * 2), contentMode: .aspectFill, options: options) { result, _ in
            self.image = result
        }
    }
}

// MARK: - Detail View
struct DetailView: View {
    let asset: PHAsset
    let namespace: Namespace.ID
    let onClose: () -> Void
    
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
            Theme.bgPrimary.ignoresSafeArea()
            
            if let img = image {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .matchedGeometryEffect(id: asset.localIdentifier, in: namespace)
                    .scaleEffect(scale)
                    .offset(offset)
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
                    .gesture(
                        DragGesture()
                            .onChanged { val in
                                if scale > 1.0 {
                                    offset = CGSize(width: lastOffset.width + val.translation.width, height: lastOffset.height + val.translation.height)
                                } else {
                                    // Swipe down to dismiss logic could go here
                                    offset = val.translation
                                }
                            }
                            .onEnded { val in
                                if scale > 1.0 {
                                    lastOffset = offset
                                } else {
                                    if val.translation.height > 100 {
                                        onClose()
                                    } else {
                                        withAnimation { offset = .zero }
                                    }
                                }
                            }
                    )
            } else {
                ProgressView().tint(Theme.accent)
                    .onAppear { loadFullImage() }
            }
            
            // Top Bar
            VStack {
                HStack {
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Theme.bgTertiary.opacity(0.8))
                            .clipShape(Circle())
                    }
                }
                .padding(.top, 50)
                .padding(.horizontal)
                
                Spacer()
                
                // Bottom Action Bar
                HStack(spacing: 40) {
                    ActionButton(icon: "trash", color: Theme.accentDestructive) {
                        // Delete logic placeholder
                    }
                    ActionButton(icon: "heart", color: Theme.accent) {
                        // Favorite logic placeholder
                    }
                    ActionButton(icon: "square.and.arrow.up", color: Theme.accent) {
                        // Share logic placeholder
                    }
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 40)
                .glassPanel()
                .padding(.bottom, 40)
            }
        }
    }
    
    private func loadFullImage() {
        let manager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        
        manager.requestImage(for: asset, targetSize: PHImageManagerMaximumSize, contentMode: .aspectFit, options: options) { result, _ in
            self.image = result
        }
    }
}

struct ActionButton: View {
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(width: 44, height: 44)
        }
    }
}
