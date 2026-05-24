//
//  Item.swift
//  AuGenda
//
//  Created by Arthur Ens on 2026-05-24.
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
