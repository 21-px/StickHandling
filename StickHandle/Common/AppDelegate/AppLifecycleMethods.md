# App Lifecycle Methods

## Overview

These are the core `UIApplicationDelegate` lifecycle methods that respond to app state transitions. They're currently implemented as empty placeholders in `AppDelegate.swift`, but provide critical hooks for managing resources and state as the app moves between foreground, background, and inactive states.

## The Four Key Lifecycle Methods

### 1. `applicationWillResignActive(_:)`

**When Called:**
- User receives incoming phone call or FaceTime
- SMS/iMessage notification appears
- Control Center is pulled down
- Notification Center is pulled down
- User double-taps home button (app switcher)
- User swipes to another app
- System alerts or overlays appear

**State Transition:**
```
Active → Inactive
```

**Duration:**
Temporary state - app is visible but not receiving touch events

**Current Implementation:**
```swift
func applicationWillResignActive(_ application: UIApplication) {
    // Sent when the application is about to move from active to inactive state. 
    // This can occur for certain types of temporary interruptions (such as an 
    // incoming phone call or SMS message) or when the user quits the application 
    // and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and invalidate 
    // graphics rendering callbacks. Games should use this method to pause the game.
}
```

**Recommended Implementation for Puck Tracking App:**
```swift
func applicationWillResignActive(_ application: UIApplication) {
    // Stop camera capture to save battery and prevent background access issues
    NotificationCenter.default.post(
        name: Notification.Name("StopCameraSession"),
        object: nil
    )
    
    // Pause any ongoing tracking
    NotificationCenter.default.post(
        name: Notification.Name("PauseTracking"),
        object: nil
    )
    
    // If AR session is active, pause it
    NotificationCenter.default.post(
        name: Notification.Name("PauseARSession"),
        object: nil
    )
    
    // Save current tracking state (if needed)
    // UserDefaults.standard.set(currentState, forKey: "lastTrackingState")
}
```

**Why This Matters:**
- Camera sessions must be stopped when app is inactive (iOS restriction)
- Prevents battery drain from running computer vision in background
- Avoids camera access violations
- Provides smooth pause behavior for user interruptions

---

### 2. `applicationDidEnterBackground(_:)`

**When Called:**
- User presses home button
- User swipes up to home screen (iPhone without home button)
- User switches to another app completely
- App is no longer visible on screen

**State Transition:**
```
Inactive → Background
```

**Duration:**
App has limited execution time (typically 5-30 seconds) before being suspended

**Current Implementation:**
```swift
func applicationDidEnterBackground(_ application: UIApplication) {
    // Use this method to release shared resources, save user data, invalidate 
    // timers, and store enough application state information to restore your 
    // application to its current state in case it is terminated later.
}
```

**Recommended Implementation for Puck Tracking App:**
```swift
func applicationDidEnterBackground(_ application: UIApplication) {
    // Ensure camera is completely stopped
    NotificationCenter.default.post(
        name: Notification.Name("StopCameraSession"),
        object: nil
    )
    
    // Release AR resources (RealityKit scenes, anchors)
    NotificationCenter.default.post(
        name: Notification.Name("CleanupARResources"),
        object: nil
    )
    
    // Save user preferences (color calibration, settings)
    UserDefaults.standard.synchronize()
    
    // Save current drill progress (if applicable)
    // DrillManager.shared.saveCurrentProgress()
    
    // Release memory-intensive resources
    // ImageCache.shared.clearCache()
    
    // Invalidate any timers
    // trackingTimer?.invalidate()
    
    print("📱 App entered background - resources released")
}
```

**Why This Matters:**
- Camera MUST be stopped (iOS will terminate app if camera runs in background)
- Unsaved data could be lost if app is terminated by system
- Background apps are suspended after ~30 seconds
- System may terminate background apps at any time if memory is needed
- Releasing resources makes app a better "citizen" and less likely to be killed

**Background Execution Time:**
```
0-5s:   Critical tasks (saving data)
5-30s:  Extended tasks (finishing network requests)
30s+:   App suspended (no code execution)
```

---

### 3. `applicationWillEnterForeground(_:)`

**When Called:**
- User returns to app from background
- User taps app icon while app is still in background
- User switches back from another app

**State Transition:**
```
Background → Inactive
```

**Duration:**
Brief moment before app becomes fully active

**Current Implementation:**
```swift
func applicationWillEnterForeground(_ application: UIApplication) {
    // Called as part of the transition from the background to the active state; 
    // here you can undo many of the changes made on entering the background.
}
```

