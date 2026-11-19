import SwiftUI

/// Live workout ("Prowadź trening"): planned for milestone v0.3.
/// Web counterpart: `src/components/live/*` (clock, rest timer, set entry,
/// supersets); finishing saves a normal workout via POST /workouts.
struct LiveWorkoutView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Prowadź trening", systemImage: "timer")
        } description: {
            Text("Trening na żywo pojawi się w kolejnej wersji: zegar, przerwy, szybkie wpisywanie serii.")
        }
        .navigationTitle("Prowadź trening")
    }
}
