#if canImport(UIKit)

//
//  CameraPreview.swift
//  BoyfriendCamera
//
//  Created by 柯杰 on 11/19/25.
//

import Foundation
import SwiftUI
import AVFoundation
import UIKit

struct CameraPreview: UIViewRepresentable {
    // We pass the "Manager" into this view so it knows what to show
    @ObservedObject var cameraManager: CameraManager

    func makeUIView(context: Context) -> UIView {
        // 1. Create a blank standard View
        let view = UIView(frame: UIScreen.main.bounds)

        // 2. Create the layer that actually shows the video
        let previewLayer = AVCaptureVideoPreviewLayer(session: cameraManager.session)
        
        // 3. Configure it to fill the whole screen
        previewLayer.frame = view.frame
        previewLayer.videoGravity = .resizeAspectFill

        // 4. Add the layer to the view
        view.layer.addSublayer(previewLayer)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        // This function updates the view if data changes, but we don't need it for a simple camera feed yet.
    }
}
#else

import SwiftUI
import AVFoundation

struct CameraPreview: View {
    @ObservedObject var cameraManager: CameraManager

    var body: some View {
        Text("Camera preview is not available on this platform.")
            .multilineTextAlignment(.center)
            .padding()
    }
}

#endif

