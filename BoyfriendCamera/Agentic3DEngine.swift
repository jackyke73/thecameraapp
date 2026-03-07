import Foundation
import CoreVideo
import simd

/// Represents a detected 3D object/cluster in a Gaussian Splatting scene.
struct SplatObject: Identifiable, Sendable {
    let id: UUID
    let label: String
    let confidence: Double
    let center: SIMD3<Float>
    let boundingBox: [SIMD3<Float>] // 8 corners
}

/// A structure to hold the results of a 3D semantic analysis.
struct SplatSceneAnalysis: Sendable {
    let objects: [SplatObject]
    let sceneGraphHierarchy: [String: [String]] // Simple parent-child relationships
    let recommendedManipulations: [SplatAction]
}

struct SplatAction: Sendable {
    let targetId: UUID
    let actionDescription: String // e.g., "Shift 1m Left", "Inpaint Background"
}

// MARK: - Active Guidance Types

struct VoxelKey: Hashable, Sendable {
    let x: Int
    let y: Int
    let z: Int
    
    init(x: Int, y: Int, z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }
}

struct VoxelInfo: Sendable {
    var splatCount: Int = 0
    // Bitmask of 8 octants to track view diversity (simple heuristic for entropy)
    var visitedViewOctants: UInt8 = 0 
    
    // Heuristic: Uncertainty is high if we haven't seen this voxel from multiple angles,
    // or if it has very few splats (potential hole).
    var uncertainty: Float {
        let densityScore = min(Float(splatCount) / 10.0, 1.0) // Saturation at 10 splats
        let diversityScore = Float(visitedViewOctants.nonzeroBitCount) / 8.0
        
        // We want to minimize uncertainty.
        // If density is 0, uncertainty is 1.0.
        // If density is high but diversity is low, uncertainty is medium.
        return 1.0 - (densityScore * 0.7 + diversityScore * 0.3)
    }
    
    init() {} 
}

/// The Agentic3DEngine is responsible for bridging 2D images with 3D Gaussian Splatting spatial understanding.
actor Agentic3DEngine {
    
    private let isExperimental: Bool = true
    
    // Active Guidance State
    private var voxelGrid: [VoxelKey: VoxelInfo]
    private let voxelSize: Float = 0.1 // 10cm voxels
    
    init() {
        print("Agentic3DEngine: Initializing Spatial Reasoning Systems...")
        self.voxelGrid = [:]
    }
    
    /// Projects 2D detections into 3D space using depth data (FastViT/DepthAnything) 
    /// to initialize Gaussian clusters.
    func project2DTo3D(detections: [String], depthMap: CVPixelBuffer) async -> [SplatObject] {
        // This is where the magic happens:
        // 1. Take 2D bounding boxes from YOLO/FastVLM.
        // 2. Sample DepthMap at those regions.
        // 3. Back-project into 3D world space.
        // 4. Group Gaussians (Splatting primitives) that fall into these volumes.
        
        // Mocking 3D object detection for the prototype
        return [
            SplatObject(
                id: UUID(),
                label: "Primary Subject",
                confidence: 0.98,
                center: SIMD3<Float>(0, 0, -2.0),
                boundingBox: []
            ),
            SplatObject(
                id: UUID(),
                label: "Background Obstacle",
                confidence: 0.75,
                center: SIMD3<Float>(1.5, 0, -5.0),
                boundingBox: []
            )
        ]
    }
    
    // MARK: - AG-Splatting Guidance
    
    /// Updates the voxel grid with new splat data and returns a guidance vector for the next best view.
    func updateUncertaintyMap(currentCameraPosition: SIMD3<Float>, newSplats: [SIMD3<Float>]) -> SIMD3<Float>? {
        // 1. Integrate new splats into voxels
        for splatPos in newSplats {
            let key = toVoxelKey(splatPos)
            var info = voxelGrid[key] ?? VoxelInfo()
            info.splatCount += 1
            
            // Calculate view octant (simplified view direction)
            let viewDir = simd_normalize(splatPos - currentCameraPosition)
            let octant = getOctant(viewDir)
            info.visitedViewOctants |= (1 << octant)
            
            voxelGrid[key] = info
        }
        
        // 2. Find High Uncertainty Centroid (Target)
        // Filter for voxels that have *some* data but need *more* (don't guide to empty space yet)
        let uncertainVoxels = voxelGrid.filter { _, info in
            info.splatCount > 0 && info.uncertainty > 0.4
        }
        
        guard !uncertainVoxels.isEmpty else { return nil } // Scan complete!
        
        // Compute weighted centroid
        var weightedSum = SIMD3<Float>(0, 0, 0)
        var totalWeight: Float = 0
        
        for (key, info) in uncertainVoxels {
            let pos = fromVoxelKey(key)
            let weight = info.uncertainty
            weightedSum += pos * weight
            totalWeight += weight
        }
        
        let targetPos = weightedSum / totalWeight
        
        // 3. Generate Guidance Vector (Move towards target position's "unseen" side)
        // Ideally, we'd solve for the view direction that maximizes entropy reduction.
        // Simple heuristic: Move towards the centroid.
        let guidanceVector = simd_normalize(targetPos - currentCameraPosition)
        return guidanceVector
    }
    
    /// Returns the centroids of high-uncertainty voxels for visualization.
    func getHighUncertaintyVoxels() -> [SIMD3<Float>] {
        return voxelGrid.compactMap { (key, info) -> SIMD3<Float>? in
            // Return centroid if uncertainty is high AND we have some data (it's not empty space)
            if info.uncertainty > 0.6 && info.splatCount > 0 {
                return fromVoxelKey(key)
            }
            return nil
        }
    }
    
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

    /// Calculates a focus-weighted guidance vector for AG-Splatting.
    /// This identifies the largest "gap" in the sphere of coverage and points towards it.
    func calculateStrategicGuidance(cameraPos: SIMD3<Float>, targetPos: SIMD3<Float>) -> SIMD3<Float> {
        // Find high entropy zones relative to the camera
        let highUncertainty = getHighUncertaintyVoxels()
        
        if highUncertainty.isEmpty {
            // Default to simple orbit
            return simd_normalize(targetPos - cameraPos)
        }
        
        // Find the centroid of the MOST uncertain region
        let centroid = highUncertainty.reduce(SIMD3<Float>(0,0,0), +) / Float(highUncertainty.count)
        return simd_normalize(centroid - cameraPos)
    }

    /// Suggests how to "fix" the 3D scene by moving objects (The "Agentic Photographer" mode).
    func suggest3DAdjustments(objects: [SplatObject]) -> [SplatAction] {
        var actions: [SplatAction] = []
        
        if let obstacle = objects.first(where: { $0.label.contains("Obstacle") }) {
            actions.append(SplatAction(
                targetId: obstacle.id,
                actionDescription: "Translate 2.0m Right to clear the background."
            ))
        }
        
        return actions
    }
}
