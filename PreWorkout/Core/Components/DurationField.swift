import SwiftUI

/// Hours · minutes · seconds wheels (like the Clock timer). Works on whole seconds.
struct DurationWheel: View {
    @Binding var seconds: Double
    var maxHours = 10

    var body: some View {
        let p = DurationText.parts(Int(seconds.rounded()))
        HStack(spacing: 0) {
            wheel(0...maxHours, value: p.h, unit: Text("godz."), part: .hour)
            wheel(0...59, value: p.m, unit: Text("min"), part: .minute)
            wheel(0...59, value: p.s, unit: Text("sek."), part: .second)
        }
        .frame(height: 150)
    }

    private enum Part { case hour, minute, second }

    private func set(h: Int, m: Int, s: Int) {
        seconds = Double(h * 3600 + m * 60 + s)
    }

    private func wheel(_ range: ClosedRange<Int>, value: Int, unit: Text, part: Part) -> some View {
        HStack(spacing: 2) {
            Picker(selection: Binding(
                get: { value },
                set: { newValue in
                    MainActor.assumeIsolated {
                        let p = DurationText.parts(Int(seconds.rounded()))
                        switch part {
                        case .hour: set(h: newValue, m: p.m, s: p.s)
                        case .minute: set(h: p.h, m: newValue, s: p.s)
                        case .second: set(h: p.h, m: p.m, s: newValue)
                        }
                    }
                }
            )) {
                ForEach(range, id: \.self) { n in
                    Text(verbatim: "\(n)").monospacedDigit().tag(n)
                }
            } label: {
                unit
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            .frame(minWidth: 44)
            .clipped()
            unit.font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Form row for a duration: shows "1:30" / "1:05:03", tap to edit with wheels.
struct DurationField: View {
    let title: LocalizedStringKey
    @Binding var seconds: Double?
    @State private var editing = false

    init(_ title: LocalizedStringKey, seconds: Binding<Double?>) {
        self.title = title
        _seconds = seconds
    }

    init(_ title: LocalizedStringKey, wholeSeconds: Binding<Int?>) {
        self.title = title
        _seconds = Binding(
            get: { wholeSeconds.wrappedValue.map(Double.init) },
            set: { wholeSeconds.wrappedValue = $0.map { Int($0.rounded()) } }
        )
    }

    var body: some View {
        Group {
            Button {
                withAnimation(.snappy) { editing.toggle() }
            } label: {
                LabeledContent(title) {
                    Text(verbatim: seconds.map { DurationText.format($0) } ?? "–")
                        .monospacedDigit()
                        .foregroundStyle(editing ? Color.accentColor : Color.secondary)
                }
            }
            .tint(.primary)
            if editing {
                DurationWheel(seconds: Binding(get: { seconds ?? 0 }, set: { seconds = $0 > 0 ? $0 : nil }))
                if seconds != nil {
                    Button("Wyczyść", role: .destructive) {
                        seconds = nil
                        withAnimation(.snappy) { editing = false }
                    }
                }
            }
        }
    }
}
