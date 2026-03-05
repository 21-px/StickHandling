//
//  PuckTrackingView.swift
//  StickHandle
//
//  Created by Tyson on 3/4/26.
//

/// Input: None (user navigates to this view)
/// Transformation: Displays live camera feed, processes each frame through PuckTracker, overlays red circle on detected puck position, shows tracking status
/// Output: Full-screen camera view with visual tracking feedback (red circle + status text)

import SwiftUI
import Combine
import AVFoundation

struct PuckTrackingView: View {
    
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var puckTracker = PuckTracker()
    
    @State private var viewSize: CGSize = .zero
    
    var body: some View {
        ZStack {
            // Camera preview layer
            CameraPreview(cameraManager: cameraManager)
                .edgesIgnoringSafeArea(.all)
            
            // Puck tracking overlay
            if let puckPosition = puckTracker.puckPosition {
                PuckOverlay(position: puckPosition, viewSize: viewSize)
            }
            
            // Status overlay (top of screen)
            VStack {
                TrackingStatusView(
                    isTracking: puckTracker.isTracking,
                    confidence: puckTracker.trackingConfidence
                )
                .padding()
                .background(Color.black.opacity(0.5))
                .cornerRadius(10)
                .padding()
                
                Spacer()
            }
        }
        .background(GeometryReader { geometry in
            Color.clear.preference(
                key: SizePreferenceKey.self,
                value: geometry.size
            )
        })
        .onPreferenceChange(SizePreferenceKey.self) { size in
            viewSize = size
        }
        .onReceive(cameraManager.frames) { frame in
            // Process each frame as it comes in
            puckTracker.processFrame(frame)
        }
        .task {
            // Request camera access when view appears
            await cameraManager.requestAccess()
            
            if cameraManager.isAuthorized {
                // Start camera session
                cameraManager.startSession()
            }
        }
        .onDisappear {
            cameraManager.stopSession()
        }
        .alert("Camera Error", isPresented: .constant(cameraManager.error != nil)) {
            Button("OK") {
                // In a real app, might want to open Settings
            }
        } message: {
            if let error = cameraManager.error {
                Text(error.localizedDescription)
            }
        }
    }
}

// MARK: - Camera Preview

/// UIViewRepresentable wraps UIKit views for use in SwiftUI
/// Similar to wrapping a DOM element in a React component
struct CameraPreview: UIViewRepresentable {
    
    let cameraManager: CameraManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.backgroundColor = .black
        
        let previewLayer = cameraManager.getPreviewLayer()
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        
        // Store layer in context to update frame later
        context.coordinator.previewLayer = previewLayer
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update preview layer frame when view size changes
        context.coordinator.previewLayer?.frame = uiView.bounds
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - Puck Overlay

/// Red circle that shows where the puck is detected
struct PuckOverlay: View {
    let position: PuckPosition
    let viewSize: CGSize
    
    var body: some View {
        let screenPosition = position.toScreenCoordinates(viewSize: viewSize)
        let radiusInPixels = position.radius * min(viewSize.width, viewSize.height)
        
        Circle()
            .stroke(Color.red, lineWidth: 4)
            .frame(width: radiusInPixels * 2, height: radiusInPixels * 2)
            .position(screenPosition)
            .animation(.easeInOut(duration: 0.1), value: position.x)
            .animation(.easeInOut(duration: 0.1), value: position.y)
    }
}

// MARK: - Status View

/// Shows tracking status at top of screen
struct TrackingStatusView: View {
    let isTracking: Bool
    let confidence: Float
    
    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(isTracking ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                
                Text(isTracking ? "Tracking Puck" : "No Puck Detected")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            
            if isTracking {
                Text("Confidence: \(Int(confidence * 100))%")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
    }
}

// MARK: - Helper for getting view size

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}

// MARK: - Preview

#Preview {
    PuckTrackingView()
}
