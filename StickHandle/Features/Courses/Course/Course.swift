//
//  Course.swift
//  StickHandle
//
//  Created by Tyson on 3/5/26.
//

/// Input: Course configuration data (name, elements, time limit, etc.)
/// Transformation: Defines the structure and rules for a stickhandling course
/// Output: Immutable course object that can be validated and tracked

import Foundation
import simd

/// Represents a complete stickhandling course with elements and rules
struct Course: Identifiable, Codable {
    let id: String
    let name: String
    let difficulty: Difficulty
    let description: String
    let elements: [CourseElement]
    let repeatMode: RepeatMode
    let timeLimit: TimeInterval
    let successCriteria: SuccessCriteria
    
    /// Difficulty levels matching Duolingo-style progression
    enum Difficulty: String, Codable {
        case beginner
        case intermediate
        case expert
    }
    
    /// How the course elements should be repeated
    enum RepeatMode: String, Codable {
        case sequential    // Complete once in order
        case alternating   // Alternate between elements (for shuttle drills)
        case continuous    // Keep repeating until time runs out
    }
    
    /// Criteria for successfully completing the course
    enum SuccessCriteria: Codable {
        case minimumCrosses(Int)           // Must cross lines at least N times
        case allElementsCompleted           // Must complete all elements once
        case minimumScore(Int)              // Must achieve minimum score
        
        enum CodingKeys: String, CodingKey {
            case type, value
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .minimumCrosses(let count):
                try container.encode("minimumCrosses", forKey: .type)
                try container.encode(count, forKey: .value)
            case .allElementsCompleted:
                try container.encode("allElementsCompleted", forKey: .type)
            case .minimumScore(let score):
                try container.encode("minimumScore", forKey: .type)
                try container.encode(score, forKey: .value)
            }
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let type = try container.decode(String.self, forKey: .type)
            
            switch type {
            case "minimumCrosses":
                let count = try container.decode(Int.self, forKey: .value)
                self = .minimumCrosses(count)
            case "allElementsCompleted":
                self = .allElementsCompleted
            case "minimumScore":
                let score = try container.decode(Int.self, forKey: .value)
                self = .minimumScore(score)
            default:
                throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown success criteria type")
            }
        }
    }
}

/// Elements that make up a course (lines to cross, checkpoints, etc.)
enum CourseElement: Codable {
    case crossLine(start: SIMD3<Float>, end: SIMD3<Float>, direction: CrossDirection)
    case checkpoint(position: SIMD3<Float>, radius: Float)
    
    enum CodingKeys: String, CodingKey {
        case type, start, end, direction, position, radius
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .crossLine(let start, let end, let direction):
            try container.encode("crossLine", forKey: .type)
            try container.encode([start.x, start.y, start.z], forKey: .start)
            try container.encode([end.x, end.y, end.z], forKey: .end)
            try container.encode(direction, forKey: .direction)
        case .checkpoint(let position, let radius):
            try container.encode("checkpoint", forKey: .type)
            try container.encode([position.x, position.y, position.z], forKey: .position)
            try container.encode(radius, forKey: .radius)
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
        case "crossLine":
            let startArray = try container.decode([Float].self, forKey: .start)
            let endArray = try container.decode([Float].self, forKey: .end)
            let direction = try container.decode(CrossDirection.self, forKey: .direction)
            self = .crossLine(
                start: SIMD3<Float>(startArray[0], startArray[1], startArray[2]),
                end: SIMD3<Float>(endArray[0], endArray[1], endArray[2]),
                direction: direction
            )
        case "checkpoint":
            let posArray = try container.decode([Float].self, forKey: .position)
            let radius = try container.decode(Float.self, forKey: .radius)
            self = .checkpoint(
                position: SIMD3<Float>(posArray[0], posArray[1], posArray[2]),
                radius: radius
            )
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Unknown element type")
        }
    }
}

/// Direction requirement for crossing a line
enum CrossDirection: String, Codable {
    case forward       // Must cross from behind
    case backward      // Must cross from front
    case leftToRight   // Must cross left to right
    case rightToLeft   // Must cross right to left
    case any          // Either direction works
}

// MARK: - Predefined Courses

extension Course {
    /// The first beginner course - side-to-side shuttle drill
    static let sideShuttleBeginner = Course(
        id: "side-shuttle-beginner",
        name: "Side Shuttle",
        difficulty: .beginner,
        description: "Move the puck side-to-side between two lines as fast as you can!",
        elements: [
            .crossLine(
                start: SIMD3<Float>(0.2, 0, 0.3),   // Line 1 - left side, vertical
                end: SIMD3<Float>(0.2, 0, 1.0),     // 0.7m tall (about 2 feet)
                direction: .any
            ),
            .crossLine(
                start: SIMD3<Float>(0.81, 0, 0.3),  // Line 2 - right side, 0.61m away (2 feet)
                end: SIMD3<Float>(0.81, 0, 1.0),
                direction: .any
            )
        ],
        repeatMode: .alternating,
        timeLimit: 30.0,
        successCriteria: .minimumCrosses(10)
    )
    
    /// All available courses
    static let allCourses: [Course] = [
        .sideShuttleBeginner
    ]
}
