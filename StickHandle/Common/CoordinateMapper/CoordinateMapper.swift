//
//  CoordinateMapper.swift
//  StickHandle
//
//  Created by Tyson on 3/5/26.
//

/// Input: 2D puck position (normalized 0-1), AR camera transform, plane anchor
/// Transformation: Maps 2D camera coordinates to 3D AR world space coordinates
/// Output: 3D position (SIMD3<Float>) in AR world space

import Foundation
import ARKit
import simd
import Combine

/// Maps between 2D camera space and 3D AR world space
class CoordinateMapper: ObservableObject {
    
    private var planeAnchor: ARAnchor?
    private var cameraTransform: simd_float4x4?
    
    /// Update the plane anchor (floor plane detected by ARKit)
    func updatePlane(_ anchor: ARAnchor) {
        self.planeAnchor = anchor
    }
    
    /// Update the camera transform
    func updateCamera(_ transform: simd_float4x4) {
        self.cameraTransform = transform
    }
    
    /// Convert normalized 2D puck position to 3D AR world coordinates
    /// - Parameters:
    ///   - normalizedPosition: 2D position from puck tracker (0-1 range)
    ///   - viewportSize: Size of the camera viewport
    /// - Returns: 3D position in AR world space, or nil if mapping not possible
    func mapToWorldSpace(normalizedPosition: CGPoint, viewportSize: CGSize) -> SIMD3<Float>? {
        guard let anchor = planeAnchor else {
            return nil
        }
        
        // Convert normalized (0-1) to screen coordinates
        let screenX = Float(normalizedPosition.x * viewportSize.width)
        let screenY = Float(normalizedPosition.y * viewportSize.height)
        
        // For now, assume puck is on the detected plane (y = 0)
        // Use the plane's transform to position in world space
        let planeTransform = anchor.transform
        
        // Map screen position to plane coordinates
        // This is a simplified mapping - assumes camera is looking down at plane
        // X: 0-1 maps to plane width
        // Z: 0-1 maps to plane depth
        
        let planeX = Float(normalizedPosition.x - 0.5) * 2.0  // -1 to 1
        let planeZ = Float(normalizedPosition.y - 0.5) * 2.0  // -1 to 1
        
        // Transform to world space
        let localPosition = SIMD4<Float>(planeX, 0, planeZ, 1)
        let worldPosition = planeTransform * localPosition
        
        return SIMD3<Float>(worldPosition.x, worldPosition.y, worldPosition.z)
    }
    
    /// Simpler mapping for initial testing (assumes plane at origin)
    func mapToPlaneSpace(normalizedPosition: CGPoint) -> SIMD3<Float> {
        // Map 0-1 normalized coords to ~1.5m x 1.5m area on floor
        // This gives us a reasonable play area
        let x = Float(normalizedPosition.x - 0.5) * 1.5
        let z = Float(normalizedPosition.y - 0.5) * 1.5
        
        return SIMD3<Float>(x, 0, z)
    }
}
