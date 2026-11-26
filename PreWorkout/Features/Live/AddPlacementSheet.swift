import SwiftUI

/// Where a freshly picked exercise goes. A sheet with four clear rows instead
/// of a dialog (on iOS 26 dialogs became popovers with an arrow).
struct AddPlacementSheet: View {
    let exerciseName: String
    let currentName: String
    let onPick: (AddMode) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 4) {
                Text("Gdzie dodać?").lvCaps()
                Text(verbatim: exerciseName)
                    .font(.system(size: 20, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(.top, 22)

            VStack(spacing: 8) {
                row(.next, icon: "arrow.turn.down.right", title: Text("Zaraz po bieżącym"), detail: Text("Następne po: \(currentName)"))
                row(.end, icon: "text.append", title: Text("Na koniec"), detail: Text("Ostatnie ćwiczenie treningu"))
                row(.superset, icon: "arrow.left.arrow.right", title: Text("Superseria z bieżącym"), detail: Text("Na zmianę z: \(currentName), przerwa po rundzie"))
                row(.combo, icon: "link", title: Text("Do bieżącej kombinacji"), detail: Text("Kolejny ruch tej samej serii, bez przerwy"))
            }

            Button("Anuluj") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LV.muted)
                .frame(height: 44)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .foregroundStyle(LV.text)
        .lvSheet([.medium, .large])
    }

    private func row(_ mode: AddMode, icon: String, title: Text, detail: Text) -> some View {
        Button {
            onPick(mode)
            dismiss()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 40, height: 40)
                    .background(.white.opacity(0.08), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    title.font(.system(size: 16, weight: .semibold))
                    detail.font(.system(size: 13)).foregroundStyle(LV.muted).lineLimit(2)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(LV.faint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lvGlass(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(LVPress(scale: 0.97))
    }
}

extension View {
    /// The live stage swipe zone: the whole view is a hit area for `gesture`,
    /// recognised together with the buttons inside it.
    func browsable<G: Gesture>(_ gesture: G) -> some View {
        contentShape(Rectangle()).simultaneousGesture(gesture)
    }
}
