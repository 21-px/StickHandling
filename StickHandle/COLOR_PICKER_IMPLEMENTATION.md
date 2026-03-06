# Color Picker Implementation

## Overview
Added the ability for users to tap on the puck in the camera feed to select its color for tracking, with the selection saved permanently to UserDefaults.

## Changes Made

### 1. PuckTracker.swift

#### Color Storage & Persistence
- **Changed** hardcoded color ranges to `@Published` properties that can be updated
- **Added** UserDefaults keys for persisting HSV color ranges:
  - `hueMinKey`, `hueMaxKey`
  - `satMinKey`, `satMaxKey`
  - `brightMinKey`, `brightMaxKey`
- **Added** `init()` method to load saved colors from UserDefaults (or use defaults)
- **Added** `currentFrame: CVPixelBuffer?` to store the latest frame for color sampling

#### Color Picking Functionality
- **Added** `getColorAt(normalizedPoint:)` - Extracts HSV color from a tapped point
  - Samples a 3x3 pixel region around the point and averages the color
  - Returns HSV tuple or nil if no frame available
- **Added** `getPixelColor(ciImage:x:y:width:height:)` - Helper to extract RGB from a pixel
- **Added** `updateTargetColor(hsv:)` - Updates tracking color and saves to UserDefaults
  - Creates reasonable ranges around the selected color (±0.08 for hue, ±0.2 for sat/bright)
  - Regenerates the color cube filter with new ranges
  - Persists settings immediately

#### Color Cube Updates
- **Changed** `createGreenColorCube()` to `static createColorCube(hue:saturation:brightness:)`
  - Now accepts custom color ranges as parameters
  - Can be called to regenerate the cube when color changes
- **Added** `rgbToHsvStatic()` - Static version of RGB→HSV conversion for use in static methods

#### Helper Extension
- **Added** `CGFloat.ifZero(_:)` extension - Returns default value if CGFloat is 0 (for UserDefaults)

### 2. PuckTrackingView.swift

#### New State Properties
- **Added** `@State private var colorPickerMode = false` - Toggles color picker mode
- **Added** `@State private var selectedColorPreview: Color?` - Shows selected color preview
- **Added** `@State private var showColorConfirmation = false` - Shows confirmation message

#### UI Updates
- **Added** tap gesture to camera preview that triggers color picking when in picker mode
- **Added** "Pick Color" button (eyedropper icon) that toggles picker mode
  - Changes to green checkmark when active
  - Shows "Tap on puck to set color" instruction when active
- **Added** color preview square that appears after tapping
  - Shows the selected color visually
  - Includes white border for visibility
- **Added** confirmation message "✓ Color Updated!" that appears briefly after selection
- **Modified** top bar to show different UI based on mode:
  - Normal mode: Shows tracking status
  - Picker mode: Shows "Tap on puck" instruction

#### Color Picking Flow
- **Added** `handleColorPick(at:viewSize:)` method:
  1. Converts screen tap to normalized coordinates
  2. Calls `puckTracker.getColorAt()` to extract color
  3. Updates tracker with new color
  4. Shows color preview
  5. Shows confirmation message for 1.5 seconds
  6. Automatically exits picker mode
- **Added** `hsvToRgb(h:s:v:)` - Converts HSV to RGB for color preview display

## User Experience Flow

1. User opens the Debug page (PuckTrackingView)
2. User taps the "Pick" button (eyedropper icon) to enter color picker mode
3. Top center shows instruction: "Tap on puck to set color"
4. User taps anywhere on the puck in the camera feed
5. **Yellow circle appears** briefly at tap location for visual confirmation
6. System extracts the color from that pixel (averaging a 3x3 region)
7. Color preview appears showing the selected color
8. Confirmation message "✓ Color Updated!" appears
9. After 1.5 seconds, picker mode exits automatically
10. Color is saved to UserDefaults and will persist across app launches
11. Puck tracking immediately uses the new color

## Bug Fixes (Latest Update)

### Issue 1: Can't Tap Inside Tracking Circle ✅ FIXED
**Problem**: The `PuckOverlay` (red tracking circle) was blocking touch events, preventing users from tapping on the puck itself to select its color.

**Solution**: Added `.allowsHitTesting(false)` to the `PuckOverlay` view so it displays the tracking visualization but doesn't intercept taps.

```swift
PuckOverlay(position: puckPosition, viewSize: geometry.size)
    .allowsHitTesting(false) // Don't block taps for color picking
```

### Issue 2: Wrong Color Being Selected ✅ FIXED
**Problem**: When tapping on a location, the system was sampling a 7x7 pixel region (49 pixels) and averaging them, resulting in a blend of multiple colors rather than the specific color tapped.

