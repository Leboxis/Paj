import SwiftUI

/// Configuration initiale (ou modification via Réglages). Les valeurs sont
/// enregistrées dans le trousseau iOS et testées contre l'API avant validation.
struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var existing = false

    @State private var token = ""
    @State private var driveIdText = ""
    @State private var accessCode = ""
    @State private var rootIdText = ""
    @State private var testing = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ID du drive kdrive", text: $driveIdText)
                        .keyboardType(.numberPad)
                    SecureField("Token API Infomaniak", text: $token)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    TextField("ID du dossier racine (5 par défaut)", text: $rootIdText)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Connexion kdrive")
                } footer: {
                    Text("Token à créer sur console.infomaniak.com → Gérer → API. Stocké uniquement dans le trousseau de l'iPhone.")
                }

                Section("Code d'accès à l'app") {
                    TextField("Code optionnel (chiffres)", text: $accessCode)
                        .keyboardType(.numberPad)
                }

                Section {
                    Button(testing ? "Vérification…" : "Vérifier et enregistrer") {
                        saveAndTest()
                    }
                    .disabled(testing || token.isEmpty || Int(driveIdText) == nil)
                }

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
                }
                if let successMessage {
                    Section { Text(successMessage).foregroundStyle(.green).font(.footnote) }
                }
            }
            .navigationTitle(existing ? "Modifier la config" : "Bienvenue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if existing {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Fermer") { dismiss() }
                    }
                }
            }
            .onAppear {
                if existing {
                    token = AppConfig.token
                    driveIdText = AppConfig.driveId > 0 ? String(AppConfig.driveId) : ""
                    accessCode = AppConfig.accessCode
                    rootIdText = String(AppConfig.rootDirectoryId)
                }
            }
        }
    }

    private func saveAndTest() {
        testing = true
        errorMessage = nil
        successMessage = nil
        let token = token
        let driveId = driveIdText
        let accessCode = accessCode
        let rootId = rootIdText.isEmpty ? "5" : rootIdText

        Task { @MainActor in
            AppConfig.save(token: token, driveId: driveId, accessCode: accessCode, rootId: rootId)
            do {
                let info = try await KDriveClient.shared.driveInfo()
                appState.refreshConfig()
                if existing {
                    successMessage = "Connecté au drive « \(info.name) »."
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    dismiss()
                } else {
                    appState.unlock()
                }
            } catch {
                errorMessage = "Connexion impossible : \(error.localizedDescription)"
            }
            testing = false
        }
    }
}
