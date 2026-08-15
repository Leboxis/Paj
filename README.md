# Paj — client kdrive personnel pour iPhone

App native **SwiftUI** connectée à un drive **kdrive Infomaniak** via l'API officielle.
Compilation en IPA via **GitHub Actions**, installation par **SideStore** (re-signature sur l'appareil,
aucun compte développeur payant requis).

## Fonctionnalités

- Barre d'onglets translucide façon app Fichiers : **Récents, Parcourir, Médias, Favoris, Réglages**
- Liste **et** grille (bascule en toolbar), tri côté serveur (nom, date, taille, type)
- Grille médias 3 colonnes façon Photos, miniatures mises en cache (mémoire + disque ~250 Mo)
- Visionneuse plein écran : photos haute résolution avec zoom pincement/double-tap,
  vidéos en **streaming** via URL temporaire signée (AVPlayer)
- Pagination par curseur + préchargement en fin de défilement (défilement 120 Hz natif)
- Actions : favoris, renommer, supprimer (corbeille), ouverture via URL temporaire
- Écran de verrouillage par code + Face ID, verrouillage auto en arrière-plan

## Structure

```
project.yml                    # Spec XcodeGen (génère Paj.xcodeproj — non versionné)
.github/workflows/build-ipa.yml # CI : IPA Release non signée en artifact
Paj/Sources/App/               # Point d'entrée, état global
Paj/Sources/Core/              # Config/trousseau, modèles, client API, cache miniatures
Paj/Sources/Models/            # Liste paginée partagée
Paj/Sources/Views/             # Onglets, liste/grille, visionneuse, réglages
Paj/Resources/                 # Info.plist, icône
```

## Mise en route (GitHub Actions → SideStore)

1. Créer un **repo GitHub privé** et pousser ce dossier.
2. Dans **Settings → Secrets and variables → Actions**, ajouter :
   - `KDRIVE_API_TOKEN` — le token API Infomaniak (console.infomaniak.com)
   - `KDRIVE_ID` — l'ID du drive (ex. `871043`)
   - `APP_ACCESS_CODE` — le code de verrouillage de l'app
3. Onglet **Actions → Build IPA → Run workflow** (ou push sur `main`). ~5-10 min.
4. Sur l'iPhone : ouvrir la run dans Safari → **télécharger l'artifact `Paj-ipa`**
   → partager → **ouvrir avec SideStore** → installer. SideStore re-signe l'IPA à l'installation.

Sans secrets configurés, l'IPA se construit quand même : la configuration (token, ID, code)
se fait alors directement dans l'app au premier lancement et reste dans le trousseau iOS.

## Développement local (macOS)

```bash
brew install xcodegen
xcodegen generate
open Paj.xcodeproj   # Run sur simulateur/appareil
```

## Sécurité

- `.env.local`, `Api infomaniak.json` et tout secret sont **exclus du repo** (`.gitignore`).
- Le token vit soit dans l'IPA (secret CI injecté dans l'Info.plist), soit dans le trousseau
  de l'app — jamais dans le code source.
- L'URL de streaming est signée et expire au bout d'une heure.