**Recommended Implementation for Puck Tracking App:**
```swift
func applicationWillEnterForeground(_ application: UIApplication) {
    // Prepare to resume camera (actual start happens in didBecomeActive)
    NotificationCenter.default.post(
        name: Notification.Name("PrepareCamera"),
        object: nil
    )
    
    // Reload any expired data
    // DataManager.shared.refreshIfNeeded()
    
    // Prepare AR session for resuming
    NotificationCenter.default.post(
        name: Notification.Name("PrepareARSession"),
        object: nil
    )
    
    // Check if color calibration settings are still valid
    // PuckTracker.shared.validateColorSettings()
    
    print("📱 App entering foreground - preparing to resume")
}
```

**Why This Matters:**
- Good place to prepare resources before app is visible
- User doesn't see initialization work happening
- Can check if data needs refreshing after being in background
- Opportunity to validate state before resuming

---

### 4. `applicationDidBecomeActive(_:)`

**When Called:**
- App finishes launching
- App returns to foreground and becomes fully interactive
- After any temporary interruption ends (phone call ends, notification dismissed)
- User dismisses Control Center/Notification Center

**State Transition:**
```
Inactive → Active
```

**Duration:**
App is now fully interactive and receiving events

**Current Implementation:**
```swift
func applicationDidBecomeActive(_ application: UIApplication) {
    // Restart any tasks that were paused (or not yet started) while the 
    // application was inactive. If the application was previously in the 
    // background, optionally refresh the user interface.
}
```

**Recommended Implementation for Puck Tracking App:**
```swift
func applicationDidBecomeActive(_ application: UIApplication) {
    // Resume camera session (if user is on tracking screen)
    NotificationCenter.default.post(
        name: Notification.Name("ResumeCameraIfNeeded"),
        object: nil
    )
    
    // Resume AR session (if user is in AR view)
    NotificationCenter.default.post(
        name: Notification.Name("ResumeARSession"),
        object: nil
    )
    
    // Resume puck tracking
    NotificationCenter.default.post(
        name: Notification.Name("ResumeTracking"),
        object: nil
    )
    
    // Refresh UI if needed
    // RefreshUIIfNeeded()
    
    // Re-validate camera permissions (user might have changed in Settings)
    // CameraManager.shared.checkPermissions()
    
    print("📱 App became active - resuming operations")
}
```

**Why This Matters:**
- Camera can safely restart here (app is fully in foreground)
- Computer vision processing can resume
- AR session can resume tracking
- User is now actively using the app and expects full functionality

---

## Complete Lifecycle Flow

### Cold Start (App Not Running)
```
Not Running
    ↓ (User taps app icon)
application(_:didFinishLaunchingWithOptions:)
    ↓
Inactive
    ↓
applicationDidBecomeActive(_:)
    ↓
Active ✓ (Fully interactive)
```

### Going to Background
```
Active
    ↓ (Home button / swipe up)
applicationWillResignActive(_:)
    ↓
Inactive
    ↓
applicationDidEnterBackground(_:)
    ↓
Background
    ↓ (After ~30 seconds)
Suspended (frozen in memory)
    ↓ (If system needs memory)
Terminated
```

### Returning from Background
```
Background/Suspended
    ↓ (User returns to app)
applicationWillEnterForeground(_:)
    ↓
Inactive
    ↓
applicationDidBecomeActive(_:)
    ↓
Active ✓
```

### Temporary Interruption
```
Active
    ↓ (Phone call, notification)
applicationWillResignActive(_:)
    ↓
Inactive (app visible but not interactive)
    ↓ (User dismisses interruption)
applicationDidBecomeActive(_:)
    ↓
Active ✓
```

---

## Resource Management Strategy

### Camera Session
| State | Camera Status | Reason |
|-------|--------------|--------|
| **Active** | Running | User is actively tracking puck |
| **Inactive** | Paused | Temporary interruption, may resume |
| **Background** | Stopped | iOS requirement, saves battery |
| **Suspended** | Stopped | No code execution |

### AR Session (RealityKit)
| State | AR Status | Reason |
|-------|-----------|--------|
| **Active** | Running | Full AR experience |
| **Inactive** | Paused | Preserve state for quick resume |
| **Background** | Paused | Can't run in background |
| **Suspended** | Released | Free memory |

### Puck Tracker
| State | Tracking Status | Reason |
|-------|----------------|--------|
| **Active** | Processing Frames | Real-time detection |
| **Inactive** | Paused | No new frames to process |
| **Background** | Stopped | No camera frames available |
| **Suspended** | Stopped | No code execution |

