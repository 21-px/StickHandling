//
//  ARCourseView.swift
//  StickHandle
//
//  Created by Tyson on 3/5/26.
//

/// Input: Selected course, puck tracking data
/// Transformation: Renders AR course lines, validates crossings, shows timer and score
/// Output: Full AR experience with course visualization and real-time feedback

import SwiftUI
import RealityKit
import ARKit
import Combine

struct ARCourseView: View {
    
    let course: Course
    
    @StateObject private var puckTracker = PuckTracker()
    @StateObject private var validator: CourseValidator
    @StateObject private var coordinateMapper = CoordinateMapper()
    
    @State private var hasStarted = false
    @State private var cancellables = Set<AnyCancellable>()
    @State private var orientation = UIDeviceOrientation.portrait
    @State private var isRecalibrating = false
    @State private var showPuckTrackingView = false
    @State private var arSession: ARSession?
    @State private var cameraIntrinsics: simd_float3x3?
    
    init(course: Course) {
        self.course = course
        _validator = StateObject(wrappedValue: CourseValidator(course: course))
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // AR view with course lines
                ARViewContainer(
                    course: course,
                    validator: validator,
                    coordinateMapper: coordinateMapper,
                    puckTracker: puckTracker,
                    shouldRecenter: $isRecalibrating,
                    arSession: $arSession,
                    cameraIntrinsics: $cameraIntrinsics
                )
                .edgesIgnoringSafeArea(.all)
                .gesture(
                    // Long press to recenter course
                    LongPressGesture(minimumDuration: 1.0)
                        .onEnded { _ in
                            recenterCourse()
                        }
                )
                
                // Puck tracking overlay (show red circle around puck)
                if let puckPosition = puckTracker.puckPosition {
                    PuckOverlay(
                        position: puckPosition,
                        viewSize: geometry.size,
                        transformForARKit: true,  // Enable ARKit coordinate transformation
                        orientation: orientation,
                        cameraIntrinsics: cameraIntrinsics
                    )
                    .allowsHitTesting(false) // Don't interfere with gestures
                }
                
                // Course UI overlay
                VStack {
                    // Top: Timer, Score, and Debug Button
                    HStack {
                        CourseStatsView(
                            crossCount: validator.crossCount,
                            timeRemaining: validator.timeRemaining,
                            isComplete: validator.isComplete
                        )
                        .padding()
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(12)
                        
                        Spacer()
                        
                        // Debug: Switch to Puck Tracking View
                        Button(action: {
                            showPuckTrackingView = true
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "eye.circle.fill")
                                    .font(.title2)
                                Text("Debug")
                                    .font(.caption2)
                            }
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.blue.opacity(0.8)) // Make more visible
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Calibration message (shows briefly on recenter)
                    if isRecalibrating {
                        Text("Course repositioned!")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.green.opacity(0.8))
                            .cornerRadius(8)
                            .transition(.scale.combined(with: .opacity))
                    }
                    
                    Spacer()
                    
                    // Bottom: Start button or completion message
                    if !hasStarted {
                        VStack(spacing: 16) {
                            Text("Long-press screen to recenter course")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal)
                            
                            Button(action: startCourse) {
                                Text("Start Course")
                                    .font(.title2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 40)
                                    .padding(.vertical, 16)
                                    .background(Color.green)
                                    .cornerRadius(12)
                            }
                        }
                        .padding(.bottom, 40)
                    } else if validator.isComplete {
                        CourseCompleteView(
                            crossCount: validator.crossCount,
                            successCriteria: course.successCriteria
                        )
                        .padding()
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $showPuckTrackingView) {
            PuckTrackingView()
                .onAppear {
                    // Pause AR session when showing debug view
                    arSession?.pause()
                }
                .onDisappear {
                    // Resume AR session when returning
                    if let session = arSession {
                        let config = ARWorldTrackingConfiguration()
                        config.planeDetection = [.horizontal]
                        session.run(config)
                    }
                }
        }
        .onAppear {
            setupTracking()
            setupOrientationObserver()
        }
        .onDisappear {
            arSession?.pause()
            validator.stopCourse()
        }
    }
    
    private func recenterCourse() {
        isRecalibrating = true
        
        // Brief haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // Hide message after brief confirmation (0.5 seconds since it's instant now)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation {
                isRecalibrating = false
            }
        }
    }
    
    private func setupOrientationObserver() {
        NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            let newOrientation = UIDevice.current.orientation
            if newOrientation.isValidInterfaceOrientation {
                orientation = newOrientation
            }
        }
    }
    
    private func setupTracking() {
        // Get frames directly from ARKit (passed via ARSessionDelegate)
        
        // Subscribe to puck position updates
        puckTracker.$puckPosition
            .compactMap { $0 }
            .sink { position in
                // Map 2D puck position to 3D world space
                let worldPosition = coordinateMapper.mapToPlaneSpace(
                    normalizedPosition: CGPoint(x: position.x, y: position.y)
                )
                
                // Update course validator
                validator.updatePuckPosition(worldPosition)
            }
            .store(in: &cancellables)
    }
    
    private func startCourse() {
        hasStarted = true
        validator.startCourse()
    }
}

