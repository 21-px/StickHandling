//
//  PuckTracker.swift
//  StickHandle
//
//  Created by Tyson on 3/4/26.
//

/// Input: CVPixelBuffer (video frame from camera), target color (HSV range for bright green)
/// Transformation: Uses color filtering to detect green regions (color blobs), finds center of mass and size. Works at long distances by accepting any green blob above minimum size threshold.
/// Output: PuckPosition struct with normalized coordinates (0-1 range for x, y) and confidence score based on blob size, or nil if no puck detected

import Vision
import CoreImage
import UIKit
import Combine

/// Tracks a bright green puck in video frames using color-based detection
@MainActor
class PuckTracker: ObservableObject {
    
    // Published property so SwiftUI views can react to puck position changes
    // Like updating React state with setPuckPosition()
    @Published var puckPosition: PuckPosition?
    @Published var isTracking: Bool = false
    @Published var trackingConfidence: Float = 0.0
    @Published var debugImage: UIImage? // For showing color mask in debug mode
    
    // Color detection parameters for puck
    // HSV (Hue, Saturation, Value) is better than RGB for color detection
    // These values are loaded from UserDefaults or use default green values
    @Published var targetHue: (min: CGFloat, max: CGFloat)
    @Published var targetSaturation: (min: CGFloat, max: CGFloat)
    @Published var targetBrightness: (min: CGFloat, max: CGFloat)
    
    // UserDefaults keys for persisting color selection
    private let hueMinKey = "com.stickhandle.puck.hue.min"
    private let hueMaxKey = "com.stickhandle.puck.hue.max"
    private let satMinKey = "com.stickhandle.puck.sat.min"
    private let satMaxKey = "com.stickhandle.puck.sat.max"
    private let brightMinKey = "com.stickhandle.puck.bright.min"
    private let brightMaxKey = "com.stickhandle.puck.bright.max"
    private let lidarEnabledKey = "com.stickhandle.puck.lidar.enabled"
    
    // LiDAR setting
    @Published var lidarEnabled: Bool
    
    // Store the current frame for color picking
    nonisolated(unsafe) private var currentFrame: CVPixelBuffer?
    
    // Debug mode to visualize color detection
    nonisolated(unsafe) var debugMode: Bool = false
    
    nonisolated(unsafe) private var lastDetectionTime = Date()
    private let detectionTimeout: TimeInterval = 0.5 // If no detection for 0.5s, mark as not tracking
    
    // Temporal smoothing to reduce jitter
    nonisolated(unsafe) private var smoothedPosition: CGPoint?
    nonisolated(unsafe) private var smoothedRadius: CGFloat?
    private let smoothingFactor: CGFloat = 0.5 // Lower = smoother but more lag, higher = snappier (0.5 = balanced)
    
    // Frame throttling for performance
    nonisolated(unsafe) private var frameCount: Int = 0
    private let processEveryNthFrame = 1 // Process every frame now that we've optimized
    
    // Processing queue for background work
    nonisolated(unsafe) private let processingQueue = DispatchQueue(label: "com.stickhandle.processing", qos: .userInitiated)
    
    // Core Image context for image processing (reuse for efficiency)
    nonisolated(unsafe) private let ciContext = CIContext(options: [.useSoftwareRenderer: false, .priorityRequestLow: false])
    
    // Cache the color cube to avoid recreating it every frame
    // Will be regenerated when color changes
    nonisolated(unsafe) private var colorCubeData: Data
    
    init() {
        // Load saved color values or use defaults (bright green)
        let defaults = UserDefaults.standard
        
        // Initialize all stored properties first
        let loadedHue = (
            min: CGFloat(defaults.double(forKey: hueMinKey)).ifZero(0.20),
            max: CGFloat(defaults.double(forKey: hueMaxKey)).ifZero(0.50)
        )
        
        let loadedSat = (
            min: CGFloat(defaults.double(forKey: satMinKey)).ifZero(0.3),
            max: CGFloat(defaults.double(forKey: satMaxKey)).ifZero(1.0)
        )
        
        let loadedBright = (
            min: CGFloat(defaults.double(forKey: brightMinKey)).ifZero(0.3),
            max: CGFloat(defaults.double(forKey: brightMaxKey)).ifZero(1.0)
        )
        
        // Assign to self after computing values
        self.targetHue = loadedHue
        self.targetSaturation = loadedSat
        self.targetBrightness = loadedBright
        
        // Load LiDAR setting (default to false)
        self.lidarEnabled = defaults.bool(forKey: lidarEnabledKey)
        
        // Create initial color cube with loaded/default values
        self.colorCubeData = Self.createColorCube(
            hue: loadedHue,
            saturation: loadedSat,
            brightness: loadedBright
        )
    }
    
