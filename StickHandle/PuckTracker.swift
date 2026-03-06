//
//  PuckTracker.swift
//  StickHandle
//
//  Created by Tyson on 3/4/26.
//

/// Input: CVPixelBuffer (video frame from camera), target color (HSV range for bright green)
/// Transformation: Uses Vision framework to detect green color regions, finds largest contiguous green area (the puck), tracks center point and size
/// Output: PuckPosition struct with normalized coordinates (0-1 range for x, y) and confidence score, or nil if no puck detected

import Vision
import CoreImage
import UIKit
import Combine

/// Tracks a bright green puck in video frames using color-based detection
class PuckTracker: ObservableObject {
    
    // Published property so SwiftUI views can react to puck position changes
    // Like updating React state with setPuckPosition()
    @Published var puckPosition: PuckPosition?
    @Published var isTracking: Bool = false
    @Published var trackingConfidence: Float = 0.0
    @Published var debugImage: UIImage? // For showing color mask in debug mode
    
    // Color detection parameters for bright green
    // HSV (Hue, Saturation, Value) is better than RGB for color detection
    // Tuned for bright green/yellow-green puck
    // Wider ranges for better initial detection
    private let targetHue: (min: CGFloat, max: CGFloat) = (0.20, 0.50) // Wider green range
    private let targetSaturation: (min: CGFloat, max: CGFloat) = (0.3, 1.0) // Lower minimum
    private let targetBrightness: (min: CGFloat, max: CGFloat) = (0.3, 1.0) // Lower minimum
    
    // Debug mode to visualize color detection
    var debugMode: Bool = false
    
    private var lastDetectionTime = Date()
    private let detectionTimeout: TimeInterval = 0.5 // If no detection for 0.5s, mark as not tracking
    
    // Frame throttling for performance
    private var frameCount: Int = 0
    private let processEveryNthFrame = 1 // Process every frame now that we've optimized
    
    // Processing queue for background work
    private let processingQueue = DispatchQueue(label: "com.stickhandle.processing", qos: .userInitiated)
    
    // Core Image context for image processing (reuse for efficiency)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false, .priorityRequestLow: false])
    
    // Cache the color cube to avoid recreating it every frame
    private lazy var colorCubeData: Data = {
        return createGreenColorCube()
    }()
    