// MARK: - AR View Container

struct ARViewContainer: UIViewRepresentable {
    let course: Course
    let validator: CourseValidator
    let coordinateMapper: CoordinateMapper
    let puckTracker: PuckTracker
    @Binding var shouldRecenter: Bool
    @Binding var arSession: ARSession?
    @Binding var cameraIntrinsics: simd_float3x3?
    
    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        
        // IMPORTANT: Enable camera feed background so we can see what ARKit sees
        // Without this, ARView just shows virtual content on a transparent background
        arView.environment.background = .cameraFeed()
        
        // Configure AR session
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal]
        arView.session.run(config)
        
        // Store session reference so parent can control it
        DispatchQueue.main.async {
            arSession = arView.session
        }
        
        // Store references
        context.coordinator.arView = arView
        context.coordinator.course = course
        
        // Set up AR scene (now just initializes, actual course created on plane detection)
        context.coordinator.setupScene(arView: arView, course: course)
        
        // Subscribe to plane detection
        arView.session.delegate = context.coordinator
        
        return arView
    }
    
    func updateUIView(_ uiView: ARView, context: Context) {
        // Update active line visualization
        context.coordinator.updateActiveLineVisual(activeLine: validator.activeLine)
        
        // Handle recenter request
        if shouldRecenter && !context.coordinator.isRecentering {
            context.coordinator.recenterCourse()
            DispatchQueue.main.async {
                shouldRecenter = false
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(validator: validator, coordinateMapper: coordinateMapper, puckTracker: puckTracker, cameraIntrinsics: $cameraIntrinsics)
    }
    
    class Coordinator: NSObject, ARSessionDelegate {
        let validator: CourseValidator
        let coordinateMapper: CoordinateMapper
        let puckTracker: PuckTracker
        var lineEntities: [ModelEntity] = []
        var planeAnchor: AnchorEntity?
        var course: Course?
        weak var arView: ARView?
        var isRecentering = false
        var cameraIntrinsics: Binding<simd_float3x3?>
        
        init(validator: CourseValidator, coordinateMapper: CoordinateMapper, puckTracker: PuckTracker, cameraIntrinsics: Binding<simd_float3x3?>) {
            self.validator = validator
            self.coordinateMapper = coordinateMapper
            self.puckTracker = puckTracker
            self.cameraIntrinsics = cameraIntrinsics
        }
        
        func recenterCourse() {
            isRecentering = true
            
            guard let arView = arView, let course = course else {
                isRecentering = false
                return
            }
            
            // Get current camera transform
            guard let cameraTransform = arView.session.currentFrame?.camera.transform else {
                isRecentering = false
                return
            }
            
            // Create a raycast from the camera to find where it's pointing on the plane
            let screenCenter = CGPoint(x: 0.5, y: 0.5) // Center of screen in normalized coordinates
            
            // Perform raycast to find intersection with horizontal plane
            let query = arView.makeRaycastQuery(
                from: screenCenter,
                allowing: .existingPlaneGeometry,
                alignment: .horizontal
            )
            
            if let query = query,
               let result = arView.session.raycast(query).first {
                
                // Found intersection point - place course here!
                repositionCourse(at: result.worldTransform, arView: arView, course: course)
                
            } else {
                // No plane intersection found, place course 1 meter in front of camera
                var transform = cameraTransform
                // Move 1 meter forward from camera
                transform.columns.3.z -= 1.0
                // Project to ground level (y = 0 or current plane height)
                if let planeAnchor = planeAnchor as? AnchorEntity {
                    transform.columns.3.y = planeAnchor.position.y
                }
                
                repositionCourse(at: transform, arView: arView, course: course)
            }
            
            // Done recentering
            DispatchQueue.main.async {
                self.isRecentering = false
            }
        }
        
        /// Reposition the course to a new location (keeps existing anchor if possible)
        private func repositionCourse(at transform: simd_float4x4, arView: ARView, course: Course) {
            // Remove old line entities
            for entity in lineEntities {
                entity.removeFromParent()
            }
            lineEntities.removeAll()
            
            // If we don't have an anchor yet, create one
            if planeAnchor == nil {
                let anchor = AnchorEntity(world: transform)
                planeAnchor = anchor
                arView.scene.addAnchor(anchor)
            }
            
            // Update anchor position to new location
            if let anchor = planeAnchor {
                anchor.transform.matrix = transform
                
                // Create new line entities at this position
                for (index, element) in course.elements.enumerated() {
                    if case .crossLine(let start, let end, _) = element {
                        let lineEntity = createLineEntity(from: start, to: end, isActive: index == 0)
                        lineEntities.append(lineEntity)
                        anchor.addChild(lineEntity)
                    }
                }
            }
        }
        
        func setupScene(arView: ARView, course: Course) {
            // Don't create anchor immediately - wait for plane detection
            // Lines will be added when plane is detected
        }
        
        func createCourseOnPlane(planeAnchor: ARPlaneAnchor, arView: ARView, course: Course) {
            // Only create course if we don't have one yet
            guard self.planeAnchor == nil else { return }
            
            // Use the plane anchor's transform to position the course
            repositionCourse(at: planeAnchor.transform, arView: arView, course: course)
        }
        
        func createLineEntity(from start: SIMD3<Float>, to end: SIMD3<Float>, isActive: Bool) -> ModelEntity {
            // Calculate line parameters
            let midpoint = (start + end) / 2
            let length = simd_distance(start, end)
            let lineWidth: Float = 0.05  // Thicker line for visibility
            let lineHeight: Float = 0.005 // Thin vertical profile
            
            // Create a thin box to represent the line
            let mesh = MeshResource.generateBox(width: lineWidth, height: lineHeight, depth: length)
            
            // Material - bright color for active, dimmer for inactive
            // Use UnlitMaterial for glowing effect
            let color: UIColor = isActive ? .systemGreen : .systemOrange
            var material = UnlitMaterial(color: color)
            
            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = midpoint
            
            // Rotate to align with line direction
            let direction = normalize(end - start)
            let angle = atan2(direction.x, direction.z)
            entity.orientation = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
            
            return entity
        }
        
        func updateActiveLineVisual(activeLine: Int) {
            // Update materials to show which line is active
            for (index, entity) in lineEntities.enumerated() {
                let isActive = index == activeLine
                let color: UIColor = isActive ? .systemGreen : .systemOrange
                let material = UnlitMaterial(color: color)
                entity.model?.materials = [material]
            }
        }
        
        // MARK: - ARSessionDelegate
        
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            for anchor in anchors {
                if let planeAnchor = anchor as? ARPlaneAnchor, planeAnchor.alignment == .horizontal {
                    // Found a horizontal plane - create course here!
                    coordinateMapper.updatePlane(planeAnchor)
                    
                    // Only create course on first plane detected
                    if self.planeAnchor == nil, let arView = self.arView, let course = self.course {
                        createCourseOnPlane(planeAnchor: planeAnchor, arView: arView, course: course)
                    }
                }
            }
        }
        
        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            coordinateMapper.updateCamera(frame.camera.transform)
            
            // Update camera intrinsics for parent view
            let intrinsics = frame.camera.intrinsics
            cameraIntrinsics.wrappedValue = intrinsics
            
            // IMPORTANT: Pass ARKit camera frames to puck tracker
            // This provides the live camera feed for puck tracking
            // Also pass camera intrinsics for distance estimation
            puckTracker.processFrame(frame.capturedImage, cameraIntrinsics: intrinsics)
        }
    }
}

