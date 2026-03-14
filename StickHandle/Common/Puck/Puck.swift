//
//  Puck.swift
//  StickHandle
//
//  Created by Tyson on 3/10/26.
//

/// Physical specifications for a hockey puck
/// Used for accurate AR tracking and visualization

import Foundation

/// Standard hockey puck dimensions
struct Puck {
    
    // MARK: - Physical Dimensions
    
    /// Diameter of the puck in inches (3 inches)
    static let diameterInches: Float = 3.0
    
    /// Height/thickness of the puck in inches (1 inch)
    static let heightInches: Float = 1.0
    
    /// Diameter of the puck in meters (0.0762 meters)
    static let diameterMeters: Float = 0.0762
    
    /// Height/thickness of the puck in meters (0.0254 meters)
    static let heightMeters: Float = 0.0254
    
    /// Radius of the puck in meters (0.0381 meters)
    static let radiusMeters: Float = 0.0381
    
    // MARK: - Computed Properties
    
    /// Convert inches to meters
    /// - Parameter inches: Value in inches
    /// - Returns: Value in meters
    static func inchesToMeters(_ inches: Float) -> Float {
        return inches * 0.0254
    }
    
    /// Convert meters to inches
    /// - Parameter meters: Value in meters
    /// - Returns: Value in inches
    static func metersToInches(_ meters: Float) -> Float {
        return meters / 0.0254
    }
}
