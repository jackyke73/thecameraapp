import Foundation
import ARKit
import Combine

/// Manages the registration and alignment of multiple splats into a single world space.
/// Enables "Splat-to-Real-World" persistence.
class SplatWorldMap: ObservableObject {
    
    struct Voxel: Hashable {
        let x: Int16
        let y: Int16
        let z: Int16
        
        static func from(_ pos: SIMD3<Float>, resolution: Float = 0.1) -> Voxel {
            Voxel(x: Int16(floor(pos.x / resolution)),
                  y: Int16(floor(pos.y / resolution)),
                  z: Int16(floor(pos.z / resolution)))
        }
        
        func toWorld(resolution: Float = 0.1) -> SIMD3<Float> {
            SIMD3<Float>(Float(x) * resolution + resolution/2,
                        Float(y) * resolution + resolution/2,
                        Float(z) * resolution + resolution/2)
        }
    }
    
    struct VoxelData {
        var pointCount: Int = 0
        var observationCount: Int = 0 // How many unique camera angles saw this voxel
        var lastUpdated: Date = Date()
        
        var uncertainty: Float {
            if observationCount == 0 { return 1.0 }
            return 1.0 / Float(observationCount)
        }
    }
    
    @Published var voxelGrid: [Voxel: VoxelData] = [:]
    private let lock = NSLock()
    private let resolution: Float = 0.08 // 8cm voxels
    
    func reset() async {
        lock.lock()
        voxelGrid.removeAll()
        lock.unlock()
    }
    
    /// Integrates new points and updates uncertainty based on viewing angle
    func integrate(points: [SIMD3<Float>], cameraPos: SIMD3<Float>) async {
        lock.lock()
        defer { lock.unlock() }
        
        for p in points {
            let v = Voxel.from(p, resolution: resolution)
            var data = voxelGrid[v] ?? VoxelData()
            data.pointCount += 1
            data.observationCount += 1 // Simplified: every integration is a "new" observation
            data.lastUpdated = Date()
            voxelGrid[v] = data
        }
    }
    
    /// Returns the centroid of the top-N highest uncertainty areas.
    /// Used for "Active Guidance" to tell the user where to move next.
    func findHighUncertaintyCentroids(limit: Int = 5) async -> [SIMD3<Float>] {
        lock.lock()
        defer { lock.unlock() }
        
        // Find voxels with points but low observation counts
        let candidates = voxelGrid.filter { $0.value.observationCount < 5 && $0.value.pointCount > 2 }
        
        let sorted = candidates.sorted { $0.value.uncertainty > $1.value.uncertainty }
        return sorted.prefix(limit).map { $0.key.toWorld(resolution: resolution) }
    }
    
    /// Calculates a normalized vector towards the largest cluster of uncertain voxels
    func getPathToGaps(cameraPos: SIMD3<Float>) async -> SIMD3<Float>? {
        let targets = await findHighUncertaintyCentroids(limit: 10)
        guard !targets.isEmpty else { return nil }
        
        var avgDir = SIMD3<Float>(0, 0, 0)
        for t in targets {
            avgDir += simd_normalize(t - cameraPos)
        }
        
        return simd_normalize(avgDir)
    }
    
    /// Export the current grid for persistence or cloud-sync
    func export() -> Data? {
        // TODO: Implement binary serialization of the grid
        return nil
    }
}