    /// Process a video frame to detect the green puck
    /// Call this for each frame from the camera
    nonisolated func processFrame(_ pixelBuffer: CVPixelBuffer, cameraIntrinsics: simd_float3x3? = nil, lidarDistance: Float? = nil) {
        // Store the current frame for potential color picking
        currentFrame = pixelBuffer
        
        // Throttle frame processing for performance
        frameCount += 1
        if frameCount % processEveryNthFrame != 0 {
            return
        }
        
        // Capture orientation on main actor before going to background queue
        // UIDevice.current.orientation can ONLY be read on main thread
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // Process on background queue to avoid blocking main thread
            self.processingQueue.async { [weak self, pixelBuffer, cameraIntrinsics, lidarDistance] in
                guard let self = self else { return }
                
                // Convert pixel buffer to CIImage for processing
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                
                // Get image dimensions for distance estimation
                // IMPORTANT: Use SCALED dimensions (160px width) because detection happens on the scaled image!
                // The normalized radius is relative to the scaled image, not the original full-res image
                let originalWidth = ciImage.extent.width
                let originalHeight = ciImage.extent.height
                let scaledWidth = 160
                let scaledHeight = Int(160.0 / originalWidth * originalHeight)
                
                // Calculate scale factor for intrinsics
                let scaleFactorX = CGFloat(scaledWidth) / originalWidth
                let scaleFactorY = CGFloat(scaledHeight) / originalHeight
                
                // Detect green regions in the image
                if let position = self.detectGreenPuck(in: ciImage, pixelBuffer: pixelBuffer) {
                    // Estimate distance - prefer LiDAR, fallback to camera intrinsics
                    var positionWithDistance = position
                    
                    if let lidarDist = lidarDistance {
                        // Use LiDAR distance (most accurate!)
                        positionWithDistance = PuckPosition(
                            x: position.x,
                            y: position.y,
                            radius: position.radius,
                            confidence: position.confidence,
                            estimatedDistance: lidarDist
                        )
                    } else if let intrinsics = cameraIntrinsics {
                        // Fallback: estimate from puck size using camera intrinsics
                        // Scale the intrinsics to match the scaled image dimensions
                        var scaledIntrinsics = intrinsics
                        scaledIntrinsics[0][0] = intrinsics[0][0] * Float(scaleFactorX)  // fx
                        scaledIntrinsics[1][1] = intrinsics[1][1] * Float(scaleFactorY)  // fy
                        scaledIntrinsics[2][0] = intrinsics[2][0] * Float(scaleFactorX)  // cx
                        scaledIntrinsics[2][1] = intrinsics[2][1] * Float(scaleFactorY)  // cy
                        
                        let distance = self.estimateDistance(
                            detectedRadiusNormalized: position.radius,
                            imageWidth: scaledWidth,
                            imageHeight: scaledHeight,
                            intrinsics: scaledIntrinsics
                        )
                        positionWithDistance = PuckPosition(
                            x: position.x,
                            y: position.y,
                            radius: position.radius,
                            confidence: position.confidence,
                            estimatedDistance: distance
                        )
                    }
                    
                    // Apply temporal smoothing to reduce jitter
                    let smoothedPosition = self.applySmoothing(to: positionWithDistance)
                    
                    Task { @MainActor [weak self] in
                        guard let self = self else { return }
                        self.puckPosition = smoothedPosition
                        self.isTracking = true
                        self.trackingConfidence = smoothedPosition.confidence
                        self.lastDetectionTime = Date()
                    }
                } else {
                    // Check if we've lost tracking
                    let timeSinceLastDetection = Date().timeIntervalSince(self.lastDetectionTime)
                    if timeSinceLastDetection > self.detectionTimeout {
                        Task { @MainActor [weak self] in
                            guard let self = self else { return }
                            self.isTracking = false
                            self.trackingConfidence = 0.0
                        }
                        // Reset smoothing when tracking is lost
                        self.smoothedPosition = nil
                        self.smoothedRadius = nil
                    }
                }
            }
        }
    }
    
    /// Enable or disable debug visualization
    func setDebugMode(_ enabled: Bool) {
        debugMode = enabled
    }
    
    /// Enable or disable LiDAR distance measurement
    func setLidarEnabled(_ enabled: Bool) {
        lidarEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: lidarEnabledKey)
    }
    
    /// Estimate distance to puck using pinhole camera model
    /// Distance = (RealSize * FocalLength) / ApparentSize
    /// - Parameters:
    ///   - detectedRadiusNormalized: Detected radius in normalized coordinates (0-1)
    ///   - imageWidth: Image width in pixels
    ///   - imageHeight: Image height in pixels
    ///   - intrinsics: Camera intrinsic matrix (contains focal length)
    /// - Returns: Estimated distance in meters, or nil if calculation fails
    nonisolated private func estimateDistance(
        detectedRadiusNormalized: CGFloat,
        imageWidth: Int,
        imageHeight: Int,
        intrinsics: simd_float3x3
    ) -> Float? {
        // Extract focal length from intrinsics matrix
        // intrinsics[0][0] = fx (focal length in x)
        // intrinsics[1][1] = fy (focal length in y)
        let focalLengthX = intrinsics[0][0]
        let focalLengthY = intrinsics[1][1]
        
        // Use average focal length for more stable results
        let focalLength = (focalLengthX + focalLengthY) / 2.0
        
        // Convert normalized radius to pixels
        // Radius is normalized against the smaller dimension
        let smallerDimension = min(imageWidth, imageHeight)
        let radiusPixels = Float(detectedRadiusNormalized) * Float(smallerDimension)
        
        // Diameter in pixels = 2 * radius
        let diameterPixels = radiusPixels * 2.0
        
        // Real puck diameter in meters
        let realDiameter = Puck.diameterMeters
        
        // Pinhole camera formula: distance = (realSize * focalLength) / apparentSize
        guard diameterPixels > 0 else {
            return nil
        }
        let distance = (realDiameter * focalLength) / diameterPixels
        
        // Sanity check: puck should be between 0.1m and 10m away
        guard distance > 0.1 && distance < 10.0 else {
            return nil
        }
        
        return distance
    }
    
    /// Apply temporal smoothing to reduce jitter in puck tracking
    /// Uses exponential moving average: new = (alpha * current) + ((1-alpha) * previous)
    nonisolated private func applySmoothing(to position: PuckPosition) -> PuckPosition {
        guard let previous = smoothedPosition, let prevRadius = smoothedRadius else {
            // First detection, no smoothing
            smoothedPosition = CGPoint(x: position.x, y: position.y)
            smoothedRadius = position.radius
            return position
        }
        
        // Exponential moving average
        // smoothingFactor controls how much we trust the new measurement vs. previous position
        // Lower values = smoother but more lag, higher values = more responsive but less smooth
        let newX = smoothingFactor * position.x + (1 - smoothingFactor) * previous.x
        let newY = smoothingFactor * position.y + (1 - smoothingFactor) * previous.y
        let newRadius = smoothingFactor * position.radius + (1 - smoothingFactor) * prevRadius
        
        // Update stored values for next frame
        smoothedPosition = CGPoint(x: newX, y: newY)
        smoothedRadius = newRadius
        
        return PuckPosition(
            x: newX,
            y: newY,
            radius: newRadius,
            confidence: position.confidence,
            estimatedDistance: position.estimatedDistance  // ✅ Preserve distance!
        )
    }
    
    /// Extract color at a specific normalized point in the current frame
    /// - Parameter normalizedPoint: Point in 0-1 range (x, y)
    /// - Returns: HSV color at that point, or nil if no frame available
    func getColorAt(normalizedPoint: CGPoint) -> (h: CGFloat, s: CGFloat, v: CGFloat)? {
        guard let pixelBuffer = currentFrame else { return nil }
        
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        // Convert normalized coordinates to pixel coordinates
        let x = Int(normalizedPoint.x * CGFloat(width))
        let y = Int(normalizedPoint.y * CGFloat(height))
        
        // Sample a small region around the point to average out camera noise
        // Using 3x3 grid (9 pixels) for accurate but noise-resistant sampling
        let sampleSize = 1  // -1 to +1 = 3x3 grid
        var rSum: CGFloat = 0
        var gSum: CGFloat = 0
        var bSum: CGFloat = 0
        var sampleCount = 0
        
        for dy in -sampleSize...sampleSize {
            for dx in -sampleSize...sampleSize {
                let px = max(0, min(width - 1, x + dx))
                let py = max(0, min(height - 1, y + dy))
                
                // Extract RGB values at this pixel
                if let rgb = getPixelColor(ciImage: ciImage, x: px, y: py, width: width, height: height) {
                    rSum += rgb.r
                    gSum += rgb.g
                    bSum += rgb.b
                    sampleCount += 1
                }
            }
        }
        
        guard sampleCount > 0 else { return nil }
        
        let r = rSum / CGFloat(sampleCount)
        let g = gSum / CGFloat(sampleCount)
        let b = bSum / CGFloat(sampleCount)
        
        return rgbToHsv(r: r, g: g, b: b)
    }
    
    /// Helper to extract RGB color from a CIImage at specific pixel
    nonisolated private func getPixelColor(ciImage: CIImage, x: Int, y: Int, width: Int, height: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        // Create a 1x1 crop of the image at the specified pixel
        let cropRect = CGRect(x: x, y: y, width: 1, height: 1)
        let croppedImage = ciImage.cropped(to: cropRect)
        
        // Render to get pixel data
        var bitmap = [UInt8](repeating: 0, count: 4)
        ciContext.render(croppedImage, toBitmap: &bitmap, rowBytes: 4, bounds: cropRect, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())
        
        return (
            r: CGFloat(bitmap[0]) / 255.0,
            g: CGFloat(bitmap[1]) / 255.0,
            b: CGFloat(bitmap[2]) / 255.0
        )
    }
    
    /// Update the target color for puck detection
    /// - Parameter hsv: The HSV color to target
    func updateTargetColor(hsv: (h: CGFloat, s: CGFloat, v: CGFloat)) {
        // Create a WIDE range around the selected color for robust tracking in various lighting conditions
        // Wider ranges help handle shadows, highlights, different ambient lighting, and reflections
        
        // Hue: ±0.15 (±54°) - much wider to handle color shifts from lighting
        let hueRange: CGFloat = 0.15
        
        // Saturation: Accept from 0.1 to 1.0 - handles both washed-out colors (bright light) 
        // and highly saturated colors (normal conditions)
        // This allows the same color to be tracked whether it's in shadow, direct light, or reflection
        let satMin: CGFloat = 0.2  // Very low threshold - even desaturated colors match
        let satMax: CGFloat = 0.98  // Always accept up to fully saturated
        
        // Brightness: Accept from 0.2 to 1.0 - handles shadows (darker) and highlights (brighter)
        // This is critical for tracking across varying lighting conditions
        let brightMin: CGFloat = 0.2  // Low threshold for shadows
        let brightMax: CGFloat = 0.98  // Always accept up to fully bright
        
        targetHue = (
            min: max(0, hsv.h - hueRange),
            max: min(1, hsv.h + hueRange)
        )
        
        // Use absolute ranges for saturation and brightness instead of ranges around picked value
        // This prevents the ranges from becoming too restrictive based on the picked sample
        targetSaturation = (
            min: satMin,
            max: satMax
        )
        
        targetBrightness = (
            min: brightMin,
            max: brightMax
        )
        
        // Save to UserDefaults
        let defaults = UserDefaults.standard
        defaults.set(Double(targetHue.min), forKey: hueMinKey)
        defaults.set(Double(targetHue.max), forKey: hueMaxKey)
        defaults.set(Double(targetSaturation.min), forKey: satMinKey)
        defaults.set(Double(targetSaturation.max), forKey: satMaxKey)
        defaults.set(Double(targetBrightness.min), forKey: brightMinKey)
        defaults.set(Double(targetBrightness.max), forKey: brightMaxKey)
        
        // Regenerate color cube with new values
        colorCubeData = Self.createColorCube(
            hue: targetHue,
            saturation: targetSaturation,
            brightness: targetBrightness
        )
    }
    
    /// Detect the green puck in an image using color filtering
    nonisolated private func detectGreenPuck(in image: CIImage, pixelBuffer: CVPixelBuffer) -> PuckPosition? {
        
        // Store original image size before scaling
        let originalWidth = image.extent.width
        let originalHeight = image.extent.height
        
        // Apply color threshold filter to isolate bright green
        guard let greenMask = createColorMask(for: image) else {
            return nil
        }
        
        // In debug mode, convert mask to UIImage for visualization
        // Use FULL RESOLUTION mask for proper edge-to-edge display
        if debugMode {
            // Create full-resolution mask for debug display
            let fullResMask = createColorMask(for: image, skipScaling: true)
            if let fullResMask = fullResMask {
                if let cgImage = ciContext.createCGImage(fullResMask, from: fullResMask.extent) {
                    Task { @MainActor [weak self] in
                        // FIX: Use screen scale for retina displays
                        // Without scale parameter, UIImage defaults to 1.0 which causes incorrect rendering on retina displays
                        // The image gets cropped/offset when .scaledToFill() is applied
                        let screenScale = UIScreen.main.scale
                        self?.debugImage = UIImage(cgImage: cgImage, scale: screenScale, orientation: .up)
                    }
                }
            }
        }
        
        // Convert mask to CGImage to analyze pixel data
        guard let cgImage = ciContext.createCGImage(greenMask, from: greenMask.extent) else {
            return nil
        }
        
        // Find the largest green blob (returns coordinates in scaled image space)
        if let detection = findLargestGreenBlob(in: cgImage, originalSize: CGSize(width: originalWidth, height: originalHeight)) {
            return detection
        }
        
        return nil
    }
    
    /// Find the largest green region in the masked image
    /// Input: CGImage (binary mask where white = green puck pixels), original image size
    /// Transformation: Analyzes pixel distribution, calculates center of mass, checks if blob is reasonable size
    /// Output: PuckPosition with normalized coordinates and confidence based on blob size and shape
    nonisolated private func findLargestGreenBlob(in image: CGImage, originalSize: CGSize) -> PuckPosition? {
        let width = image.width
        let height = image.height
        
        // Create bitmap context to read pixel data
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = context.data else {
            return nil
        }
        
        let buffer = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        
        // Less aggressive downsampling for more stable detection
        // Check every 2nd pixel (4x faster than checking every pixel, but more accurate than step=3)
        let sampleStep = 2
        
        // Find all white pixels (green regions in the mask)
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        var pixelCount: Int = 0
        var minX: Int = width
        var maxX: Int = 0
        var minY: Int = height
        var maxY: Int = 0
        
        // Collect edge pixels for circle fitting
        var edgePixels: [(x: Int, y: Int)] = []
        
        // Use stride for faster iteration
        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let offset = (y * width + x) * 4
                
                // Fast check: only look at one color channel first
                guard buffer[offset] > 128 else { continue }
                
                let r = buffer[offset]
                let g = buffer[offset + 1]
                let b = buffer[offset + 2]
                
                // Check if pixel is white (part of green mask)
                if r > 128 && g > 128 && b > 128 {
                    sumX += CGFloat(x)
                    sumY += CGFloat(y)
                    pixelCount += 1
                    
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                    
                    // Check if this is an edge pixel (has at least one non-white neighbor)
                    let isEdge = isEdgePixel(buffer: buffer, x: x, y: y, width: width, height: height, step: sampleStep)
                    if isEdge {
                        edgePixels.append((x, y))
                    }
                }
            }
        }
        
        // Need at least some pixels to consider it a detection
        // Low threshold for distance tracking, but not so low that noise triggers false positives
        // With sampleStep=2, we're checking 25% of pixels, so scale threshold accordingly
        let minPixels = 3 // Requires at least 3 sampled pixels (equivalent to ~12 actual pixels)
        guard pixelCount > minPixels else {
            return nil
        }
        
        // Calculate center of mass in scaled image space (initial estimate)
        let centerX = sumX / CGFloat(pixelCount)
        let centerY = sumY / CGFloat(pixelCount)
        
        // Try circle fitting if we have edge pixels
        var fittedCircle: (center: CGPoint, radius: CGFloat)?
        if edgePixels.count >= 5 { // Need at least 5 points to fit a circle
            fittedCircle = fitCircleToEdges(edgePixels: edgePixels, initialCenter: CGPoint(x: centerX, y: centerY))
        }
        
        // Use fitted circle if available and reasonable, otherwise fall back to centroid method
        let finalCenterX: CGFloat
        let finalCenterY: CGFloat
        let finalRadius: CGFloat
        var isPartialCircle = false
        
        if let fitted = fittedCircle {
            // Validate fitted circle is reasonable
            let fittedNormRadius = fitted.radius / CGFloat(min(width, height))
            if fittedNormRadius > 0.005 && fittedNormRadius < 0.6 {
                // Fitted circle is reasonable - use it!
                finalCenterX = fitted.center.x
                finalCenterY = fitted.center.y
                finalRadius = fitted.radius
                isPartialCircle = true // Mark that we used edge-based detection
            } else {
                // Fitted circle is unreasonable, fall back to centroid
                finalCenterX = centerX
                finalCenterY = centerY
                
                // Calculate bounding box size (for confidence checks)
                let bboxWidth = maxX - minX
                let bboxHeight = maxY - minY
                let bboxRadius = max(bboxWidth, bboxHeight) / 2
                
                // Calculate RMS radius
                let rmsRadius = calculateRMSRadius(buffer: buffer, width: width, height: height, 
                                                   centerX: centerX, centerY: centerY, sampleStep: sampleStep)
                
                if rmsRadius > 0 && rmsRadius < CGFloat(bboxRadius) * 2.0 {
                    finalRadius = rmsRadius
                } else {
                    finalRadius = CGFloat(bboxRadius)
                }
            }
        } else {
            // No fitted circle - use traditional centroid method
            finalCenterX = centerX
            finalCenterY = centerY
            
            // Calculate bounding box size (for confidence checks)
            let bboxWidth = maxX - minX
            let bboxHeight = maxY - minY
            let bboxRadius = max(bboxWidth, bboxHeight) / 2
            
            // Calculate RMS radius
            let rmsRadius = calculateRMSRadius(buffer: buffer, width: width, height: height, 
                                               centerX: centerX, centerY: centerY, sampleStep: sampleStep)
            
            if rmsRadius > 0 && rmsRadius < CGFloat(bboxRadius) * 2.0 {
                finalRadius = rmsRadius
            } else {
                finalRadius = CGFloat(bboxRadius)
            }
        }
        
        // Normalize coordinates (0-1) relative to the SCALED image
        let normalizedX = finalCenterX / CGFloat(width)
        let normalizedY = finalCenterY / CGFloat(height)
        let normalizedRadius = finalRadius / CGFloat(min(width, height))
        
        // SIMPLIFIED CONFIDENCE CALCULATION FOR DISTANCE TRACKING
        // At distance, downscaling makes pucks lose circular shape, so we just check:
        // 1. Blob is reasonable size (not too tiny = noise, not too huge = not puck)
        // 2. Has enough pixels to be real
        
        // EXTREMELY permissive size range for maximum distance tracking
        let minReasonableSize: CGFloat = 0.00001 // Essentially no minimum - allows tiny distant pucks
        let maxReasonableSize: CGFloat = 0.5     // Larger max - allows close pucks
        let isReasonableSize = normalizedRadius >= minReasonableSize && normalizedRadius <= maxReasonableSize
        
        guard isReasonableSize else {
            return nil // Filter out noise (too small) or false positives (too large)
        }
        
        // Calculate confidence based on size
        // Optimal size is around 0.05-0.15 (medium distance)
        // But we accept anything from minReasonableSize to maxReasonableSize
        let optimalMinSize: CGFloat = 0.03
        let optimalMaxSize: CGFloat = 0.2
        
        var confidence: Float = 0.0
        
        if normalizedRadius >= optimalMinSize && normalizedRadius <= optimalMaxSize {
            // Optimal range - high confidence
            confidence = 0.9
        } else if normalizedRadius < optimalMinSize {
            // Small but visible - scale confidence with size
            // Use log scale for very small sizes to avoid confidence dropping to zero
            let minConfidence: Float = 0.3 // Even tiniest blobs get 30% confidence
            let sizeRatio = Float(max(0, min(1, (normalizedRadius - minReasonableSize) / (optimalMinSize - minReasonableSize))))
            confidence = minConfidence + (sizeRatio * 0.6) // 0.3 to 0.9
        } else {
            // Large - scale confidence down as it gets bigger
            let sizeRatio = Float((normalizedRadius - optimalMaxSize) / (maxReasonableSize - optimalMaxSize))
            confidence = 0.9 - (sizeRatio * 0.4) // 0.9 to 0.5
        }
        
        // Boost confidence if we detected a partial circle (edge-based fitting)
        if isPartialCircle {
            confidence = min(1.0, confidence * 1.2) // 20% confidence boost for circular edge detection
        }
        
        // Calculate bounding box for aspect ratio check
        let bboxWidth = maxX - minX
        let bboxHeight = maxY - minY
        
        // Check aspect ratio as a basic sanity check (not too elongated)
        // This helps filter out obvious non-puck shapes without requiring perfect circles
        let aspectRatio = CGFloat(bboxWidth) / CGFloat(max(bboxHeight, 1))
        let isReasonablyRound = aspectRatio > 0.3 && aspectRatio < 3.0 // Even more permissive
        
        if !isReasonablyRound {
            confidence *= 0.7 // Reduce confidence less aggressively
        }
        
        // VERY low minimum confidence threshold for distance tracking
        guard confidence > 0.2 else {
            return nil
        }
        
        let position = PuckPosition(
            x: normalizedX,
            y: normalizedY,
            radius: normalizedRadius,
            confidence: confidence
        )
        
        return position
    }
    
    /// Check if a pixel is on the edge of the colored region
    nonisolated private func isEdgePixel(buffer: UnsafeMutablePointer<UInt8>, x: Int, y: Int, width: Int, height: Int, step: Int) -> Bool {
        // A pixel is an edge if it's white but has at least one non-white neighbor
        let directions = [(-step, 0), (step, 0), (0, -step), (0, step)] // Left, right, up, down
        
        for (dx, dy) in directions {
            let nx = x + dx
            let ny = y + dy
            
            // Check bounds
            guard nx >= 0 && nx < width && ny >= 0 && ny < height else {
                return true // Border pixels are considered edges
            }
            
            let offset = (ny * width + nx) * 4
            let neighborR = buffer[offset]
            
            // If neighbor is black (not part of blob), this is an edge
            if neighborR < 128 {
                return true
            }
        }
        
        return false
    }
    
    /// Calculate RMS (root mean square) radius for subpixel accuracy
    nonisolated private func calculateRMSRadius(buffer: UnsafeMutablePointer<UInt8>, width: Int, height: Int, 
                                                centerX: CGFloat, centerY: CGFloat, sampleStep: Int) -> CGFloat {
        var sumSquaredDistance: CGFloat = 0
        var distanceCount: Int = 0
        
        for y in stride(from: 0, to: height, by: sampleStep) {
            for x in stride(from: 0, to: width, by: sampleStep) {
                let offset = (y * width + x) * 4
                guard buffer[offset] > 128 else { continue }
                
                let r = buffer[offset]
                let g = buffer[offset + 1]
                let b = buffer[offset + 2]
                
                if r > 128 && g > 128 && b > 128 {
                    let dx = CGFloat(x) - centerX
                    let dy = CGFloat(y) - centerY
                    sumSquaredDistance += dx * dx + dy * dy
                    distanceCount += 1
                }
            }
        }
        
        return sqrt(sumSquaredDistance / CGFloat(max(distanceCount, 1)))
    }
    
    /// Fit a circle to edge pixels using least squares optimization
    /// This allows detecting partially occluded pucks by fitting a circle to visible arc
    /// Returns: (center, radius) of fitted circle, or nil if fitting fails
    nonisolated private func fitCircleToEdges(edgePixels: [(x: Int, y: Int)], initialCenter: CGPoint) -> (center: CGPoint, radius: CGFloat)? {
        guard edgePixels.count >= 5 else { return nil }
        
        // Use algebraic circle fitting (Pratt method)
        // This is fast and works well for partial circles
        
        var centerX = initialCenter.x
        var centerY = initialCenter.y
        var radius: CGFloat = 0
        
        // Iterative refinement (5 iterations for better accuracy)
        for iteration in 0..<5 {
            // Calculate distances from current center estimate
            var sumDist: CGFloat = 0
            var validPoints = 0
            
            for point in edgePixels {
                let dx = CGFloat(point.x) - centerX
                let dy = CGFloat(point.y) - centerY
                let dist = sqrt(dx * dx + dy * dy)
                
                // On first iteration, accept all points
                // On subsequent iterations, only use inliers (within tolerance)
                if iteration == 0 || (iteration > 0 && abs(dist - radius) < max(radius * 0.4, 3.0)) {
                    sumDist += dist
                    validPoints += 1
                }
            }
            
            guard validPoints > 0 else { break }
            radius = sumDist / CGFloat(validPoints)
            
            // Update center estimate using weighted average
            var sumX: CGFloat = 0
            var sumY: CGFloat = 0
            var totalWeight: CGFloat = 0
            
            for point in edgePixels {
                let px = CGFloat(point.x)
                let py = CGFloat(point.y)
                let dx = px - centerX
                let dy = py - centerY
                let dist = sqrt(dx * dx + dy * dy)
                
                guard dist > 0.1 else { continue }
                
                // Weight by inverse distance from expected radius
                // Points closer to the expected circle get MUCH higher weight
                let distanceFromCircle = abs(dist - radius)
                let weight = 1.0 / (1.0 + distanceFromCircle * distanceFromCircle) // Squared for stronger weighting
                
                sumX += px * weight
                sumY += py * weight
                totalWeight += weight
            }
            
            guard totalWeight > 0 else { break }
            
            let newCenterX = sumX / totalWeight
            let newCenterY = sumY / totalWeight
            
            // Check for convergence (if center barely moves, we're done)
            let centerShift = sqrt(pow(newCenterX - centerX, 2) + pow(newCenterY - centerY, 2))
            centerX = newCenterX
            centerY = newCenterY
            
            if centerShift < 0.1 {
                break // Converged!
            }
        }
        
        // Final radius calculation using only inliers for maximum accuracy
        var finalRadiusSum: CGFloat = 0
        var inlierCount = 0
        let tolerance = max(radius * 0.3, 2.0) // 30% tolerance or 2 pixels
        
        for point in edgePixels {
            let dx = CGFloat(point.x) - centerX
            let dy = CGFloat(point.y) - centerY
            let dist = sqrt(dx * dx + dy * dy)
            
            if abs(dist - radius) < tolerance {
                finalRadiusSum += dist
                inlierCount += 1
            }
        }
        
        // Need at least 1/3 of edge pixels to be inliers for a good fit
        let inlierRatio = CGFloat(inlierCount) / CGFloat(edgePixels.count)
        guard inlierRatio >= 0.33 else { return nil }
        
        // Use average of inlier distances as final radius for accuracy
        let finalRadius = inlierCount > 0 ? finalRadiusSum / CGFloat(inlierCount) : radius
        
        return (center: CGPoint(x: centerX, y: centerY), radius: finalRadius)
    }
    
    /// Create a binary mask highlighting green regions
    /// - Parameters:
    ///   - image: Input image
    ///   - skipScaling: If true, creates full-resolution mask (for debug display)
    nonisolated private func createColorMask(for image: CIImage, skipScaling: Bool = false) -> CIImage? {
        
        let inputImage: CIImage
        
        if skipScaling {
            // Full resolution for debug display
            inputImage = image
        } else {
            // Reduce image size even MORE for maximum speed
            // Scale down to 160px wide - much faster, still accurate enough for tracking
            let scale = 160.0 / image.extent.width
            inputImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        
        // Use cached color cube data instead of recreating every frame
        let cubeSize = 64
        
        let colorCube = CIFilter(name: "CIColorCube")
        colorCube?.setValue(cubeSize, forKey: "inputCubeDimension")
        colorCube?.setValue(colorCubeData, forKey: "inputCubeData")
        colorCube?.setValue(inputImage, forKey: kCIInputImageKey)
        
        return colorCube?.outputImage
    }
    
    /// Create a color lookup table that passes through the target color and blacks out other colors
    private static func createColorCube(
        hue: (min: CGFloat, max: CGFloat),
        saturation: (min: CGFloat, max: CGFloat),
        brightness: (min: CGFloat, max: CGFloat)
    ) -> Data {
        let cubeSize = 64
        let cubeDataSize = cubeSize * cubeSize * cubeSize * 4 // RGBA
        var cubeData = [Float](repeating: 0, count: cubeDataSize)
        
        var offset = 0
        for blue in 0..<cubeSize {
            for green in 0..<cubeSize {
                for red in 0..<cubeSize {
                    // Convert RGB to normalized 0-1
                    let r = CGFloat(red) / CGFloat(cubeSize - 1)
                    let g = CGFloat(green) / CGFloat(cubeSize - 1)
                    let b = CGFloat(blue) / CGFloat(cubeSize - 1)
                    
                    // Convert RGB to HSV
                    let hsv = rgbToHsvStatic(r: r, g: g, b: b)
                    
                    // Check if this color is in our target range
                    let isTargetColor = hsv.h >= hue.min && hsv.h <= hue.max &&
                                        hsv.s >= saturation.min && hsv.s <= saturation.max &&
                                        hsv.v >= brightness.min && hsv.v <= brightness.max
                    
                    if isTargetColor {
                        // Keep the color (white in mask)
                        cubeData[offset] = 1.0 // R
                        cubeData[offset + 1] = 1.0 // G
                        cubeData[offset + 2] = 1.0 // B
                        cubeData[offset + 3] = 1.0 // A
                    } else {
                        // Make it black (not target color)
                        cubeData[offset] = 0.0
                        cubeData[offset + 1] = 0.0
                        cubeData[offset + 2] = 0.0
                        cubeData[offset + 3] = 1.0
                    }
                    
                    offset += 4
                }
            }
        }
        
        return cubeData.withUnsafeBufferPointer { Data(buffer: $0) }
    }
    
    /// Convert RGB to HSV color space (static version for use in static methods)
    private static func rgbToHsvStatic(r: CGFloat, g: CGFloat, b: CGFloat) -> (h: CGFloat, s: CGFloat, v: CGFloat) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC
        
        var h: CGFloat = 0
        let s: CGFloat = maxC == 0 ? 0 : delta / maxC
        let v: CGFloat = maxC
        
        if delta != 0 {
            if maxC == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                h = (b - r) / delta + 2
            } else {
                h = (r - g) / delta + 4
            }
            h /= 6
            if h < 0 {
                h += 1
            }
        }
        
        return (h, s, v)
    }
    
    /// Convert RGB to HSV color space
    nonisolated private func rgbToHsv(r: CGFloat, g: CGFloat, b: CGFloat) -> (h: CGFloat, s: CGFloat, v: CGFloat) {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC
        
        var h: CGFloat = 0
        let s: CGFloat = maxC == 0 ? 0 : delta / maxC
        let v: CGFloat = maxC
        
        if delta != 0 {
            if maxC == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                h = (b - r) / delta + 2
            } else {
                h = (r - g) / delta + 4
            }
            h /= 6
            if h < 0 {
                h += 1
            }
        }
        
        return (h, s, v)
    }
}

