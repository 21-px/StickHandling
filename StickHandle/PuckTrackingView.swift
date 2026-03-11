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
    @State private var colorPickerMode = false
    @State private var selectedColorPreview: Color?
    @State private var showColorConfirmation = false
    @State private var lastTapLocation: CGPoint?
    @State private var showTapIndicator = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            // Camera preview layer - extends to screen edges
            CameraPreview(cameraManager: cameraManager)
                .ignoresSafeArea()
            
            // Debug mask overlay (if enabled) - must be at same level as camera to match edge-to-edge
            if showDebugMask, let debugImage = puckTracker.debugImage {
                Image(uiImage: debugImage)
                    .resizable()
                    .scaledToFill()
                    .frame(
                        width: cameraManager.previewLayerSize.width,
                        height: cameraManager.previewLayerSize.height
                    )
                    .clipped()  // Clip to frame bounds
                    .ignoresSafeArea()
                    .opacity(0.5)
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear {
                                    // 🔍 DIAGNOSTIC: Image view size vs preview layer size
                                    print("🔍 DEBUG MASK IMAGE VIEW:")
                                    print("   GeometryReader size: \(geometry.size.width) x \(geometry.size.height)")
                                    print("   Preview layer size: \(cameraManager.previewLayerSize.width) x \(cameraManager.previewLayerSize.height)")
                                    print("   Using preview layer size for .frame() to match exactly")
                                }
                                .onChange(of: geometry.size) { newSize in
                                    print("🔍 DEBUG MASK - GeometryReader size changed: \(newSize.width) x \(newSize.height)")
                                }
                                .onChange(of: cameraManager.previewLayerSize) { newSize in
                                    print("🔍 DEBUG MASK - Preview layer size changed: \(newSize.width) x \(newSize.height)")
                                }
                        }
                    )
            }
            
            // UI overlays - respect safe area
            GeometryReader { geometry in
                // 🔍 DIAGNOSTIC: GeometryReader size
                let _ = print("🔍 GEOMETRY - PuckTrackingView GeometryReader:")
                let _ = print("   geometry.size.width = \(geometry.size.width)")
                let _ = print("   geometry.size.height = \(geometry.size.height)")
                let _ = print("   Should be PORTRAIT (width < height)")
                
                ZStack {
                    // Invisible gesture layer for color picking
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            // Tap gesture for color picking
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    if colorPickerMode {
                                        handleColorPick(at: value.location, viewSize: geometry.size)
                                    }
                                }
                        )
                
                // Puck tracking overlay
                if let puckPosition = puckTracker.puckPosition {
                    PuckOverlay(position: puckPosition, viewSize: geometry.size)
                        .id("\(puckPosition.x)-\(puckPosition.y)") // Force update when position changes
                        .allowsHitTesting(false) // Don't block taps for color picking
                }
                
                // Tap indicator (shows where user tapped for debugging)
                if showTapIndicator, let tapLocation = lastTapLocation {
                    Circle()
                        .stroke(Color.yellow, lineWidth: 3)
                        .frame(width: 40, height: 40)
                        .position(tapLocation)
                        .allowsHitTesting(false)
                        .transition(.scale.combined(with: .opacity))
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
                        
                        if !colorPickerMode {
                            TrackingStatusView(
                                isTracking: puckTracker.isTracking,
                                confidence: puckTracker.trackingConfidence
                            )
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(10)
                        } else {
                            VStack(spacing: 4) {
                                Text("Tap on puck")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("to set color")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding()
                            .background(Color.blue.opacity(0.7))
                            .cornerRadius(10)
                        }
                        
                        Spacer()
                        
                        // Current color range display + Color picker mode toggle
                        VStack(spacing: 8) {
                            // Show current tracking color range
                            ColorRangeIndicator(
                                hueRange: puckTracker.targetHue,
                                satRange: puckTracker.targetSaturation,
                                brightRange: puckTracker.targetBrightness
                            )
                            
                            // Color picker mode toggle button
                            Button(action: {
                                colorPickerMode.toggle()
                                if !colorPickerMode {
                                    selectedColorPreview = nil
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: colorPickerMode ? "checkmark.circle.fill" : "eyedropper")
                                        .font(.title2)
                                    Text(colorPickerMode ? "Done" : "Pick")
                                        .font(.caption2)
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(colorPickerMode ? Color.green.opacity(0.7) : Color.blue.opacity(0.7))
                                .cornerRadius(10)
                            }
                        }
                    }
                    .padding()
                    
                    // Color preview when in picker mode
                    if colorPickerMode, let previewColor = selectedColorPreview {
                        VStack(spacing: 8) {
                            Text("Selected Color")
                                .font(.caption)
                                .foregroundColor(.white)
                            
                            RoundedRectangle(cornerRadius: 8)
                                .fill(previewColor)
                                .frame(width: 60, height: 60)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white, lineWidth: 2)
                                )
                        }
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(10)
                    }
                    
                    // Color confirmation message
                    if showColorConfirmation {
                        Text("✓ Color Updated!")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.green.opacity(0.8))
                            .cornerRadius(10)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    Spacer()
                    
                    // Debug toggle button at bottom
                    if !colorPickerMode {
                        HStack {
                            Spacer()
                            
                            Button(action: {
                                showDebugMask.toggle()
                                puckTracker.setDebugMode(showDebugMask)
                            }) {
                                HStack {
                                    Image(systemName: showDebugMask ? "eye.fill" : "eye.slash.fill")
                                        .font(.title3)
                                    Text(showDebugMask ? "Hide Mask" : "Show Mask")
                                        .font(.caption)
                                }
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.black.opacity(0.6))
                                .cornerRadius(10)
                            }
                        }
                        .padding()
                    }
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
    
    /// Handle color selection when user taps on the camera feed
    private func handleColorPick(at location: CGPoint, viewSize: CGSize) {
        print("🎨 Tap at screen: (\(location.x), \(location.y)) in view size: \(viewSize)")
        
        // Show tap indicator
        lastTapLocation = location
        withAnimation {
            showTapIndicator = true
        }
        
        // Convert screen coordinates to normalized coordinates (0-1)
        // Note: Screen coordinates are already in portrait orientation
        let normalizedPoint = CGPoint(
            x: location.x / viewSize.width,
            y: location.y / viewSize.height
        )
        
        print("🎨 Normalized tap: (\(normalizedPoint.x), \(normalizedPoint.y))")
        
        // Get color at that point
        guard let hsv = puckTracker.getColorAt(normalizedPoint: normalizedPoint) else {
            print("❌ Could not extract color at point")
            // Hide tap indicator after a moment
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation {
                    showTapIndicator = false
                }
            }
            return
        }
        
        print("🎨 Extracted HSV: H:\(hsv.h) S:\(hsv.s) V:\(hsv.v)")
        
        // Update the puck tracker with this color
        puckTracker.updateTargetColor(hsv: hsv)
        
        // Convert HSV back to RGB for preview
        let rgb = hsvToRgb(h: hsv.h, s: hsv.s, v: hsv.v)
        selectedColorPreview = Color(red: rgb.r, green: rgb.g, blue: rgb.b)
        
        // Show confirmation briefly
        withAnimation {
            showColorConfirmation = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation {
                showColorConfirmation = false
                colorPickerMode = false
                selectedColorPreview = nil
                showTapIndicator = false
            }
        }
    }
    
    /// Convert HSV to RGB for color preview
    private func hsvToRgb(h: CGFloat, s: CGFloat, v: CGFloat) -> (r: Double, g: Double, b: Double) {
        let c = v * s
        let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = v - c
        
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        
        let hue = h * 6
        if hue < 1 {
            r = c; g = x; b = 0
        } else if hue < 2 {
            r = x; g = c; b = 0
        } else if hue < 3 {
            r = 0; g = c; b = x
        } else if hue < 4 {
            r = 0; g = x; b = c
        } else if hue < 5 {
            r = x; g = 0; b = c
        } else {
            r = c; g = 0; b = x
        }
        
        return (Double(r + m), Double(g + m), Double(b + m))
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
        view.cameraManager = cameraManager  // Pass camera manager for size updates
        view.layer.addSublayer(previewLayer)
        
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {
        // Update preview layer frame when view size changes
        DispatchQueue.main.async { [weak cameraManager] in
            uiView.previewLayer?.frame = uiView.bounds
            
            // Update published size so debug mask can match
            cameraManager?.previewLayerSize = uiView.bounds.size
        }
    }
}

