import PhotosUI
import SwiftUI

/// Edit the active person's profile: photo, name and the body parameters of the calculator.
struct EditProfileView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    var onSaved: (UserSettings) -> Void

    /// Last saved version (photo changes are saved at once).
    @State private var base: UserSettings
    @State private var form: UserSettings
    @State private var saving = false
    @State private var error: String?
    @State private var saved = 0
    @State private var photo: PhotosPickerItem?
    @State private var updatingPhoto = false

    init(settings: UserSettings, onSaved: @escaping (UserSettings) -> Void) {
        self.onSaved = onSaved
        _base = State(initialValue: settings)
        _form = State(initialValue: settings)
    }

    var body: some View {
        Form {
            photoSection

            Section {
                LabeledContent("Imię") {
                    TextField("–", text: $form.name)
                        .textContentType(.givenName)
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Nazwisko") {
                    TextField("–", text: $form.lastName)
                        .textContentType(.familyName)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                Picker("Płeć", selection: $form.sex) {
                    ForEach(["", "male", "female"], id: \.self) { Text(Labels.sex($0)).tag($0) }
                }
                LabeledContent("Wiek") {
                    HStack(spacing: 4) {
                        TextField("–", text: $form.age)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text("lat").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Wzrost") {
                    HStack(spacing: 4) {
                        TextField("–", text: $form.height)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                        Text(verbatim: "cm").foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Płeć, wiek i wzrost są używane w kalkulatorze kalorii.")
            }

            if let error {
                Section { ErrorText(message: error) }
            }
        }
        .navigationTitle("Edytuj profil")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Zapisz") { Task { await save() } }
                    .disabled(!hasChanges || saving)
            }
        }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.error, trigger: error) { _, new in new != nil }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { await setPhoto(item) }
        }
        .onAppear {
            if isIncompleteProfile {
                Analytics.send("Onboarding.stepViewed", ["step": "profileSetup"])
            }
        }
    }

    private var photoSection: some View {
        let hasPhoto = !(base.avatarUrl ?? "").isEmpty
        return Section {
            VStack(spacing: 12) {
                ZStack {
                    AvatarView(url: base.avatarUrl, name: base.displayName)
                    if updatingPhoto {
                        ProgressView()
                            .frame(width: 72, height: 72)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                HStack(spacing: 16) {
                    PhotosPicker(selection: $photo, matching: .images) {
                        (hasPhoto ? Text("Zmień zdjęcie") : Text("Dodaj zdjęcie"))
                            .font(.subheadline)
                    }
                    if hasPhoto {
                        Button("Usuń", role: .destructive) { Task { await removePhoto() } }
                            .font(.subheadline)
                    }
                }
                .buttonStyle(.borderless)
                .disabled(updatingPhoto)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.clear)
    }

    private var hasChanges: Bool {
        form.name != base.name || form.lastName != base.lastName
            || form.age != base.age || form.height != base.height || form.sex != base.sex
    }

    private var isIncompleteProfile: Bool {
        [base.name, base.lastName, base.age, base.height, base.sex]
            .allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private func validated() -> UserSettings? {
        let age = form.age.trimmingCharacters(in: .whitespaces)
        let height = form.height.trimmingCharacters(in: .whitespaces)
        if let value = Int(age), !(1...150).contains(value) {
            error = String(localized: "Wiek musi być w zakresie 1–150.")
            return nil
        }
        if let value = Int(height), !(50...300).contains(value) {
            error = String(localized: "Wzrost musi być w zakresie 50–300 cm.")
            return nil
        }
        if (!age.isEmpty && Int(age) == nil) || (!height.isEmpty && Int(height) == nil) {
            error = String(localized: "Wiek i wzrost muszą być liczbami.")
            return nil
        }
        var body = form
        body.name = form.name.trimmingCharacters(in: .whitespaces)
        body.lastName = form.lastName.trimmingCharacters(in: .whitespaces)
        body.age = age
        body.height = height
        return body
    }

    private func save() async {
        guard let body = validated() else { return }
        saving = true
        error = nil
        defer { saving = false }
        do {
            let wasIncomplete = isIncompleteProfile
            try await APIClient.shared.saveSettings(body, person: appState.activePersonId)
            Analytics.send(wasIncomplete ? "Profile.completed" : "Profile.edited")
            base = body
            form = body
            saved += 1
            onSaved(body)
            try? await appState.loadPeople()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func setPhoto(_ item: PhotosPickerItem) async {
        updatingPhoto = true
        defer {
            updatingPhoto = false
            photo = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let url = AvatarView.dataURL(from: data) else {
            error = String(localized: "Nie udało się wczytać zdjęcia.")
            return
        }
        // Keep unsaved form edits out of the photo update.
        var body = base
        body.avatarUrl = url
        await persistPhoto(body)
    }

    private func removePhoto() async {
        updatingPhoto = true
        defer { updatingPhoto = false }
        var body = base
        body.avatarUrl = ""
        await persistPhoto(body)
    }

    private func persistPhoto(_ body: UserSettings) async {
        do {
            try await APIClient.shared.saveSettings(body, person: appState.activePersonId)
            base = body
            form.avatarUrl = body.avatarUrl
            saved += 1
            onSaved(body)
            try? await appState.loadPeople()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