// MARK: - Helper Extensions

extension CGFloat {
    /// Return self if non-zero, otherwise return the provided default
    func ifZero(_ defaultValue: CGFloat) -> CGFloat {
        return self == 0 ? defaultValue : self
    }
}

// MARK: - Data Models

/// Represents the detected position of the puck
/// Coordinates are normalized (0-1) relative to the image
struct PuckPosition {
    let x: CGFloat // Horizontal position (0 = left, 1 = right)
    let y: CGFloat // Vertical position (0 = top, 1 = bottom)
    let radius: CGFloat // Radius of detected puck (normalized)
    let confidence: Float // Confidence score 0-1
    var estimatedDistance: Float? // Estimated distance to puck in meters (if available)
    
    /// Convert normalized coordinates to screen coordinates
    /// - Parameter viewSize: The size of the view (in screen coordinates)
    /// - Parameter orientation: The device orientation (for ARKit coordinate transformation)
    /// - Returns: Screen position in points
    ///
    /// **Coordinate Transformation for ARKit:**
    /// ARKit camera frames are in landscape-right (camera sensor orientation).
    /// When device is in portrait, we need to rotate coordinates:
    ///
    /// ```
    /// Landscape-Right Frame:        Portrait Screen:
    ///   (0,0)──────(1,0)              (0,0)──────(1,0)
    ///     │          │                  │          │
    ///     │   CAM    │                  │  VIEW   │
    ///     │          │                  │          │
    ///   (0,1)──────(1,1)              (0,1)──────(1,1)
    ///
    /// Transformation: adjustedX = y, adjustedY = 1.0 - x
    /// - Landscape top (y=0) → Portrait left (x=0)
    /// - Landscape bottom (y=1) → Portrait right (x=1)
    /// - Landscape left (x=0) → Portrait bottom (y=1)
    /// - Landscape right (x=1) → Portrait top (y=0)
    /// ```
    func toScreenCoordinates(
        viewSize: CGSize,
        transformForARKit: Bool = false,
        orientation: UIDeviceOrientation = .portrait
    ) -> CGPoint {
        var adjustedX = x
        var adjustedY = y
        
        // Only transform if using ARKit frames
        if transformForARKit {
            // ARKit frames are always in the camera sensor's native orientation (landscape-right)
            // We need to transform these coordinates to match the current device orientation
            
            switch orientation {
            case .portrait, .unknown, .faceUp, .faceDown:
                // ARKit landscape-right → Portrait display
                // Camera coordinate system rotated 90° counterclockwise relative to portrait
                // Transform: rotate coordinates 90° clockwise to match portrait
                adjustedX = 1.0 - y
                adjustedY = x
                
            case .portraitUpsideDown:
                // ARKit landscape-right → Portrait upside-down display
                // Rotate 90° counterclockwise from landscape-right
                adjustedX = y
                adjustedY = 1.0 - x
                
            case .landscapeLeft:
                // ARKit landscape-right → Landscape-left display
                // 180° rotation needed
                adjustedX = x
                adjustedY = y
                
            case .landscapeRight:
                // ARKit landscape-right → Landscape-right display
                // Actually needs 180° rotation because camera sensor is opposite direction
                adjustedX = 1.0 - x
                adjustedY = 1.0 - y
                
            @unknown default:
                // Default to portrait transformation
                adjustedX = 1.0 - y
                adjustedY = x
            }
        }
        // If not transformForARKit, coordinates are already correct (from CameraManager)
        
        let finalPoint = CGPoint(
            x: adjustedX * viewSize.width,
            y: adjustedY * viewSize.height
        )
        
        return finalPoint
    }
}
