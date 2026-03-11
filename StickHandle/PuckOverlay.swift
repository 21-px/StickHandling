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
            
            // Debug: Show estimated distance
            if let distance = position.estimatedDistance {
                Text(String(format: "%.2fm", distance))
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .padding(4)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(4)
                    .offset(y: displayRadius / 2 + 20)
            }
        }
        .position(screenPosition)
    }
    
    /// Calculate display radius for the puck overlay
    /// If distance is available, projects the real 3-inch puck diameter onto screen
    /// Otherwise, falls back to detected size with scaling
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
            let radiusPixels = diameterPixels / 2.0
            
            // Apply minimum size for visibility (at least 60px radius)
            return max(radiusPixels, 60)
        }
        
        // Fallback: Use detected radius with scaling (original behavior)
        let radiusInPixels = position.radius * min(viewSize.width, viewSize.height)
        
        // Make circle large enough to clearly surround the puck
        // Multiply by 3 to ensure it encompasses the puck, minimum 100px
        let displayRadius = max(radiusInPixels * 3, 100)
        
        return displayRadius
    }
}
