# AppDelegate.swift

## Purpose
The application delegate that serves as the entry point for the UIKit app lifecycle. Manages orientation locking and sets up the initial SwiftUI view hierarchy.

## What It Does

### Input
- App lifecycle events from iOS
- Orientation lock requests from views

### Transformation
1. **App Initialization**: Sets up the root SwiftUI view on launch
2. **Window Management**: Creates and manages the main UIWindow
3. **Orientation Control**: Provides global orientation locking mechanism
4. **Lifecycle Handling**: Responds to app state transitions (active, background, etc.)

### Output
- Main app window with SwiftUI view hierarchy
- Controlled interface orientation based on view requirements

## Key Components

### Main Entry Point
```swift
@main
class AppDelegate: UIResponder, UIApplicationDelegate
```

**@main attribute:**
- Marks this as the app's entry point
- Equivalent to having a `main.swift` with `UIApplicationMain()`
- iOS calls this on app launch

### Orientation Lock
```swift
static var orientationLock = UIInterfaceOrientationMask.all
```

**Purpose:**
Allows individual views to control which orientations are allowed.

**Default:** `.all` - All orientations permitted

**How it works:**
```swift
func application(
    _ application: UIApplication,
    supportedInterfaceOrientationsFor window: UIWindow?
) -> UIInterfaceOrientationMask {
    return AppDelegate.orientationLock
}
```

iOS queries this method to determine allowed orientations. By changing the static property, views can control rotation behavior.

## Lifecycle Methods

### App Launch
```swift
func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
) -> Bool
```

**Actions:**
1. Creates SwiftUI `ContentView`
2. Wraps in `UIHostingController`
3. Creates `UIWindow` for main screen
4. Sets hosting controller as root
5. Makes window visible

**Flow:**
```
Launch → Create ContentView → Wrap in UIHostingController
      → Create UIWindow → Set root → Display
```

### Resign Active
```swift
func applicationWillResignActive(_ application: UIApplication)
```

**When called:**
- Incoming phone call
- SMS message
- Switching to another app
- Control Center/Notification Center opened

**Use cases:**
- Pause ongoing tasks
- Disable timers
- Pause games/drills

**Current status:** Empty (placeholder comments only)

### Enter Background
```swift
func applicationDidEnterBackground(_ application: UIApplication)
```

**When called:**
- App no longer visible
- User pressed home button
- Switched to another app

**Use cases:**
- Save user data
- Release shared resources
- Pause AR session
- Store app state

**Current status:** Empty (placeholder comments only)

### Enter Foreground
```swift
func applicationWillEnterForeground(_ application: UIApplication)
```

**When called:**
- App becoming visible again
- Returning from background

**Use cases:**
- Resume AR session
- Refresh UI
- Reconnect camera
- Restore paused tasks

**Current status:** Empty (placeholder comments only)

### Become Active
```swift
func applicationDidBecomeActive(_ application: UIApplication)
```

**When called:**
- App fully active and receiving events
- After launching or returning to foreground

**Use cases:**
- Start/resume timers
- Refresh interface
- Resume animations
- Restart camera session

**Current status:** Empty (placeholder comments only)

## Orientation Locking Mechanism

### How Views Use It

#### PuckTrackingView (Portrait Only)
```swift
.onAppear {
    AppDelegate.orientationLock = .portrait
}
.onDisappear {
    AppDelegate.orientationLock = .all
}
```

**Effect:**
- Camera feed stays in portrait orientation
- Prevents rotation during tracking
- Mimics ARKit behavior (fixed camera orientation)

#### ARCourseView (All Orientations)
Uses default `.all` orientation (could be made portrait-only too).

### Orientation Masks

**Available options:**
```swift
.portrait          // Only portrait
.landscape         // Only landscape (left or right)
.landscapeLeft     // Only landscape left
.landscapeRight    // Only landscape right
.portraitUpsideDown // Upside-down portrait
.allButUpsideDown  // All except upside-down
.all               // All orientations
```

## Window Hierarchy

### SwiftUI Integration
```swift
let contentView = ContentView()
let window = UIWindow(frame: UIScreen.main.bounds)
window.rootViewController = UIHostingController(rootView: contentView)
```

**Structure:**
```
UIWindow
  └── UIHostingController
       └── ContentView (SwiftUI)
            └── ARCourseView
                 └── ARViewContainer (RealityKit)
```

### Why UIHostingController?
Bridges between UIKit (UIWindow) and SwiftUI (ContentView):
- UIKit manages windows and lifecycle
- SwiftUI manages view hierarchy
- Hosting controller adapts SwiftUI for UIKit

## App State Transitions

