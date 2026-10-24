# Blusic

**Ta musique, simplement.** Application iPhone native en SwiftUI, pensée autour d’une interface sombre, de pochettes immersives et d’un lecteur en verre translucide. Identité adaptée de l’icône Blusic fournie ; ergonomie mobile inspirée des captures et d’Apple Music.

## Version 1.1 — Invidious

- **Recherche → Catalogue** : recherche du catalogue YouTube public, sans clé Google.
- **Lecture audio native** : résolution des adresses temporaires, meilleur flux AAC/M4A compatible, téléchargement en cache puis lecture avec arrière-plan, EQ, vitesse et tonalité.
- Import des playlists publiques YouTube/YouTube Music via Invidious, avec pagination.
- **Réglages → Invidious** : adresse du serveur, test de connexion, secours automatiques et réinitialisation. Instance initiale : `https://yt.chocolatemoo53.com`.
- Migration des titres YouTube sauvegardés dans la version 1.0 en conservant leurs identifiants, favoris et playlists.
- Menu d’un titre → **Ouvrir le lecteur officiel** en secours explicite si le flux est inaccessible.

Le catalogue dépend des contenus YouTube publics et des instances communautaires. **Ce n’est ni du lossless ni une garantie de disposer de tous les titres des autres plateformes.** La qualité réellement fournie est affichée. L’instance peut bloquer l’API ou les flux ; dans ce cas Blusic signale l’erreur et permet de choisir un autre serveur.

## Ouvrir le projet

Ouvre **`Blusic.xcodeproj`** dans **Xcode 16 ou plus récent sur un Mac**. Aucun paquet Swift, serveur, CocoaPods ou XcodeGen à installer. Les quatre morceaux originaux et les pochettes sont déjà dans le projet.

- **iOS minimum : 17.0**, iPhone en portrait.
- **Liquid Glass Apple natif : iOS 26 + compilation avec Xcode 26**. Matériaux translucides SwiftUI sur iOS 17–18 ou avec un SDK antérieur.
- Langue de l’interface : français. Modes sombre, clair et système.

### Installer sur ton iPhone avec Xcode

1. Copie ce dossier sur un Mac et ouvre `Blusic.xcodeproj`.
2. Dans **Xcode → Settings → Accounts**, ajoute ton compte Apple.
3. Sélectionne la cible **Blusic → Signing & Capabilities**, choisis ta **Team** et un **Bundle Identifier** unique, par exemple `fr.tonnom.blusic`.
4. Connecte ton iPhone, sélectionne-le comme destination. Active son **Mode développeur** si iOS le demande.
5. Clique sur **Run ▶**. L’app est compilée, signée et installée par Xcode.

Un compte Apple personnel permet le test sur ton appareil ; la durée de validité de sa signature gratuite est limitée. TestFlight/App Store nécessitent une distribution via Apple Developer.

### Depuis Windows, sans Mac personnel

Voir **[le guide Windows détaillé](docs/COMPILER-DEPUIS-WINDOWS.md)**. Le workflow **`.github/workflows/ios.yml`** utilise un runner macOS avec **Xcode 26.3** pour compiler une vraie IPA **iPhone arm64**, vérifier son binaire, puis lancer les tests iPhone Simulator.

Après la connexion et l’envoi du projet dans ton dépôt GitHub privé :

```powershell
python tools/github_ipa.py build --repo TON-COMPTE/blusic-ios
```

L’utilitaire suit la compilation et télécharge **`dist/github/<execution>/Blusic-unsigned.ipa`**. Avec le dépôt Git configuré, **`Compiler IPA.cmd`** lance cette procédure par double-clic.

**Une compilation distante a réussi** : [résultat et IPA récupérée](docs/COMPILATION-RESULTAT.md). Les **10 tests iPhone Simulator passent**. L’IPA obtenue est non signée et doit encore être signée pour ton appareil, par exemple avec AltStore Classic sous Windows. Ce dépôt ne contient ni certificat, ni profil Apple, ni compte de signature.

**Catalogue :** Invidious est intégré dans la version 1.1, mais n’offre pas une couverture universelle de toutes les plateformes. Voir [la recherche d’API et leurs limites](docs/API-MUSICALES.md).

## Fonctions implémentées

### Interface et personnalisation

- Accueil éditorial, accès rapide aux favoris/récents, pochettes et sélection de morceaux.
- Navigation flottante et mini-lecteur avec progression.
- Lecteur grand format avec fond de pochette diffus, file d’attente et vue paroles.
- Bibliothèque, artistes, playlists et collections intelligentes favoris/récents/ajouts récents/hors ligne.
- Six couleurs d’accent, trois apparences, arrondi des pochettes, listes compactes, haptiques, animation des pochettes.
- Respect du réglage système Réduire les animations pour les animations importantes du lecteur ; libellés VoiceOver sur les commandes.

