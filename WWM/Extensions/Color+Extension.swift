//
//  Color+Extension.swift
//  WWM
//
//  Created by F on 18.08.25.
//

import SwiftUI

extension Color {
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let length = hexSanitized.count

        let r, g, b, a: Double

        switch length {
        case 3:
            r = Double((rgb & 0xF00) >> 8) / 15
            g = Double((rgb & 0x0F0) >> 4) / 15
            b = Double(rgb & 0x00F) / 15
            a = 1.0
        case 4:
            r = Double((rgb & 0xF000) >> 12) / 15
            g = Double((rgb & 0x0F00) >> 8) / 15
            b = Double((rgb & 0x00F0) >> 4) / 15
            a = Double(rgb & 0x000F) / 15
        case 6:
            r = Double((rgb & 0xFF0000) >> 16) / 255
            g = Double((rgb & 0x00FF00) >> 8) / 255
            b = Double(rgb & 0x0000FF) / 255
            a = 1.0
        case 8:
            r = Double((rgb & 0xFF000000) >> 24) / 255
            g = Double((rgb & 0x00FF0000) >> 16) / 255
            b = Double((rgb & 0x0000FF00) >> 8) / 255
            a = Double(rgb & 0x000000FF) / 255
        default:
            r = 0.5; g = 0.5; b = 0.5; a = 1.0
        }

        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}