### Lifecycle Flow
```
Not Running
    ↓ (Launch)
Inactive (didFinishLaunching)
    ↓
Active (didBecomeActive)
    ↓ (Home button)
Background (didEnterBackground)
    ↓ (Return)
Inactive (willEnterForeground)
    ↓
Active (didBecomeActive)
    ↓ (Terminate)
Not Running
```

### State Definitions

**Active:**
- App in foreground
- Receiving events
- Fully interactive

**Inactive:**
- Visible but not receiving events
- Temporary state during transitions
- Alert overlays, phone calls

**Background:**
- Not visible
- Limited execution time
- Can save state

**Suspended:**
- In memory but not executing
- Can be terminated by system

## Future Enhancements

### AR Session Management
```swift
func applicationWillResignActive(_ application: UIApplication) {
    // Pause AR session when interrupted
    NotificationCenter.default.post(
        name: Notification.Name("PauseARSession"),
        object: nil
    )
}

func applicationDidBecomeActive(_ application: UIApplication) {
    // Resume AR session
    NotificationCenter.default.post(
        name: Notification.Name("ResumeARSession"),
        object: nil
    )
}
```

### State Preservation
```swift
func applicationDidEnterBackground(_ application: UIApplication) {
    // Save current course progress
    UserDefaults.standard.set(
        currentCourseProgress,
        forKey: "lastCourseState"
    )
}

func applicationWillEnterForeground(_ application: UIApplication) {
    // Restore progress
    currentCourseProgress = UserDefaults.standard
        .value(forKey: "lastCourseState")
}
```

### Camera Cleanup
```swift
func applicationWillResignActive(_ application: UIApplication) {
    // Stop camera to save battery
    CameraManager.shared.stopSession()
}

func applicationDidBecomeActive(_ application: UIApplication) {
    // Restart camera if needed
    if shouldResumeCamera {
        CameraManager.shared.startSession()
    }
}
```

### Analytics
```swift
func applicationDidBecomeActive(_ application: UIApplication) {
    Analytics.log(event: "app_opened")
}

func applicationDidEnterBackground(_ application: UIApplication) {
    Analytics.log(event: "app_backgrounded")
}
```

## Current Implementation Notes

### Minimal Setup
The current implementation is intentionally minimal:
- Only handles basic window setup
- Lifecycle methods are placeholders
- Delegates complex behavior to SwiftUI views

**Why minimal?**
- SwiftUI views handle their own lifecycle (`.onAppear`, `.onDisappear`)
- Modern apps favor view-level state management
- Less coupling between app delegate and features

### Orientation Lock Strategy
Global static property is a simple but effective approach:
- Easy for views to control
- No complex notification system needed
- Immediate effect on rotation behavior

**Trade-off:**
- Global state (not ideal for complex apps)
- Only one view can control at a time
- Last view to set wins

## Related Files
- `ContentView.swift`: Root SwiftUI view
- `PuckTrackingView.swift`: Uses orientation lock
- `ARCourseView.swift`: Could use orientation lock

## Dependencies
- `UIKit`: For app delegate and window management
- `SwiftUI`: For `ContentView` and `UIHostingController`

## Platform Requirements
- iOS 13.0+ (SwiftUI support)

## SwiftUI vs UIKit App Delegate

### Modern SwiftUI App
Could use `@main App` instead:
```swift
@main
struct StickHandleApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
```

### Why UIKit AppDelegate Here?
1. **Orientation Control:** Easier access to orientation delegate method
2. **Compatibility:** Works with older iOS versions
3. **Flexibility:** More control over window setup
4. **Familiarity:** Standard pattern for AR/camera apps

## Testing Considerations

### Orientation Lock Testing
```swift
// Test that lock is applied
AppDelegate.orientationLock = .portrait
XCTAssertEqual(
    appDelegate.application(
        UIApplication.shared,
        supportedInterfaceOrientationsFor: nil
    ),
    .portrait
)
```

### Lifecycle Testing
```swift
// Test launch setup
let appDelegate = AppDelegate()
_ = appDelegate.application(
    UIApplication.shared,
    didFinishLaunchingWithOptions: nil
)

XCTAssertNotNil(appDelegate.window)
XCTAssertTrue(appDelegate.window?.isKeyWindow == true)
```

## Best Practices

### Avoid Heavy Work in Lifecycle
- Keep launch fast (< 400ms recommended)
- Defer initialization to views
- Use lazy loading

### Resource Management
- Release camera in background
- Pause AR sessions when inactive
- Save important state before suspension

### Thread Safety
- All lifecycle methods called on main thread
- Safe to update UI directly
- Avoid blocking operations
