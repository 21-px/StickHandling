//
//  PuckOverlay.swift
//  StickHandle
//
//  Created by Tyson on 3/5/26.
//

/// Shared component for displaying puck tracking visualization
/// Used in both PuckTrackingView and ARCourseView

import SwiftUI

/// Red circle that shows where the puck is detected
struct PuckOverlay: View {
    let position: PuckPosition
    let viewSize: CGSize
    var transformForARKit: Bool = false
    var orientation: UIDeviceOrientation = .portrait
    
    var body: some View {
        let screenPosition = position.toScreenCoordinates(
            viewSize: viewSize,
            transformForARKit: transformForARKit,
            orientation: orientation
        )
        let radiusInPixels = position.radius * min(viewSize.width, viewSize.height)
        
        // Make circle large enough to clearly surround the puck
        // Multiply by 3 to ensure it encompasses the puck, minimum 100px
        let displayRadius = max(radiusInPixels * 3, 100)
        
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
        }
        .position(screenPosition)
    }
}
