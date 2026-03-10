import Foundation
import simd

/// Stores the state of the Gaussian Splatting scene as a voxel grid of descriptors.
/// Used for identifying gaps in capture and planning the "Next Best View".
actor SplatWorldMap {
    private var voxelGrid: [VoxelKey: VoxelInfo]
    private let voxelSize: Float = 0.15 // 15cm voxels for performance
    
    // Bounds of the active capture area
    private var minBound = SIMD3<Float>(repeating: Float.infinity)
    private var maxBound = SIMD3<Float>(repeating: -Float.infinity)
    
    init() {
        self.voxelGrid = [:]
    }
    
    func reset() {
        voxelGrid.removeAll()
        minBound = SIMD3<Float>(repeating: Float.infinity)
        maxBound = SIMD3<Float>(repeating: -Float.infinity)
    }
    
    /// Integrates a batch of 3D points into the world map.
    func integrate(points: [SIMD3<Float>], cameraPos: SIMD3<Float>) {
        for p in points {
            let key = toVoxelKey(p)
            var info = voxelGrid[key] ?? VoxelInfo()
            info.splatCount += 1
            
            // Record the view direction that saw this voxel
            let viewDir = normalize(p - cameraPos)
            let octant = getOctant(viewDir)
            info.visitedViewOctants |= (1 << octant)
            
            voxelGrid[key] = info
            
            // Update bounds
            minBound = min(minBound, p)
            maxBound = max(maxBound, p)
        }
    }
    
    /// Identifies the "Gaps" in the scan by finding voxels with high uncertainty.
    func findHighUncertaintyCentroids() -> [SIMD3<Float>] {
        let targets = voxelGrid.filter { _, info in
            info.splatCount > 0 && info.uncertainty > 0.5
        }
        
        // Sort by uncertainty and take top 20 to avoid overwhelming the guidance
        return targets.sorted { $0.value.uncertainty > $1.value.uncertainty }
            .prefix(20)
            .map { fromVoxelKey($0.key) }
    }
    
    /// Calculates a path vector towards the largest cluster of uncertainty.
    func getPathToGaps(cameraPos: SIMD3<Float>) -> SIMD3<Float>? {
        let gaps = findHighUncertaintyCentroids()
        guard !gaps.isEmpty else { return nil }
        
        // Find the "center of gravity" of the gaps
        let gapCentroid = gaps.reduce(SIMD3<Float>(0,0,0), +) / Float(gaps.count)
        return normalize(gapCentroid - cameraPos)
    }
    
    // MARK: - Helpers
    
    private func toVoxelKey(_ pos: SIMD3<Float>) -> VoxelKey {
        VoxelKey(
            x: Int(floor(pos.x / voxelSize)),
            y: Int(floor(pos.y / voxelSize)),
            z: Int(floor(pos.z / voxelSize))
        )
    }
    
    private func fromVoxelKey(_ key: VoxelKey) -> SIMD3<Float> {
        SIMD3<Float>(
            Float(key.x) * voxelSize + voxelSize/2,
            Float(key.y) * voxelSize + voxelSize/2,
            Float(key.z) * voxelSize + voxelSize/2
        )
    }
    
    private func getOctant(_ dir: SIMD3<Float>) -> Int {
        var octant = 0
        if dir.x > 0 { octant |= 1 }
        if dir.y > 0 { octant |= 2 }
        if dir.z > 0 { octant |= 4 }
        return octant
    }
}
