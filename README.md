# Maison

App iOS native (SwiftUI, Liquid Glass) pour piloter une installation [Home Assistant](https://www.home-assistant.io) : la puissance de Home Assistant, la simplicité de Maison d’Apple.

- **Local d’abord** — l’app parle directement au serveur Home Assistant du foyer ; l’accès à distance passe par Tailscale.
- **Les automatisations tournent sur le serveur**, pas sur l’iPhone.
- **Partage du foyer via iCloud** (CloudKit) pour les données propres à l’app.

> Projet personnel en cours. Rien n’est encore branché à Home Assistant : la structure de navigation et le modèle d’appareils sont en place.

## Démarrer

Le projet Xcode est généré depuis [`project.yml`](project.yml) avec [XcodeGen](https://github.com/yonaskolb/XcodeGen) et n’est pas versionné.

```sh
brew install xcodegen
xcodegen generate
open Maison.xcodeproj
```

Prérequis : Xcode 26 ou plus récent, cible iOS 26.

## Structure

```
Maison/
  App/            point d’entrée, navigation par onglets
  Features/       Maison, Pièces, Automatisations, Réglages
  Core/Devices/   types d’appareils Home Assistant → action rapide
  Resources/      catalogue d’assets
MaisonTests/      tests (Swift Testing)
ci/               options d’export et utilitaires pour GitHub Actions
```

## Intégration et livraison continues

| Workflow | Déclencheur | Ce qu’il fait |
| --- | --- | --- |
| [`CI`](.github/workflows/ci.yml) | push sur `main`, pull request | génère le projet, compile et lance les tests sur simulateur |
| [`TestFlight`](.github/workflows/release.yml) | tag `v*` ou lancement manuel | archive en Release et envoie la build sur TestFlight |

La version affichée vient du tag (`v0.2.0` → `0.2.0`), le numéro de build du compteur d’exécutions GitHub.

```sh
git tag v0.1.0 && git push origin v0.1.0
```

### Secrets requis pour TestFlight

Le plus simple : `./ci/setup-testflight.sh ~/Downloads/AuthKey_XXXX.p8 <issuer-id> <team-id>`, qui les enregistre via `gh`. Sinon, à ajouter dans *Settings → Secrets and variables → Actions* :

| Secret | Contenu |
| --- | --- |
| `APPLE_TEAM_ID` | identifiant d’équipe Apple Developer (10 caractères) |
| `ASC_KEY_ID` | Key ID de la clé API App Store Connect |
| `ASC_ISSUER_ID` | Issuer ID de la clé API |
| `ASC_KEY_P8` | contenu complet du fichier `AuthKey_XXXX.p8` |

La clé API se crée dans App Store Connect → *Utilisateurs et accès* → *Intégrations* → *App Store Connect API*, avec le rôle **App Manager** (nécessaire pour la signature automatique). L’app `me.theodaguier.maison` doit exister dans App Store Connect avant le premier envoi.