// MARK: - Course Stats View

struct CourseStatsView: View {
    let crossCount: Int
    let timeRemaining: TimeInterval
    let isComplete: Bool
    
    var body: some View {
        VStack(spacing: 12) {
            // Timer
            HStack {
                Image(systemName: "timer")
                    .foregroundColor(.white)
                Text(String(format: "%.1fs", timeRemaining))
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(timeRemaining < 5 ? .red : .white)
            }
            
            // Score
            HStack {
                Image(systemName: "flag.checkered")
                    .foregroundColor(.white)
                Text("\(crossCount) crosses")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Course Complete View

struct CourseCompleteView: View {
    let crossCount: Int
    let successCriteria: Course.SuccessCriteria
    
    var didSucceed: Bool {
        switch successCriteria {
        case .minimumCrosses(let required):
            return crossCount >= required
        case .minimumScore(let required):
            return crossCount >= required
        case .allElementsCompleted:
            return true
        }
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: didSucceed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(didSucceed ? .green : .red)
            
            Text(didSucceed ? "Course Complete!" : "Try Again!")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)
            
            Text("\(crossCount) crosses")
                .font(.title2)
                .foregroundColor(.white)
            
            if case .minimumCrosses(let required) = successCriteria {
                Text("Target: \(required) crosses")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
            }
        }
        .padding(32)
        .background(Color.black.opacity(0.8))
        .cornerRadius(16)
    }
}

// MARK: - Preview

#Preview {
    ARCourseView(course: .sideShuttleBeginner)
}
