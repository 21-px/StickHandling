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
    @State private var showDebugMask = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera preview layer
                CameraPreview(cameraManager: cameraManager)
                    .edgesIgnoringSafeArea(.all)
                
                // Debug mask overlay (if enabled)
                if showDebugMask, let debugImage = puckTracker.debugImage {
                    Image(uiImage: debugImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .opacity(0.5)
                        .edgesIgnoringSafeArea(.all)
                }
                
                // Puck tracking overlay
                if let puckPosition = puckTracker.puckPosition {
                    PuckOverlay(position: puckPosition, viewSize: geometry.size)
                        .id("\(puckPosition.x)-\(puckPosition.y)") // Force update when position changes
                }
                
                // Debug info at top (separate from circle)
                if let puckPosition = puckTracker.puckPosition {
                    VStack {
                        Spacer().frame(height: 100) // Below the status indicator
                        
                        VStack(spacing: 4) {
                            let screenPos = puckPosition.toScreenCoordinates(viewSize: geometry.size)
                            Text("Screen: (\(Int(screenPos.x)), \(Int(screenPos.y)))")
                                .font(.caption)
                                .foregroundColor(.yellow)
                            Text("Normalized: (\(String(format: "%.3f", puckPosition.x)), \(String(format: "%.3f", puckPosition.y)))")
                                .font(.caption)
                                .foregroundColor(.yellow)
                            Text("ViewSize: \(Int(geometry.size.width)) x \(Int(geometry.size.height))")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(8)
                        
                        Spacer()
                    }
                }
                
                // Status overlay (top of screen)
                VStack {
                    HStack {
                        // Back button to return to AR Course
                        Button(action: {
                            dismiss()
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "arrow.left.circle.fill")
                                    .font(.title2)
                                Text("Back")
                                    .font(.caption2)
                            }
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.green.opacity(0.6))
                            .cornerRadius(10)
                        }
                        
                        Spacer()
                        
                        TrackingStatusView(
                            isTracking: puckTracker.isTracking,
                            confidence: puckTracker.trackingConfidence
                        )
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(10)
                        
                        Spacer()
                        
                        // Debug toggle button
                        Button(action: {
                            showDebugMask.toggle()
                            puckTracker.setDebugMode(showDebugMask)
                        }) {
                            Image(systemName: showDebugMask ? "eye.fill" : "eye.slash.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                    
                    Spacer()
                }
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
}

// MARK: - Camera Preview

/// UIViewRepresentable wraps UIKit views for use in SwiftUI
/// Similar to wrapping a DOM element in a React component
struct CameraPreview: UIViewRepresentable {
    
    let cameraManager: CameraManager
    
    func makeUIView(context: Context) -> CameraPreviewUIView {
        let view = CameraPreviewUIView()
        view.backgroundColor = .black
        
        // Get preview layer from camera manager
        let previewLayer = cameraManager.getPreviewLayer()
        view.previewLayer = previewLayer
        view.layer.addSublayer(previewLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Update preview layer frame when view size changes
        DispatchQueue.main.async {
            uiView.previewLayer?.frame = uiView.bounds
        }
    }
}

/// Custom UIView that properly handles the preview layer frame
class CameraPreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Ensure preview layer matches view bounds
        previewLayer?.frame = bounds
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
