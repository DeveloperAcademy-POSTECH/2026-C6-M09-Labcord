//
//  ExperimentProtocol.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/24/26.
//

import Foundation

public struct ExperimentProtocol: Codable {
    public var timerSeconds: [Int]
    public var materials: [String]
    public var samples: [String]
    public var glossaryTerms: [String]
    public var units: [String]
    
    public init(
        timerSeconds: [Int] = [],
        materials: [String] = [],
        samples: [String] = [],
        glossaryTerms: [String] = [],
        units: [String] = []
    ) {
        self.timerSeconds = timerSeconds
        self.materials = materials
        self.samples = samples
        self.glossaryTerms = glossaryTerms
        self.units = units
    }
}