### Audio natif

- Moteur **AVAudioEngine** : `AVAudioPlayerNode → AVAudioUnitTimePitch → AVAudioUnitEQ → mixer`.
- Lecture de fichiers copiés depuis **Fichiers**, avec titre/artiste/album/pochette extraits quand présents.
- WAV, AIFF, FLAC, ALAC/M4A, AAC et MP3 **sans DRM**, selon les décodeurs iOS. Le décodeur est vérifié à l’import.
- Quatre instrumentaux **originaux Blusic Studio**, embarqués, 48 secondes chacun, stéréo PCM 16 bits / 44,1 kHz. Ce ne sont pas les titres commerciaux visibles sur les captures.
- Lecture en arrière-plan avec `AVAudioSession.playback` et `UIBackgroundModes.audio`.
- Commandes de l’écran verrouillé : lecture/pause, suivant/précédent, position et pochette.
- Arrêt au débranchement d’une sortie audio ; interruptions système et reprise autorisée par iOS.
- AirPlay, volume du lecteur, vitesse **0,5× à 2×**, tonalité indépendante **−12 à +12 demi-tons**.
- Égaliseur 10 bandes **−12 à +12 dB**, cinq préréglages et réglage personnalisé, marge de niveau anti-saturation.
- File réordonnable/supprimable, écoute suivante, aléatoire sans répétition avant épuisement de la sélection, répétition titre/tout.
- Boucle A–B, minuterie 15/30/45/60 minutes ou arrêt en fin de titre.
- Sources audio HTTPS provenant des playlists : téléchargement en cache avant lecture, jusqu’à 300 Mo par fichier. Pas de promesse de streaming instantané/HLS.

**Lossless :** les fichiers réellement sans perte sont décodés sans réencodage avec pertes. YouTube n’est pas une source lossless. Le traitement audio, la vitesse, le mixage iOS, le matériel et la liaison Bluetooth peuvent convertir le signal. L’app n’annonce pas de sortie bit-perfect ni de « Hi-Res » inventé.

### Paroles

- Import **LRC** horodaté et **TXT** ; horodatages multiples, fractions de seconde et `[offset:…]`.
- Recherche explicite dans **LRCLIB** avec titre/artiste/album/durée ; aucun texte inventé si le service ne trouve pas le titre.
- Ligne courante mise en valeur, défilement automatique désactivable, toucher pour se positionner, décalage réglable.
- Cache des paroles dans la bibliothèque. Les quatre démos sont instrumentales.

### Bibliothèque, imports et statistiques

- Création, renommage, suppression et réorganisation des playlists ; ajout via le menu des morceaux ou sélection dans une playlist.
- Tri par titre, artiste et date ; recherche locale et recherche à l’intérieur d’une collection.
- Import **CSV** Soundiiz/TuneMyMusic ou générique : virgule, point-virgule, tabulation, champs entre guillemets, accents et retours à la ligne.
- Import **M3U/M3U8** avec métadonnées `EXTINF` et URL HTTPS. Les chemins de fichiers externes sont traités comme des références à associer.
- Les listes Spotify/Apple Music/Deezer sont transférables **via leur export CSV** : pas de connexion OAuth directe à ces comptes dans cette version.
- Association automatique aux fichiers déjà en bibliothèque quand titre et artiste concordent ; sinon association manuelle à un fichier audio au toucher du morceau.
- Import paginé de **playlists YouTube publiques via Invidious sans clé API** ; aperçu avant confirmation. Les playlists privées, radios dynamiques et bibliothèques personnelles ne sont pas synchronisées.
- Export de playlists CSV et sauvegarde/fusion JSON des métadonnées, favoris, paroles et historique. Les fichiers audio sont à conserver séparément.
- Historique réel, temps d’écoute quotidien, classement par temps écouté, vues jour/7 jours/30 jours. Une session compte comme écoute après 30 secondes. Les vidéos YouTube ne gonflent pas les statistiques natives.
- Sauvegarde JSON atomique ; fichiers stockés dans le conteneur de l’app ; gestion/suppression des imports.

## Invidious et YouTube : ce qui est effectivement intégré

Invidious est un service communautaire non officiel qui interroge les contenus publics YouTube. Blusic utilise :