    /// Process a video frame to detect the green puck
    /// Call this for each frame from the camera
    func processFrame(_ pixelBuffer: CVPixelBuffer) {
        // Throttle frame processing for performance
        frameCount += 1
        if frameCount % processEveryNthFrame != 0 {
            return
        }
        
        // Log every 30th frame to confirm processing is happening
        if frameCount % 30 == 0 {
            print("📹 PuckTracker: Processing frame \(frameCount)")
        }
        
        // Process on background queue to avoid blocking main thread
        processingQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Convert pixel buffer to CIImage for processing
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
            
            // Detect green regions in the image
            if let position = self.detectGreenPuck(in: ciImage, pixelBuffer: pixelBuffer) {
                DispatchQueue.main.async {
                    self.puckPosition = position
                    self.isTracking = true
                    self.trackingConfidence = position.confidence
                    self.lastDetectionTime = Date()
                    
                    // Log first detection
                    if self.frameCount % 30 == 0 {
                        print("✅ Puck detected at (\(position.x), \(position.y)) confidence: \(position.confidence)")
                    }
                }
            } else {
                // Check if we've lost tracking
                let timeSinceLastDetection = Date().timeIntervalSince(self.lastDetectionTime)
                if timeSinceLastDetection > self.detectionTimeout {
                    DispatchQueue.main.async {
                        self.isTracking = false
                        self.trackingConfidence = 0.0
                    }
                }
            }
        }
    }
    
    /// Enable or disable debug visualization
    func setDebugMode(_ enabled: Bool) {
        debugMode = enabled
    }
    
    /// Detect the green puck in an image using color filtering
    private func detectGreenPuck(in image: CIImage, pixelBuffer: CVPixelBuffer) -> PuckPosition? {
        
        // Store original image size before scaling
        let originalWidth = image.extent.width
        let originalHeight = image.extent.height
        
        // Apply color threshold filter to isolate bright green
        guard let greenMask = createColorMask(for: image) else {
            return nil
        }
        
        // In debug mode, convert mask to UIImage for visualization
        if debugMode {
            if let cgImage = ciContext.createCGImage(greenMask, from: greenMask.extent) {
                DispatchQueue.main.async {
                    self.debugImage = UIImage(cgImage: cgImage)
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
    private func findLargestGreenBlob(in image: CGImage, originalSize: CGSize) -> PuckPosition? {
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
        
        // Aggressive downsampling for maximum speed
        // Check every 3rd pixel (9x faster than checking every pixel!)
        let sampleStep = 3
        
        // Find all white pixels (green regions in the mask)
        var sumX: CGFloat = 0
        var sumY: CGFloat = 0
        var pixelCount: Int = 0
        var minX: Int = width
        var maxX: Int = 0
        var minY: Int = height
        var maxY: Int = 0
        
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
                }
            }
        }
        
        // Need at least some pixels to consider it a detection
        // Very low threshold since we're downsampling aggressively (3x3 = 9x reduction)
        let minPixels = 10 // Very low threshold for initial detection
        guard pixelCount > minPixels else {
            return nil
        }
        
        // Calculate center of mass in scaled image space
        let centerX = sumX / CGFloat(pixelCount)
        let centerY = sumY / CGFloat(pixelCount)
        
        // Calculate bounding box size
        let bboxWidth = maxX - minX
        let bboxHeight = maxY - minY
        let radius = max(bboxWidth, bboxHeight) / 2
        
        // Normalize coordinates (0-1) relative to the SCALED image
        let normalizedX = centerX / CGFloat(width)
        let normalizedY = centerY / CGFloat(height)
        let normalizedRadius = CGFloat(radius) / CGFloat(min(width, height))
        
        // Calculate confidence based on:
        // 1. Number of pixels (more pixels = higher confidence)
        // 2. Aspect ratio (circular = higher confidence)
        // 3. Reasonable size
        let aspectRatio = CGFloat(bboxWidth) / CGFloat(bboxHeight)
        let isCircular = aspectRatio > 0.6 && aspectRatio < 1.4
        let isReasonableSize = normalizedRadius > 0.03 && normalizedRadius < 0.4
        
        // Adjust confidence calculation for downsampled pixels
        // Since we're sampling every 3rd pixel on 160px image, scale up the count
        let samplingFactor: Float = Float(sampleStep * sampleStep) // 9x undercount due to sampling
        let adjustedPixelCount = Float(pixelCount) * samplingFactor
        
        // Confidence based on adjusted pixel count and shape
        let pixelConfidence = min(adjustedPixelCount / 2000.0, 1.0) // More pixels = more confident
        let shapeConfidence: Float = isCircular && isReasonableSize ? 1.0 : 0.5
        let confidence = pixelConfidence * shapeConfidence
        
        return PuckPosition(
            x: normalizedX,
            y: normalizedY,
            radius: normalizedRadius,
            confidence: confidence
        )
    }
    
    /// Create a binary mask highlighting green regions
    private func createColorMask(for image: CIImage) -> CIImage? {
        
        // Reduce image size even MORE for maximum speed
        // Scale down to 160px wide - much faster, still accurate enough for tracking
        let scale = 160.0 / image.extent.width
        let scaledImage = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        
        // Use cached color cube data instead of recreating every frame
        let cubeSize = 64
        
        let colorCube = CIFilter(name: "CIColorCube")
        colorCube?.setValue(cubeSize, forKey: "inputCubeDimension")
        colorCube?.setValue(colorCubeData, forKey: "inputCubeData")
        colorCube?.setValue(scaledImage, forKey: kCIInputImageKey)
        
        return colorCube?.outputImage
    }
    
    /// Create a color lookup table that passes through green and blacks out other colors
    private func createGreenColorCube() -> Data {
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
                    let hsv = rgbToHsv(r: r, g: g, b: b)
                    
                    // Check if this color is in our green range
                    let isGreen = hsv.h >= targetHue.min && hsv.h <= targetHue.max &&
                                  hsv.s >= targetSaturation.min &&
                                  hsv.v >= targetBrightness.min
                    
                    if isGreen {
                        // Keep the color (white in mask)
                        cubeData[offset] = 1.0 // R
                        cubeData[offset + 1] = 1.0 // G
                        cubeData[offset + 2] = 1.0 // B
                        cubeData[offset + 3] = 1.0 // A
                    } else {
                        // Make it black (not green)
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
    
    /// Convert RGB to HSV color space
    private func rgbToHsv(r: CGFloat, g: CGFloat, b: CGFloat) -> (h: CGFloat, s: CGFloat, v: CGFloat) {
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

// MARK: - Data Models

/// Represents the detected position of the puck
/// Coordinates are normalized (0-1) relative to the image
struct PuckPosition {
    let x: CGFloat // Horizontal position (0 = left, 1 = right)
    let y: CGFloat // Vertical position (0 = top, 1 = bottom)
    let radius: CGFloat // Radius of detected puck (normalized)
    let confidence: Float // Confidence score 0-1
    
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
            // Transform coordinates based on device orientation
            if orientation == .portrait || orientation == .unknown {
                // ARKit landscape-right → Portrait display
                // Based on observed behavior:
                // - Puck up (y↓) → Circle left (x↓)
                // - Puck down (y↑) → Circle right (x↑)
                // - Puck right (x↑) → Circle up (y↓)
                // - Puck left (x↓) → Circle down (y↑)
                // This is: adjustedX = 1-y, adjustedY = x
                adjustedX = 1.0 - y
                adjustedY = x
            } else if orientation == .portraitUpsideDown {
                // Rotate 180° from portrait
                adjustedX = y
                adjustedY = 1.0 - x
            } else if orientation == .landscapeLeft {
                // Rotate 180° from landscape-right
                adjustedX = 1.0 - x
                adjustedY = 1.0 - y
            }
            // If landscapeRight, no transformation needed (matches ARKit camera sensor)
        }
        // If not transformForARKit, coordinates are already correct (from CameraManager)
        
        return CGPoint(
            x: adjustedX * viewSize.width,
            y: adjustedY * viewSize.height
        )
    }
}
