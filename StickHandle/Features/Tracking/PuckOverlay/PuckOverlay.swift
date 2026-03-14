//
//  PuckOverlay.swift
//  StickHandle
//
//  Created by Tyson on 3/5/26.
//

/// Shared component for displaying puck tracking visualization
/// Used in both PuckTrackingView and ARCourseView

import SwiftUI
import ARKit

/// Red circle that shows where the puck is detected
struct PuckOverlay: View {
    let position: PuckPosition
    let viewSize: CGSize
    var transformForARKit: Bool = false
    var orientation: UIDeviceOrientation = .portrait
    var cameraIntrinsics: simd_float3x3? = nil // For distance-based sizing
    
    /// Formatted distance text (always shows value, defaults to 0ft if unavailable)
    private var distanceText: String {
        if let distance = position.estimatedDistance {
            let distanceFeet = distance * 3.28084 // Convert meters to feet
            return String(format: "%.1fft", distanceFeet)
        } else {
            return "0ft"
        }
    }
    
    var body: some View {
        let screenPosition = position.toScreenCoordinates(
            viewSize: viewSize,
            transformForARKit: transformForARKit,
            orientation: orientation
        )
        
        // Calculate display radius based on distance if available
        let displayRadius = calculateDisplayRadius()
        
        ZStack {
            // Outer circle - bright red stroke with glow effect
            Circle()
                .stroke(Color.red, lineWidth: 5)
                .frame(width: displayRadius, height: displayRadius)
                .shadow(color: .red.opacity(0.6), radius: 8, x: 0, y: 0)
            
            // Inner circle - semi-transparent fill
            Circle()
                .fill(Color.red.opacity(0.15))
                .frame(width: displayRadius, height: displayRadius)
            
            // Center dot for precise position
            Circle()
                .fill(Color.red)
                .frame(width: 12, height: 12)
                .shadow(color: .red, radius: 4, x: 0, y: 0)
            
            // Show estimated distance (always display, use 0ft if unavailable)
            Text(distanceText)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(4)
                .background(Color.black.opacity(0.7))
                .cornerRadius(4)
                .offset(y: displayRadius / 2 + 20)
        }
        .position(screenPosition)
    }
    
    /// Calculate display diameter for the puck overlay
    /// If distance is available, projects the real 3-inch puck diameter onto screen
    /// Otherwise, falls back to detected size with scaling
    /// NOTE: Returns DIAMETER (not radius) because Circle().frame(width:height:) expects diameter
    private func calculateDisplayRadius() -> CGFloat {
        // If we have distance and camera intrinsics, calculate precise screen size
        if let distance = position.estimatedDistance,
           let intrinsics = cameraIntrinsics {
            
            // Extract focal length from intrinsics
            let focalLengthX = intrinsics[0][0]
            let focalLengthY = intrinsics[1][1]
            let focalLength = (focalLengthX + focalLengthY) / 2.0
            
            // Project real puck diameter onto screen using pinhole camera model
            // apparentSize = (realSize * focalLength) / distance
            let puckDiameter = Puck.diameterMeters
            let diameterPixels = CGFloat((puckDiameter * focalLength) / distance)
            
            // ✅ BUG FIX: Convert camera sensor pixels to screen points
            // focalLength from ARKit intrinsics is in camera sensor pixels, but SwiftUI uses points
            // On a 3x retina display, 1 point = 3 pixels, so we need to divide by screen scale
            let screenScale = UIScreen.main.scale
            let diameterPoints = diameterPixels / screenScale
            
            // Apply minimum size for visibility (at least 30 points diameter)
            return max(diameterPoints, 30)
        }
        
        // Fallback: Use detected radius directly from blob detection
        // The radius from PuckPosition is already normalized and accurate from edge fitting
        let smallerDimension = min(viewSize.width, viewSize.height)
        let radiusInPoints = position.radius * smallerDimension
        
        // Convert radius to diameter for Circle frame
        // position.radius is the actual radius, so diameter = 2 × radius
        let displayDiameter = radiusInPoints * 2.0
        
        // Apply minimum size for visibility (tiny distant pucks)
        return max(displayDiameter, 30) // Minimum 30 points diameter
    }
}