1. **L’API Invidious** pour la recherche, les playlists et la résolution des flux. Aucun compte ni clé API Google requis.
2. **Le moteur AVAudioEngine** pour les flux AAC/M4A. Les pistes ne stockent que leur identifiant vidéo et leur instance d’origine ; les URL signées temporaires sont résolues à la lecture.
3. Un essai du relais média de la même instance après un échec d’accès direct, puis jusqu’à deux instances de secours annonçant une API active dans l’annuaire du projet, si le secours est activé.
4. **Le lecteur vidéo officiel YouTube** en secours sur demande depuis le menu d’un titre. Il est visible et conserve les publicités éventuelles de YouTube.

Dans **Réglages → Invidious**, indique une autre adresse HTTPS si nécessaire. Le bouton de test vérifie l’API de l’adresse saisie sans masquer son erreur derrière un serveur de secours. L’instance reçoit les recherches et les identifiants vidéo ; les flux directs peuvent contacter Google. Les détails sont expliqués dans l’écran de confidentialité.

Blusic n’ajoute **aucune publicité**. Les flux Invidious passent par le moteur natif et ses effets. **Pas de promesse de lossless** : les formats YouTube sont compressés, même s’ils étaient convertis ensuite en PCM. Le format Opus/WebM n’est pas sélectionné pour assurer la compatibilité avec le moteur iOS 17 ; le meilleur AAC/M4A annoncé est choisi. Le cache est un fichier audio temporaire et non un album distribué avec l’application. Les erreurs de flux vides, tronqués, JSON ou HTML sont signalées.

## Vérifications et tests

### Effectués sous Windows

```powershell
python -m pip install -r tools/requirements-qa.txt
python tools/check_project.py
```

Le script contrôle : syntaxe des fichiers Swift par arbre syntaxique, cohérence des références Xcode et phases de compilation, plists, scheme partagé, ressources des asset catalogs, icône opaque 1024 px, durée/format/niveau/non-saturation des quatre fichiers WAV.

**Ces contrôles statiques ne constituent pas un test iPhone.** En complément, la compilation **Xcode 26.3** et les **10 XCTest** ont réussi sur GitHub Actions : voir [le rapport](docs/COMPILATION-RESULTAT.md). Le rendu réel, le lecteur YouTube, AirPlay et le maintien audio écran verrouillé restent à vérifier manuellement sur appareil. Voir [`docs/RECETTE-IPHONE.md`](docs/RECETTE-IPHONE.md).

### À lancer sur Mac

```bash
xcodebuild -list -project Blusic.xcodeproj
xcodebuild -project Blusic.xcodeproj -scheme Blusic \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Dans Xcode : **Product → Test**. La suite contient désormais **20 tests**, dont les imports, la compatibilité des sauvegardes, la pagination Invidious, les erreurs HTTP et l’annulation. **Un test en réseau réel** cherche un titre, récupère son AAC, vérifie une durée de morceau complet et un signal PCM non silencieux, démarre le moteur natif puis vérifie l’avancement, le seek et la pause sur simulateur. Ce test nécessite une instance fonctionnelle et ne se transforme pas en réussite quand le réseau échoue.

Contrôle léger depuis Windows, sans télécharger un morceau complet : `python tools/probe_invidious.py`. Il vérifie la recherche, les métadonnées et 8 Ko du flux direct/relayé ; ce n’est pas un test d’écoute iPhone.

## Organisation

```text
Blusic.xcodeproj/             Projet et scheme Xcode partagés
Blusic/
  BlusicApp.swift            Point d’entrée et injections
  Models.swift               Modèles Codable et parseur LRC
  LibraryStore.swift         Persistance, imports audio et historique
  AudioPlayer.swift          Moteur audio, cache et commandes système
  MusicServices.swift        YouTube, LRCLIB, CSV/M3U et trousseau
  InvidiousService.swift      Catalogue, playlists, flux et instances de secours
  DesignSystem.swift         Verre, icône vectorielle et composants
  *View.swift                Écrans SwiftUI
  Assets.xcassets/            Icône et pochettes originales
  Audio/                     Quatre WAV originaux embarqués
BlusicTests/                 XCTest
examples/                    CSV et LRC de test
tools/                       Génération reproductible et contrôles
docs/                        Recette iPhone et notes techniques
.github/workflows/ios.yml    Compilation/tests sur macOS et IPA non signée
```

Pour régénérer les médias originaux : `python tools/generate_assets.py` (Pillow + NumPy). Aucune dépendance Python n’est nécessaire pour compiler l’application iOS.

## Suite de développement

Pour une version distribuée à grande échelle : valider sur iPhone, mettre en place une identité de signature Apple et la distribution TestFlight, tester les contenus YouTube réellement utilisés et les obligations liées aux services externes. Les fonctionnalités non implémentées comprennent la synchronisation multiappareil, les comptes musicaux OAuth, le fondu enchaîné entre deux titres, CarPlay et les widgets.