### Memory-Intensive Resources
| State | Status | Action |
|-------|--------|--------|
| **Active** | Loaded | Full functionality |
| **Inactive** | Loaded | Keep for quick resume |
| **Background** | Released | Free memory for system |
| **Suspended** | Released | Minimize memory footprint |

---

## Implementation Pattern with NotificationCenter

### Why NotificationCenter?

The app delegate shouldn't directly reference view controllers or managers. Instead, use `NotificationCenter` to broadcast lifecycle events that interested components can observe.

**Benefits:**
- ✅ Loose coupling (app delegate doesn't know about CameraManager)
- ✅ Multiple observers (both AR and tracking views can respond)
- ✅ Easy to add new observers without modifying app delegate
- ✅ Standard iOS pattern

### Observer Pattern Example

**In CameraManager.swift:**
```swift
class CameraManager: ObservableObject {
    
    init() {
        // Listen for lifecycle events
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(stopSession),
            name: Notification.Name("StopCameraSession"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(startSession),
            name: Notification.Name("ResumeCameraIfNeeded"),
            object: nil
        )
    }
    
    @objc func startSession() {
        // Only start if we should be running
        guard shouldBeRunning else { return }
        sessionQueue.async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    @objc func stopSession() {
        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
```

**In PuckTracker.swift:**
```swift
class PuckTracker: ObservableObject {
    
    init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pause),
            name: Notification.Name("PauseTracking"),
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(resume),
            name: Notification.Name("ResumeTracking"),
            object: nil
        )
    }
    
    @objc func pause() {
        isTracking = false
        smoothedPosition = nil  // Reset smoothing
    }
    
    @objc func resume() {
        isTracking = true
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
```

---

## State Preservation and Restoration

### What to Save

**In `applicationDidEnterBackground(_:)`:**
```swift
// User preferences (already handled by PuckTracker via UserDefaults)
// - Color calibration (HSV ranges)
// - LiDAR enabled/disabled
// - Debug mode preferences

// Current view state
UserDefaults.standard.set(currentViewIdentifier, forKey: "lastActiveView")

// Drill progress (if applicable)
// DrillSession.current?.save()

// Ensure all writes complete
UserDefaults.standard.synchronize()
```

### What to Restore

**In `applicationWillEnterForeground(_:)`:**
```swift
// Validate saved state is still valid
let lastView = UserDefaults.standard.string(forKey: "lastActiveView")

// Check if color calibration needs refresh
PuckTracker.shared.validateColorSettings()

// Restore drill progress
// DrillSession.restoreLastSession()
```

---

## Testing Lifecycle Transitions

### Simulator Testing

**Simulate background:**
```
⌘ + Shift + H  (Home button)
```

**Simulate phone call:**
```
Hardware → Simulate Phone Call
```

**Simulate low memory:**
```
Hardware → Simulate Memory Warning
```

### Device Testing

**Real background transitions:**
1. Start app with puck tracking active
2. Press home button → verify camera stops
3. Return to app → verify camera resumes
4. Make actual phone call → verify camera pauses
5. End call → verify camera resumes

**Memory pressure:**
1. Open many apps to fill memory
2. Return to puck tracking app
3. Verify it restores correctly (not terminated)

---

## Common Pitfalls

### ❌ Don't: Access Camera in Background
```swift
func applicationDidEnterBackground(_ application: UIApplication) {
    // ❌ WRONG - iOS will terminate your app
    cameraManager.startSession()
}
```

### ✅ Do: Stop Camera in Background
```swift
func applicationDidEnterBackground(_ application: UIApplication) {
    // ✅ CORRECT
    NotificationCenter.default.post(
        name: Notification.Name("StopCameraSession"),
        object: nil
    )
}
```

### ❌ Don't: Assume App Will Resume
```swift
func applicationDidEnterBackground(_ application: UIApplication) {
    // ❌ WRONG - app might be terminated
    // Don't just cache in memory
    temporaryCache = importantData
}
```

### ✅ Do: Persist Important Data
```swift
func applicationDidEnterBackground(_ application: UIApplication) {
    // ✅ CORRECT - save to disk
    UserDefaults.standard.set(importantData, forKey: "savedData")
}
```

### ❌ Don't: Do Heavy Work on Main Thread
```swift
func applicationWillResignActive(_ application: UIApplication) {
    // ❌ WRONG - blocks UI thread
    processLargeDataset()
}
```

### ✅ Do: Use Background Queues
```swift
func applicationWillResignActive(_ application: UIApplication) {
    // ✅ CORRECT - background queue
    DispatchQueue.global(qos: .utility).async {
        processLargeDataset()
    }
}
```

---

## Performance Considerations

### Response Time Targets

| Method | Target Time | Consequence of Slow |
|--------|------------|-------------------|
| `willResignActive` | < 100ms | Janky interruption animation |
| `didEnterBackground` | < 5s | Forced termination by iOS |
| `willEnterForeground` | < 100ms | Delayed app launch feeling |
| `didBecomeActive` | < 200ms | Poor user experience |

### What's Fast Enough

**✅ Fast (< 1ms):**
- Post notifications
- Set boolean flags
- Increment counters

**✅ Acceptable (< 100ms):**
- Stop camera session
- Pause AR session
- Save UserDefaults (small data)

**⚠️ Risky (100ms - 5s):**
- Save large files
- Network requests
- Image processing

**❌ Too Slow (> 5s):**
- Video encoding
- Large database operations
- Complex computations

---

## Debugging Lifecycle

### Add Logging

```swift
func applicationWillResignActive(_ application: UIApplication) {
    print("📱 [LIFECYCLE] Will Resign Active - \(Date())")
    
    NotificationCenter.default.post(
        name: Notification.Name("StopCameraSession"),
        object: nil
    )
    
    print("📱 [LIFECYCLE] Camera stop notification sent")
}

func applicationDidEnterBackground(_ application: UIApplication) {
    print("📱 [LIFECYCLE] Did Enter Background - \(Date())")
    
    NotificationCenter.default.post(
        name: Notification.Name("CleanupARResources"),
        object: nil
    )
    
    UserDefaults.standard.synchronize()
    print("📱 [LIFECYCLE] UserDefaults synchronized")
    
    print("📱 [LIFECYCLE] Background transition complete")
}

func applicationWillEnterForeground(_ application: UIApplication) {
    print("📱 [LIFECYCLE] Will Enter Foreground - \(Date())")
}

func applicationDidBecomeActive(_ application: UIApplication) {
    print("📱 [LIFECYCLE] Did Become Active - \(Date())")
    
    NotificationCenter.default.post(
        name: Notification.Name("ResumeCameraIfNeeded"),
        object: nil
    )
    
    print("📱 [LIFECYCLE] Camera resume notification sent")
}
```

### Monitor Lifecycle in Console

```
📱 [LIFECYCLE] Will Resign Active - 2026-03-14 10:23:45
📱 [LIFECYCLE] Camera stop notification sent
📱 [LIFECYCLE] Did Enter Background - 2026-03-14 10:23:45
📱 [LIFECYCLE] UserDefaults synchronized
📱 [LIFECYCLE] Background transition complete

(30 seconds pass)

📱 [LIFECYCLE] Will Enter Foreground - 2026-03-14 10:24:15
📱 [LIFECYCLE] Did Become Active - 2026-03-14 10:24:15
📱 [LIFECYCLE] Camera resume notification sent
```

---

## Summary

### Key Takeaways

1. **Stop camera in background** - iOS requirement, not optional
2. **Save important data** - App can be terminated at any time in background
3. **Use NotificationCenter** - Decouple app delegate from managers
4. **Keep it fast** - Lifecycle methods should complete in < 100ms typically
5. **Test thoroughly** - Real device testing is essential

### Current Status

✅ **Implemented:**
- Empty placeholder methods
- App launches correctly
- Basic lifecycle works

❌ **Not Implemented:**
- Camera pause/resume on background
- AR session management
- State preservation
- Resource cleanup

### Next Steps

1. Add `NotificationCenter` observers to `CameraManager`
2. Add `NotificationCenter` observers to `PuckTracker`
3. Implement camera pause in `applicationWillResignActive`
4. Implement camera stop in `applicationDidEnterBackground`
5. Implement camera resume in `applicationDidBecomeActive`
6. Add logging for debugging lifecycle transitions
7. Test on real device with interruptions

---

## Related Files

- `AppDelegate.swift` - Contains these lifecycle methods
- `CameraManager.swift` - Should observe lifecycle notifications
- `PuckTracker.swift` - Should pause/resume tracking
- `PuckTrackingView.swift` - Uses `.onAppear`/`.onDisappear` for view-level lifecycle
- `ARCourseView.swift` - Should manage AR session lifecycle

---

## References

- [Apple Documentation: Managing Your App's Life Cycle](https://developer.apple.com/documentation/uikit/app_and_environment/managing_your_app_s_life_cycle)
- [Apple Documentation: UIApplicationDelegate](https://developer.apple.com/documentation/uikit/uiapplicationdelegate)
- [Apple Documentation: App States and Transitions](https://developer.apple.com/library/archive/documentation/iPhone/Conceptual/iPhoneOSProgrammingGuide/BackgroundExecution/BackgroundExecution.html)
