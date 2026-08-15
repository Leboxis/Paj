import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    @AppStorage("cardGridColumns") private var cardGridColumns: Int = 3

    @State private var driveName: String?
    @State private var usedSize: Int64?
    @State private var totalSize: Int64?
    @State private var cacheSize = "—"
    @State private var showEditConfig = false
    @State private var showReset = false

    var body: some View {
        NavigationStack {
            Form {
                if let driveName {
                    Section("Drive") {
                        LabeledContent("Nom", value: driveName)
                        if let used = usedSize, let total = totalSize {
                            LabeledContent("Occupation") {
                                Text("\(ByteCountFormatter.string(fromByteCount: used, countStyle: .file)) sur \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))")
                            }
                        }
                    }
                }

                Section {
                    Picker("Nombre de colonnes", selection: $cardGridColumns) {
                        Text("2").tag(2)
                        Text("3 (défaut)").tag(3)
                        Text("4").tag(4)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Affichage des cartes")
                } footer: {
                    Text("Définit le nombre de colonnes dans la vue grille (3 colonnes par défaut).")
                }

                Section {
                    Button {
                        appState.lock()
                    } label: {
                        Label("Verrouiller maintenant", systemImage: "lock")
                    }
                    Button {
                        showEditConfig = true
                    } label: {
                        Label("Modifier token / code / drive", systemImage: "key")
                    }
                } header: {
                    Text("Sécurité")
                } footer: {
                    Text("L'app se verrouille automatiquement à chaque passage en arrière-plan.")
                }

                Section("Stockage local") {
                    LabeledContent("Cache miniatures", value: cacheSize)
                    Button {
                        ThumbnailStore.shared.clearAll()
                        cacheSize = ThumbnailStore.shared.formattedSize()
                    } label: {
                        Label("Vider le cache", systemImage: "trash")
                    }
                }

                Section {
                    LabeledContent("Version", value: version)
                }

                Section {
                    Button("Réinitialiser la configuration", role: .destructive) {
                        showReset = true
                    }
                } footer: {
                    Text("Efface le token, l'ID du drive et le code du trousseau. L'app devra être reconfigurée.")
                }
            }
            .navigationTitle("Réglages")
            .task { await loadDriveInfo() }
            .onAppear { cacheSize = ThumbnailStore.shared.formattedSize() }
            .sheet(isPresented: $showEditConfig) {
                SetupView(existing: true)
                    .environmentObject(appState)
            }
            .alert("Réinitialiser la configuration ?", isPresented: $showReset) {
                Button("Réinitialiser", role: .destructive) {
                    AppConfig.reset()
                    appState.refreshConfig()
                }
                Button("Annuler", role: .cancel) {}
            }
        }
    }

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    private func loadDriveInfo() async {
        if let info = try? await KDriveClient.shared.driveInfo() {
            driveName = info.name
            usedSize = Int64(info.usedSize)
            totalSize = Int64(info.size)
        }
    }
}
