import SwiftUI
import LocalAuthentication

struct LockScreenView: View {
    @EnvironmentObject var appState: AppState

    @State private var code = ""
    @State private var failed = false
    @FocusState private var focused: Bool

    private var expectedLength: Int { max(AppConfig.accessCode.count, 1) }

    private var biometricsAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .padding(.bottom, 4)
            Text("Paj est verrouillé")
                .font(.title2.bold())
            SecureField("Code d'accès", text: $code)
                .keyboardType(.numberPad)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
                .focused($focused)
            if failed {
                Text("Code incorrect")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button("Déverrouiller", action: tryUnlock)
                .buttonStyle(.borderedProminent)
            if biometricsAvailable {
                Button {
                    biometricUnlock()
                } label: {
                    Label("Face ID / code iPhone", systemImage: "faceid")
                }
            }
            Spacer()
        }
        .padding()
        .onAppear { focused = true }
        .onChange(of: code) { _, newValue in
            if newValue.count >= expectedLength {
                tryUnlock()
            }
        }
    }

    private func tryUnlock() {
        let expected = AppConfig.accessCode
        if !expected.isEmpty && code == expected {
            code = ""
            failed = false
            appState.unlock()
        } else {
            code = ""
            failed = true
        }
    }

    private func biometricUnlock() {
        let context = LAContext()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Déverrouiller Paj") { success, _ in
            DispatchQueue.main.async {
                if success { appState.unlock() }
            }
        }
    }
}
