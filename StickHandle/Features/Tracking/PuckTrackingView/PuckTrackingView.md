# PuckTrackingView.swift

## Purpose
A full-screen debug and calibration view that displays the live camera feed with visual puck tracking feedback. Allows users to calibrate the color detection by selecting the puck color directly from the video feed.

## What It Does

### Input
- Live camera feed from `CameraManager`
- User interactions (taps for color selection, button toggles)

### Transformation
1. **Camera Feed Display**: Shows full-screen video from back camera
2. **Real-time Detection**: Processes each frame through `PuckTracker` for color-based detection
3. **Visual Overlay**: Draws tracking indicator (red circle) at detected puck position
4. **Color Calibration**: Allows users to tap on the puck to set/update tracking color
5. **Debug Visualization**: Shows color mask overlay when enabled
6. **Status Display**: Shows tracking confidence and detection state

### Output
- Full-screen camera preview (edge-to-edge)
- Real-time puck position overlay
- Color calibration interface
- Debug information and controls

## Key Components

### Main View Structure
```swift
ZStack {
    CameraPreview          // Full-screen camera feed
    DebugMask (optional)   // Color detection mask overlay
    PuckOverlay            // Red circle at puck position
    StatusOverlay          // Top: back button, tracking status, color picker
    ControlOverlay         // Bottom: LiDAR toggle, debug mask toggle
}
```

### CameraPreview (UIViewRepresentable)
- Wraps AVFoundation's `AVCaptureVideoPreviewLayer`
- Uses `.resizeAspectFill` for edge-to-edge display
- Locked to portrait orientation (mimics ARKit behavior)
- Updates size dynamically for debug mask alignment

### Color Picker Mode
- **Activation**: Tap "Pick" button to enter mode
- **Usage**: Tap on the puck in the video feed
- **Processing**: 
  - Converts screen coordinates to normalized camera coordinates
  - Samples HSV color at that point
  - Updates `PuckTracker` with new color range
  - Persists to UserDefaults
- **Feedback**: Shows selected color preview and confirmation message

### TrackingStatusView
- Displays tracking state (active/inactive)
- Shows confidence percentage when tracking
- Color-coded indicator (green = tracking, red = lost)

### ColorRangeIndicator
- Visual representation of HSV color range being tracked
- Shows 5-color gradient from min to max hue
- Displays current saturation and brightness midpoints

## Features

### Interactive Calibration
1. **Color Selection**: Tap on puck to set tracking color
2. **Visual Feedback**: See preview of selected color
3. **Persistent Storage**: Color settings saved to UserDefaults
4. **Live Update**: Tracking updates immediately with new color

### Debug Tools
- **Mask Visualization**: Toggle to see what the computer vision "sees"
- **LiDAR Toggle**: Enable/disable distance estimation via LiDAR
- **Position Display**: Shows normalized and screen coordinates
- **Tap Indicator**: Yellow circle shows where user tapped for debugging

### Orientation Locking
```swift
.onAppear {
    AppDelegate.orientationLock = .portrait
}
.onDisappear {
    AppDelegate.orientationLock = .all
}
```
Prevents camera rotation to maintain consistent tracking (like ARKit)

## Technical Details

### Coordinate Transformation
The view handles complex coordinate mapping:
1. **Screen Space**: SwiftUI touch coordinates
2. **Layer Space**: AVCaptureVideoPreviewLayer coordinates
3. **Camera Space**: Device camera sensor coordinates (landscape-right)
4. **Normalized Space**: 0-1 range for position-independent tracking

Transformation accounts for:
- `.resizeAspectFill` cropping
- Aspect ratio differences
- Portrait vs. landscape orientation
- SwiftUI coordinate system offsets

### Performance Optimizations
- Frame processing on background queue
- Debounced frame rate (processes every Nth frame)
- Reused Core Image context
- Efficient pixel buffer handling

### HSV to RGB Conversion
```swift
func hsvToRgb(h: CGFloat, s: CGFloat, v: CGFloat) -> (r: Double, g: Double, b: Double)
```
Converts HSV color back to RGB for preview display in SwiftUI.

## State Management

### Published Properties
- `showDebugMask`: Toggles color mask overlay
- `colorPickerMode`: Enables tap-to-select color
- `selectedColorPreview`: Preview of picked color
- `showColorConfirmation`: Success message animation
- `lastTapLocation`: Position for tap indicator
- `showTapIndicator`: Visibility of tap debug circle

### Observable Objects
- `CameraManager`: Manages AVCaptureSession and frame delivery
- `PuckTracker`: Processes frames and detects puck position

## User Workflow

### Normal Usage
1. View opens with live camera feed
2. Red circle automatically tracks detected puck
3. Status shows tracking confidence
4. Back button returns to AR course view

### Calibration Workflow
1. Tap "Pick" button to enter color picker mode
2. Tap directly on the puck in the video
3. See color preview and confirmation
4. Tracking updates immediately with new color
5. Settings persist across app launches

### Debug Workflow
1. Toggle "Show Mask" to see color detection visualization
2. Toggle "LiDAR On/Off" to test distance estimation
3. Observe coordinate readouts for position verification
4. Yellow circle shows tap locations for debugging

## Related Files
- `CameraManager.swift`: Camera session and frame capture
- `PuckTracker.swift`: Computer vision detection logic
- `PuckOverlay.swift`: Shared tracking visualization component
- `AppDelegate.swift`: Provides orientation lock mechanism

## Platform Requirements
- iOS 13.0+ (AVFoundation camera support)
- Camera permission required
- LiDAR features require iPhone 12 Pro or later

## Notes
- This view is primarily for debugging and setup
- Production use is via `ARCourseView` with integrated tracking
- Color calibration is persistent, so users only need to calibrate once
- Locked to portrait orientation for consistent tracking coordinates
