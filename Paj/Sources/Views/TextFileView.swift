import SwiftUI
import SafariServices

/// Visualiseur/éditeur de fichiers texte (.txt, .md, .log) :
/// - lecture par défaut, liens détectés et surlignés ;
/// - tap sur un lien → navigateur intégré (SFSafariViewController) ;
/// - mode édition (crayon) avec enregistrement d'une nouvelle version
///   côté kdrive (upload avec file_id).
struct TextFileView: View {
    let item: FileItem

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var originalText = ""
    @State private var loading = true
    @State private var editing = false
    @State private var dirty = false
    @State private var saving = false
    @State private var errorText: String?
    @State private var browserURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                } else if editing {
                    TextEditor(text: $text)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .onChange(of: text) { _, newValue in
                            dirty = newValue != originalText
                        }
                } else {
                    LinkTextView(text: text) { url in
                        browserURL = url
                    }
                    .padding(8)
                }
            }
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if editing {
                        Button("Annuler") {
                            text = originalText
                            dirty = false
                            editing = false
                        }
                    } else {
                        Button("Fermer") { dismiss() }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if editing {
                        Button {
                            Task { await save() }
                        } label: {
                            if saving {
                                ProgressView()
                            } else {
                                Text("Enregistrer").bold()
                            }
                        }
                        .disabled(!dirty || saving)
                    } else {
                        Button {
                            editing = true
                        } label: {
                            Label("Modifier", systemImage: "pencil")
                        }
                    }
                }
            }
            .sheet(isPresented: Binding(get: { browserURL != nil },
                                        set: { if !$0 { browserURL = nil } })) {
                if let url = browserURL {
                    InAppSafari(url: url)
                        .ignoresSafeArea()
                }
            }
            .alert("Erreur", isPresented: Binding(get: { errorText != nil },
                                                  set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
            .task { await load() }
        }
    }

    private func load() async {
        do {
            let data = try await KDriveClient.shared.downloadData(fileId: item.id)
            text = String(data: data, encoding: .utf8)
                ?? String(decoding: data, as: UTF8.self)
            originalText = text
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }

    private func save() async {
        saving = true
        do {
            try await KDriveClient.shared.saveFileContent(item, data: Data(text.utf8))
            originalText = text
            dirty = false
            editing = false
        } catch {
            errorText = error.localizedDescription
        }
        saving = false
    }
}

/// Texte en lecture seule avec détection de liens : le tap est intercepté
/// pour ouvrir le navigateur intégré au lieu de Safari externe.
struct LinkTextView: UIViewRepresentable {
    let text: String
    var onLinkTapped: (URL) -> Void

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.dataDetectorTypes = [.link]
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.textContainerInset = UIEdgeInsets(top: 4, left: 0, bottom: 24, right: 0)
        view.linkTextAttributes = [
            .foregroundColor: UIColor.systemBlue,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ]
        view.text = text
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text {
            view.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onLinkTapped: onLinkTapped)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        let onLinkTapped: (URL) -> Void

        init(onLinkTapped: @escaping (URL) -> Void) {
            self.onLinkTapped = onLinkTapped
        }

        func textView(_ textView: UITextView,
                      primaryActionFor textItem: UITextItem,
                      defaultAction: UIAction) -> UIAction? {
            if case .link(let url) = textItem.content {
                return UIAction { [weak self] _ in
                    self?.onLinkTapped(url)
                }
            }
            return defaultAction
        }
    }
}

/// Navigateur intégré à l'app (SFSafariViewController).
struct InAppSafari: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        config.entersReaderIfAvailable = false
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.preferredControlTintColor = UIColor.systemBlue
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
