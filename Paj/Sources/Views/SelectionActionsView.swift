import SwiftUI

/// Barre d'actions du mode sélection (affichée en bas d'écran, barre
/// translucide système) : favori, déplacement, tags, renommage (1 élément),
/// suppression.
struct SelectionActionsView: View {
    @ObservedObject var selection: SelectionState
    var onFavorite: () -> Void
    var onMove: () -> Void
    var onTags: () -> Void
    var onRename: (() -> Void)?
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            action("Favori", "star", action: onFavorite)
            action("Déplacer", "folder", action: onMove)
            action("Tags", "tag", action: onTags)
            if selection.count == 1, let onRename {
                action("Renommer", "pencil", action: onRename)
            }
            action("Supprimer", "trash", role: .destructive, action: onDelete)
        }
        .disabled(selection.count == 0)
    }

    private func action(_ label: String, _ icon: String, role: ButtonRole? = nil, action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.body)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.borderless)
    }
}
