import Foundation

/// État global : verrouillage au démarrage et à chaque passage en arrière-plan,
/// configuration détectée (token injecté à la build ou saisi dans l'app).
/// Sans code d'accès configuré, le verrouillage est désactivé (un écran qu'un
/// tap traverse ne protège rien et casse juste le retour dans l'app).
@MainActor
final class AppState: ObservableObject {
    @Published var isLocked = !AppConfig.accessCode.isEmpty
    @Published var isConfigured = AppConfig.isConfigured

    func lock() { isLocked = !AppConfig.accessCode.isEmpty }
    func unlock() { isLocked = false }

    func refreshConfig() { isConfigured = AppConfig.isConfigured }
}
