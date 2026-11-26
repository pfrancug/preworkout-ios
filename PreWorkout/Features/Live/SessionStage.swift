import SwiftUI

/// Live screen for a session/block: one timed practice with optional attempts and a note.
struct SessionStage: View {
    let name: String
    let elapsed: Double
    let running: Bool
    let attempts: Int
    let note: String
    let onStart: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onAttempts: (Int) -> Void
    let onNote: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            Text("Sesja").lvCaps()
            Text(verbatim: name)
                .font(.system(size: 28, weight: .heavy))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.7)
                .padding(.top, 6)
            Text(DurationText.format(elapsed))
                .font(.system(size: 72, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.45)
                .padding(.top, 18)
                .contentTransition(.numericText())
            HStack(spacing: 12) {
                if running {
                    LVPill(action: onPause) {
                        Image(systemName: "pause.fill")
                        Text("Pauza")
                    }
                } else if elapsed > 0 {
                    LVPill(action: onResume) {
                        Image(systemName: "play.fill")
                        Text("Wznów")
                    }
                } else {
                    LVPill(action: onStart) {
                        Image(systemName: "play.fill")
                        Text("Start")
                    }
                }
            }
            .padding(.top, 18)
            HStack(spacing: 14) {
                Text("Próby").font(.system(size: 15, weight: .semibold)).foregroundStyle(LV.muted)
                Button { onAttempts(max(0, attempts - 1)) } label: {
                    Image(systemName: "minus")
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .disabled(attempts == 0)
                Text(verbatim: "\(attempts)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(minWidth: 36)
                Button { onAttempts(attempts + 1) } label: {
                    Image(systemName: "plus")
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .accessibilityLabel(Text("Dodaj próbę"))
            }
            .padding(.top, 22)
            TextField("Notatka (opcjonalnie)", text: Binding(
                get: { note },
                set: { newValue in
                    MainActor.assumeIsolated { onNote(newValue) }
                }
            ), axis: .vertical)
                .lineLimit(1...3)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.top, 18)
                .padding(.horizontal, 8)
            Spacer(minLength: 8)
        }
        .foregroundStyle(LV.text)
    }
}
