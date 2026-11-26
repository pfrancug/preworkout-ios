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
                LabeledContent("Data urodzenia") {
                    if form.birthDate != nil {
                        DatePicker("Data urodzenia", selection: birthDateBinding,
                                   in: BirthDate.pickerRange(), displayedComponents: .date)
                            .labelsHidden()
                    } else {
                        Button("Wybierz datę") {
                            form.birthDate = BirthDate.iso(from: BirthDate.defaultDate())
                        }
                    }
                }
                if let age = form.effectiveAge {
                    LabeledContent("Wiek") {
                        Text("\(age) lat").foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Wzrost") {
                    HStack(spacing: 4) {
                        TextField("–", text: $form.height)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: form.height) { _, value in
                                let digits = String(value.filter { $0.isASCII && $0.isNumber }.prefix(3))
                                if digits != value { form.height = digits }
                            }
                        Text(verbatim: "cm").foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("Płeć, wiek (z daty urodzenia) i wzrost są używane w kalkulatorze kalorii.")
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
            || form.birthDate != base.birthDate || form.height != base.height || form.sex != base.sex
    }

    /// Nothing filled in yet; the age counts via the birth date or a sane legacy age.
    private var isIncompleteProfile: Bool {
        base.effectiveAge == nil
            && [base.name, base.lastName, base.height, base.sex]
                .allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var birthDateBinding: Binding<Date> {
        Binding(
            get: { form.birthDate.flatMap(BirthDate.date(from:)) ?? BirthDate.defaultDate() },
            set: { form.birthDate = BirthDate.iso(from: $0) }
        )
    }

    private func validated() -> UserSettings? {
        let height = form.height.trimmingCharacters(in: .whitespaces)
        if let birthDate = form.birthDate, BirthDate.validAge(from: birthDate) == nil {
            error = String(localized: "Wiek musi mieścić się w przedziale 10–100 lat.")
            return nil
        }
        if let value = Int(height), !Limits.heightCm.contains(Double(value)) {
            error = Limits.heightCm.message
            return nil
        }
        if !height.isEmpty && Int(height) == nil {
            error = String(localized: "Wzrost musi być liczbą.")
            return nil
        }
        var body = form
        body.name = form.name.trimmingCharacters(in: .whitespaces).capped(Limits.titleLength)
        body.lastName = form.lastName.trimmingCharacters(in: .whitespaces).capped(Limits.titleLength)
        // The server computes the age from the birth date; older builds read `age`.
        body.age = form.birthDate.flatMap { BirthDate.validAge(from: $0) }.map(String.init)
            ?? BirthDate.legacyAge(form.age).map(String.init) ?? ""
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
