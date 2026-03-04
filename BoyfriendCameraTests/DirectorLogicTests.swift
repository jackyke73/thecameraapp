import Testing
import CoreGraphics
import SwiftUI
@testable import BoyfriendCamera

struct DirectorLogicTests {

    // Helper to create minimal state
    func check(
        isPersonDetected: Bool = true,
        peopleCount: Int = 1,
        nosePoint: CGPoint? = CGPoint(x: 0.5, y: 0.5),
        faceBounds: CGRect? = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2), // Ideal size
        targetPoint: CGPoint = CGPoint(x: 0.5, y: 0.5),
        deviceRoll: Double = 0.0,
        devicePitch: Double = 0.0,
        isLevel: Bool = true,
        expressions: [String] = ["Happy"],
        lighting: LightingQuality = .good,
        yoloCommand: String? = nil
    ) -> DirectorInstruction {
        return DirectorLogic.determineInstruction(
            isPersonDetected: isPersonDetected,
            peopleCount: peopleCount,
            nosePoint: nosePoint,
            faceBounds: faceBounds,
            targetPoint: targetPoint,
            deviceRoll: deviceRoll,
            devicePitch: devicePitch,
            isLevel: isLevel,
            expressions: expressions,
            lighting: lighting,
            yoloCommand: yoloCommand
        )
    }

    @Test func testSovereignAIOverride() {
        let instr = check(yoloCommand: "Step Left")
        #expect(instr.text == "Step Left")
        #expect(instr.priority == .critical)
    }

    @Test func testLeveling() {
        // Roll > Threshold -> Tilt Left
        let leftTilt = check(deviceRoll: 0.1, isLevel: false)
        #expect(leftTilt.text == "Tilt Left")
        
        // Roll < -Threshold -> Tilt Right
        let rightTilt = check(deviceRoll: -0.1, isLevel: false)
        #expect(rightTilt.text == "Tilt Right")
    }
    
    @Test func testSubjectPresence() {
        let noSubject = check(isPersonDetected: false)
        #expect(noSubject.text == "Find your Subject")
    }

    @Test func testPitchCorrection() {
        // Pitch > Threshold (Leaning back/up) -> Angle Forward
        let leanBack = check(devicePitch: 0.2)
        #expect(leanBack.text == "Angle Forward")
        
        // Pitch < -Threshold (Leaning fwd/down) -> Angle Upward
        let leanFwd = check(devicePitch: -0.2)
        #expect(leanFwd.text == "Angle Upward")
    }

    @Test func testDistance() {
        // Too small (< 0.15) -> Move Closer
        let smallFace = CGRect(x: 0.4, y: 0.4, width: 0.1, height: 0.1)
        let closer = check(faceBounds: smallFace)
        #expect(closer.text == "Move Closer")

        // Too big (> 0.6) -> Back Up
        let bigFace = CGRect(x: 0.2, y: 0.2, width: 0.7, height: 0.7)
        let backUp = check(faceBounds: bigFace)
        #expect(backUp.text == "Back Up")
    }
    
    @Test func testFraming() {
        // Nose to the Right of Target (0.5) -> Pan Right
        let rightNose = CGPoint(x: 0.8, y: 0.5)
        let panRight = check(nosePoint: rightNose)
        #expect(panRight.text == "Pan Right")
        
        // Nose to the Left of Target -> Pan Left
        let leftNose = CGPoint(x: 0.2, y: 0.5)
        let panLeft = check(nosePoint: leftNose)
        #expect(panLeft.text == "Pan Left")
    }

    @Test func testExpression() {
        // Neutral expression -> Suggest laugh
        let boring = check(expressions: ["Neutral"])
        #expect(boring.text == "Make her laugh!")
    }

    @Test func testSuccess() {
        let perfect = check()
        #expect(perfect.text == "Perfect! Shoot!")
    }
}
