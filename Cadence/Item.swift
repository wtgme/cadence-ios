//
//  Item.swift
//  Cadence
//
//  Created by Tao Wang on 17/05/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
