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
        var observationCount: Int = 0 
        var lastUpdated: Date = Date()
        var viewingAngles: [SIMD3<Float>] = [] // Track unique viewing vectors
        
        var uncertainty: Float {
            // High uncertainty if we haven't seen it from many different angles
            // We want at least 5 distinct viewing angles (spread out)
            let angularDiversity = calculateAngularDiversity()
            let countWeight = min(Float(observationCount) / 10.0, 1.0)
            return 1.0 - (angularDiversity * 0.7 + countWeight * 0.3)
        }
        
        private func calculateAngularDiversity() -> Float {
            guard viewingAngles.count > 1 else { return 0 }
            // Measure how "spread out" the viewing angles are
            // Simple proxy: average dot product between all pairs (lower is better diversity)
            var totalDot: Float = 0
            var pairs: Float = 0
            for i in 0..<viewingAngles.count {
                for j in (i+1)..<viewingAngles.count {
                    totalDot += abs(simd_dot(viewingAngles[i], viewingAngles[j]))
                    pairs += 1
                }
            }
            let avgDot = totalDot / pairs
            return 1.0 - avgDot // 1.0 means perfectly orthogonal/diverse, 0 means all same
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
            
            let viewDir = simd_normalize(cameraPos - p)
            
            // Only add if it's sufficiently different from existing angles (> 15 degrees)
            let isNewAngle = data.viewingAngles.allSatisfy { simd_dot($0, viewDir) < 0.96 }
            
            if isNewAngle {
                data.viewingAngles.append(viewDir)
                data.observationCount += 1
                // Keep only top 10 diverse angles to save memory
                if data.viewingAngles.count > 10 {
                    data.viewingAngles.removeFirst()
                }
            }
            
            data.lastUpdated = Date()
            voxelGrid[v] = data
        }
    }
    
    /// Returns the centroid of the top-N highest uncertainty areas.
    /// Used for "Active Guidance" to tell the user where to move next.
    func findHighUncertaintyCentroids(limit: Int = 10) async -> [SIMD3<Float>] {
        lock.lock()
        defer { lock.unlock() }
        
        // Find voxels with points but high uncertainty
        let candidates = voxelGrid.filter { $0.value.pointCount > 2 && $0.value.uncertainty > 0.4 }
        
        let sorted = candidates.sorted { $0.value.uncertainty > $1.value.uncertainty }
        return sorted.prefix(limit).map { $0.key.toWorld(resolution: resolution) }
    }
    
    /// Calculates a normalized vector towards the largest cluster of uncertain voxels
    func getPathToGaps(cameraPos: SIMD3<Float>) async -> SIMD3<Float>? {
        let targets = await findHighUncertaintyCentroids(limit: 20)
        guard !targets.isEmpty else { return nil }
        
        // Weight the direction by uncertainty
        var weightedDir = SIMD3<Float>(0, 0, 0)
        var totalWeight: Float = 0
        
        lock.lock()
        for t in targets {
            let v = Voxel.from(t, resolution: resolution)
            if let data = voxelGrid[v] {
                let dir = t - cameraPos
                let dist = simd_length(dir)
                // Ignore voxels too far away (> 2m) for immediate guidance
                if dist < 2.0 {
                    let weight = data.uncertainty / (dist + 0.1)
                    weightedDir += simd_normalize(dir) * weight
                    totalWeight += weight
                }
            }
        }
        lock.unlock()
        
        if totalWeight == 0 { return nil }
        return simd_normalize(weightedDir)
    }
}
