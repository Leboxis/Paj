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

## Mise en route (GitHub Actions)

À chaque push sur `main` (ou **Actions → Build IPA → Run workflow**), la CI :

1. compile l'IPA Release non signée,
2. publie une **release GitHub** avec l'IPA (`releases/latest/download/Paj.ipa`),
3. met à jour **`apps.json`** à la racine — une source au format AltStore.

L'IPA publiée ne contient **aucun secret** : la configuration (token, ID du drive,
code) se fait au premier lancement dans l'app et reste dans le trousseau iOS.

## Installation & mises à jour dans LiveContainer

1. Dans LiveContainer : **Sources** (ou « App Sources ») → `+` → ajouter :
   `https://raw.githubusercontent.com/Leboxis/Paj/main/apps.json`
2. Installer **Paj** depuis la source (LiveContainer exécute l'IPA non signée
   telle quelle, pas de re-signature nécessaire).
3. Au premier lancement : saisir token + ID du drive + code d'accès
   (console.infomaniak.com → API). C'est mémorisé pour les mises à jour.
4. Mises à jour : LiveContainer proposera la nouvelle version à chaque push
   (la version s'auto-incrémente : `1.1.<numéro de run>`).

Alternative SideStore : télécharger l'IPA de la dernière release → ouvrir avec
SideStore (re-signature à l'installation).

## Développement local (macOS)

```bash
brew install xcodegen
xcodegen generate
open Paj.xcodeproj   # Run sur simulateur/appareil
```

## Sécurité

- `.env.local`, `Api infomaniak.json` et tout secret sont **exclus du repo** (`.gitignore`).
- Le repo est public mais **aucun secret n'est embarqué** dans les builds publiés :
  le token ne vit que dans le trousseau de l'app sur l'iPhone.
- L'URL de streaming est signée et expire au bout d'une heure.
