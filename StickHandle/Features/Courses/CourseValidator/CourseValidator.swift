//
//  CourseValidator.swift
//  StickHandle
//
//  Created by Tyson on 3/5/26.
//

/// Input: Puck positions over time, course definition
/// Transformation: Validates line crossings, tracks progress, determines course completion
/// Output: Course state (crosses count, active line, completion status)

import Foundation
import Combine
import simd

/// Validates course progress and tracks line crossings
class CourseValidator: ObservableObject {
    
    // Published state that UI can observe
    @Published var crossCount: Int = 0
    @Published var activeLine: Int = 0
    @Published var isComplete: Bool = false
    @Published var timeRemaining: TimeInterval = 0
    
    private let course: Course
    private var lastPuckPosition: SIMD3<Float>?
    private var lastCrossedLine: Int? = nil
    private var timer: Timer?
    private var startTime: Date?
    
    init(course: Course) {
        self.course = course
        self.timeRemaining = course.timeLimit
    }
    
    /// Start the course timer
    func startCourse() {
        startTime = Date()
        crossCount = 0
        activeLine = 0
        isComplete = false
        timeRemaining = course.timeLimit
        lastCrossedLine = nil
        
        // Update timer every 0.1 seconds for smooth countdown
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.updateTimer()
        }
    }
    
    /// Stop the course
    func stopCourse() {
        timer?.invalidate()
        timer = nil
    }
    
    /// Update puck position and check for line crosses
    func updatePuckPosition(_ position: SIMD3<Float>) {
        defer { lastPuckPosition = position }
        
        guard !isComplete, let lastPos = lastPuckPosition else {
            lastPuckPosition = position
            return
        }
        
        // Check if crossed the active line
        if didCrossLine(from: lastPos, to: position, lineIndex: activeLine) {
            handleLineCross()
        }
    }
    
    /// Check if course success criteria is met
    func checkCompletion() -> Bool {
        switch course.successCriteria {
        case .minimumCrosses(let required):
            return crossCount >= required
        case .allElementsCompleted:
            return crossCount >= course.elements.count
        case .minimumScore(let required):
            return crossCount >= required
        }
    }
    
    // MARK: - Private Methods
    
    private func updateTimer() {
        guard let start = startTime else { return }
        
        let elapsed = Date().timeIntervalSince(start)
        timeRemaining = max(0, course.timeLimit - elapsed)
        
        if timeRemaining <= 0 {
            completeCourse()
        }
    }
    
    private func completeCourse() {
        isComplete = true
        timer?.invalidate()
        timer = nil
    }
    
    private func handleLineCross() {
        // Only count if it's NOT the same line we just crossed
        // This prevents double-counting when puck hovers near line
        if lastCrossedLine != activeLine {
            crossCount += 1
            lastCrossedLine = activeLine
            
            // Switch to the other line for alternating mode
            if course.repeatMode == .alternating {
                activeLine = (activeLine + 1) % course.elements.count
            }
            
            // Check if course is complete
            if checkCompletion() && timeRemaining > 0 {
                completeCourse()
            }
        }
    }
    
    /// Check if path from lastPos to currentPos crossed a line
    private func didCrossLine(from lastPos: SIMD3<Float>, to currentPos: SIMD3<Float>, lineIndex: Int) -> Bool {
        guard lineIndex < course.elements.count else { return false }
        
        let element = course.elements[lineIndex]
        
        switch element {
        case .crossLine(let lineStart, let lineEnd, _):
            // Check if the puck's path (line segment from lastPos to currentPos)
            // intersects with the course line (from lineStart to lineEnd)
            return lineSegmentsIntersect(
                a1: SIMD2<Float>(lastPos.x, lastPos.z),
                a2: SIMD2<Float>(currentPos.x, currentPos.z),
                b1: SIMD2<Float>(lineStart.x, lineStart.z),
                b2: SIMD2<Float>(lineEnd.x, lineEnd.z)
            )
            
        case .checkpoint(let position, let radius):
            // Check if puck is within checkpoint radius
            let distance = simd_distance(currentPos, position)
            return distance <= radius
        }
    }
    
    /// Check if two line segments intersect (2D, ignoring Y axis)
    /// This is classic computational geometry
    private func lineSegmentsIntersect(
        a1: SIMD2<Float>, a2: SIMD2<Float>,
        b1: SIMD2<Float>, b2: SIMD2<Float>
    ) -> Bool {
        // Vector cross product to determine orientation
        func ccw(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
            return (c.y - a.y) * (b.x - a.x) - (b.y - a.y) * (c.x - a.x)
        }
        
        let ccw1 = ccw(a1, a2, b1)
        let ccw2 = ccw(a1, a2, b2)
        let ccw3 = ccw(b1, b2, a1)
        let ccw4 = ccw(b1, b2, a2)
        
        // Segments intersect if the endpoints of one segment are on opposite sides of the other
        if (ccw1 * ccw2 < 0) && (ccw3 * ccw4 < 0) {
            return true
        }
        
        // Check for collinear overlapping (edge case)
        if ccw1 == 0 && onSegment(a1, b1, a2) { return true }
        if ccw2 == 0 && onSegment(a1, b2, a2) { return true }
        if ccw3 == 0 && onSegment(b1, a1, b2) { return true }
        if ccw4 == 0 && onSegment(b1, a2, b2) { return true }
        
        return false
    }
    
    /// Check if point q is on line segment pr
    private func onSegment(_ p: SIMD2<Float>, _ q: SIMD2<Float>, _ r: SIMD2<Float>) -> Bool {
        return q.x <= max(p.x, r.x) && q.x >= min(p.x, r.x) &&
               q.y <= max(p.y, r.y) && q.y >= min(p.y, r.y)
    }
}
