import SwiftUI

/// Icon and color ids of calendar activity categories (`src/constants/activities.ts` of the web app).
enum ActivityStyle {
    private static let symbols: [String: String] = [
        "dumbbell": "dumbbell",
        "footprints": "figure.run",
        "bike": "bicycle",
        "waves": "figure.pool.swim",
        "heart-pulse": "waveform.path.ecg",
        "flame": "flame",
        "mountain": "mountain.2",
        "stretching": "figure.mind.and.body",
        "sword": "figure.martial.arts",
        "trophy": "trophy",
        "volleyball": "sportscourt",
        "timer": "timer",
        "zap": "bolt",
        "target": "target",
        "wind": "wind",
        "snowflake": "snowflake",
        "rocket": "hare",
        "skip": "forward.end",
        "stretch": "figure.flexibility",
        "other": "ellipsis.circle",
    ]

    private static let palette: [String: UInt32] = [
        "slate": 0x94A3B8, "red": 0xF87171, "orange": 0xFB923C, "amber": 0xFBBF24,
        "lime": 0xA3E635, "green": 0x4ADE80, "teal": 0x2DD4BF, "sky": 0x38BDF8,
        "violet": 0xA78BFA, "fuchsia": 0xE879F9,
        // legacy ids
        "indigo": 0x818CF8, "emerald": 0x34D399, "rose": 0xFB7185, "pink": 0xF472B6,
        "cyan": 0x22D3EE, "yellow": 0xFACC15, "blue": 0x60A5FA,
    ]

    static func symbol(_ icon: String?) -> String {
        guard let icon, let symbol = symbols[icon] else { return "dumbbell" }
        return symbol
    }

    /// Accent color for nil (workouts) or an unknown id.
    static func color(_ id: String?) -> Color {
        guard let id, let hex = palette[id] else { return .accentColor }
        return Color(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
