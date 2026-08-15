import Foundation

/// État global : verrouillage au démarrage et à chaque passage en arrière-plan,
/// configuration détectée (token injecté à la build ou saisi dans l'app).
@MainActor
final class AppState: ObservableObject {
    @Published var isLocked = true
    @Published var isConfigured = AppConfig.isConfigured

    func lock() { isLocked = true }
    func unlock() { isLocked = false }

    func refreshConfig() { isConfigured = AppConfig.isConfigured }
}