**Root Cause**: The `sampleSize` was set to `3`, which means it sampled from -3 to +3 pixels in each direction, creating a 7x7 grid. This was too aggressive for color picking.

**Solution**: Changed to sample a **3x3 pixel region** (9 pixels) by setting `sampleSize = 1`. This provides:
- ✅ **Accurate color selection** - Much closer to the actual tapped color
- ✅ **Noise reduction** - Still averages 9 pixels to reduce camera sensor noise
- ✅ **Fast sampling** - 81% fewer pixels to process (9 vs 49)

```swift
let sampleSize = 1  // -1 to +1 = 3x3 grid (9 pixels)
// Was: sampleSize = 3  // -3 to +3 = 7x7 grid (49 pixels)
```

**Alternative Option**: If you want the **exact pixel** with zero averaging, you can set `sampleSize = 0` to sample only the center pixel. However, the 3x3 grid is recommended for better results with real-world camera noise.

### Debug Features (Active)
The following debug features remain active to help troubleshoot any remaining issues:

1. **🟡 Yellow Tap Indicator** - Visual confirmation of where you tapped
2. **📋 Console Logging** - Detailed information about:
   - Screen coordinates and view size
   - Normalized coordinates (0-1)
   - Frame dimensions from camera
   - Pixel coordinates being sampled
   - Number of pixels in sample grid
   - RGB values extracted
   - HSV values calculated

**Sample Console Output**:
```
🎨 Tap at screen: (200, 400) in view size: (375, 667)
🎨 Normalized tap: (0.533, 0.599)
📐 Frame dimensions: 720x1280
📍 Normalized point: (0.533, 0.599)
📍 Pixel coordinates: (384, 768)
📊 Sampled 9 pixels in 3x3 grid
🎨 Sampled RGB: R:0.45 G:0.78 B:0.32
🎨 Extracted HSV: H:0.33 S:0.65 V:0.78
🎨 Updated puck color to H:0.33 S:0.65 V:0.78
```

These debug features can be removed later for production, but are helpful for verifying correct operation.

## Technical Details

### Color Range Calculation
When a user selects a color, we create ranges around it:
- **Hue**: ±0.08 (about ±29 degrees on the color wheel)
- **Saturation**: ±0.2
- **Brightness**: ±0.2

This provides enough tolerance to track the puck under varying lighting conditions while remaining specific enough to avoid false positives.

### Performance
- Color extraction uses Core Image's efficient bitmap rendering
- Only the current frame needs to be sampled (no video buffering)
- Color cube is regenerated once when color changes (not per frame)
- Sampling uses a 3x3 pixel region to average out noise

### Persistence
Colors are stored in UserDefaults with the app bundle ID prefix:
```
com.stickhandle.puck.hue.min
com.stickhandle.puck.hue.max
com.stickhandle.puck.sat.min
com.stickhandle.puck.sat.max
com.stickhandle.puck.bright.min
com.stickhandle.puck.bright.max
```

Default values (bright green) are used if no saved values exist.

## Update: Color Range Visual Indicator (Added)

### New Component: ColorRangeIndicator
Added a visual gradient display showing the current HSV color range being tracked.

#### Features
- **5-segment gradient bar**: Shows the hue range from min to max
- **Live updates**: Automatically reflects current tracking color
- **Compact design**: Small bar above the "Pick" button
- **Clear labeling**: "Tracking" label for clarity

#### Implementation Details
```swift
struct ColorRangeIndicator: View {
    let hueRange: (min: CGFloat, max: CGFloat)
    let satRange: (min: CGFloat, max: CGFloat)
    let brightRange: (min: CGFloat, max: CGFloat)
    
    // Creates 5 color samples across the hue range
    // Uses mid-point of saturation and brightness ranges
}
```

#### Visual Layout
```
┌─────────────────────┐
│  Back  │ Status │ ▼ │  ← Top bar
└─────────────────────┘
                    ┌────────────┐
                    │ "Tracking" │
                    ├────────────┤
                    │ █ █ █ █ █  │  ← Color gradient (5 segments)
                    └────────────┘
                    ┌────────────┐
                    │ 💧 "Pick"  │  ← Eyedropper button
                    └────────────┘
```

#### User Benefits
1. **Visual feedback**: See exactly what color is being tracked
2. **Quick verification**: Confirm color selection without testing
3. **Troubleshooting**: Understand why detection isn't working
4. **Color reference**: Know what to look for in the camera view

## Future Enhancements

Possible improvements:
- Add "Reset to Default" button to restore original green color
- Show HSV values in debug info (numerical display)
- Allow manual fine-tuning of color ranges with sliders
- Save multiple color presets
- Add color history to quickly switch between previously used colors
- Show a "heat map" overlay of what's currently being detected
- Expand gradient to show saturation/brightness variations
- Add a "test mode" to temporarily adjust ranges without saving