/// Custom UIView that properly handles the preview layer frame
class CameraPreviewUIView: UIView {
    var previewLayer: AVCaptureVideoPreviewLayer?
    weak var cameraManager: CameraManager?  // Weak reference to avoid retain cycle
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Ensure preview layer matches view bounds
        previewLayer?.frame = bounds
        
        // Update CameraManager's published size so debug mask can match
        cameraManager?.previewLayerSize = bounds.size
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

// MARK: - Color Range Indicator

/// Displays a visual representation of the current HSV color range being tracked
struct ColorRangeIndicator: View {
    let hueRange: (min: CGFloat, max: CGFloat)
    let satRange: (min: CGFloat, max: CGFloat)
    let brightRange: (min: CGFloat, max: CGFloat)
    
    var body: some View {
        VStack(spacing: 4) {
            Text("Tracking")
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
            
            // Color gradient showing the hue range
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    let hue = hueRange.min + (hueRange.max - hueRange.min) * CGFloat(index) / 4.0
                    let sat = (satRange.min + satRange.max) / 2.0 // Mid saturation
                    let bright = (brightRange.min + brightRange.max) / 2.0 // Mid brightness
                    
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color(hue: hue, saturation: sat, brightness: bright))
                        .frame(width: 12, height: 40)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.5), lineWidth: 1)
            )
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.black.opacity(0.6))
        .cornerRadius(8)
    }
}

// MARK: - Preview

#Preview {
    PuckTrackingView()
}
