# Blusic

**Ta musique, simplement.** Application iPhone native en SwiftUI, pensée autour d’une interface sombre, de pochettes immersives et d’un lecteur en verre translucide. Identité adaptée de l’icône Blusic fournie ; ergonomie mobile inspirée des captures et d’Apple Music.

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

**L’IPA issue du workflow est non signée.** Elle doit encore être signée pour ton appareil, par exemple via Xcode sur Mac ou un outil de sideload compatible tel qu’AltStore Classic sous Windows. Ce dépôt ne contient ni certificat, ni profil Apple, ni compte de signature. Aucune IPA installable n’a été produite dans l’environnement Windows de création.

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
- Import paginé de **playlists YouTube publiques** avec une clé API ; aperçu avant confirmation. Les playlists privées, radios dynamiques et bibliothèques personnelles ne sont pas synchronisées.
- Export de playlists CSV et sauvegarde/fusion JSON des métadonnées, favoris, paroles et historique. Les fichiers audio sont à conserver séparément.
- Historique réel, temps d’écoute quotidien, classement par temps écouté, vues jour/7 jours/30 jours. Une session compte comme écoute après 30 secondes. Les vidéos YouTube ne gonflent pas les statistiques natives.
- Sauvegarde JSON atomique ; fichiers stockés dans le conteneur de l’app ; gestion/suppression des imports.

## YouTube : ce qui est effectivement intégré

YouTube Music ne propose pas d’API publique permettant à une app tierce d’offrir gratuitement son catalogue audio seul, sans publicité, avec téléchargement et lecture de fond. Blusic utilise donc :

1. **YouTube Data API v3** pour la recherche et les playlists publiques.
2. **Le lecteur vidéo officiel YouTube**, visible dans `WKWebView`, pour lire les résultats.
3. Un bouton **Ouvrir dans YouTube** si le propriétaire refuse l’intégration vidéo.

Dans **Réglages → YouTube**, enregistre ta propre clé API Google. Active **YouTube Data API v3** dans ton projet Google Cloud, puis applique les restrictions appropriées. La clé est conservée dans le **trousseau iOS**, jamais dans le code ou les exports. Les restrictions de clé doivent correspondre à ton Bundle Identifier ; les quotas et règles de Google s’appliquent.

Blusic n’ajoute **aucune publicité**. Celles du lecteur YouTube restent sous le contrôle de YouTube. La lecture YouTube **audio seule, sans pub, en arrière-plan, lossless, avec pitch/EQ ou en téléchargement n’est pas proposée**. L’écoute de fond, le hors-ligne et les effets concernent le moteur natif.

## Vérifications et tests

### Effectués sous Windows

```powershell
python -m pip install -r tools/requirements-qa.txt
python tools/check_project.py
```

Le script contrôle : syntaxe des fichiers Swift par arbre syntaxique, cohérence des références Xcode et phases de compilation, plists, scheme partagé, ressources des asset catalogs, icône opaque 1024 px, durée/format/niveau/non-saturation des quatre fichiers WAV.

**Ces contrôles ne compilent pas Swift et ne constituent pas un test iPhone.** La compilation Xcode, les XCTest, le rendu réel, le lecteur YouTube, AirPlay et le maintien audio écran verrouillé restent à vérifier sur l’environnement Apple. Voir [`docs/RECETTE-IPHONE.md`](docs/RECETTE-IPHONE.md).

### À lancer sur Mac

```bash
xcodebuild -list -project Blusic.xcodeproj
xcodebuild -project Blusic.xcodeproj -scheme Blusic \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Dans Xcode : **Product → Test** pour les 10 tests unitaires, dont les imports CSV multiligne, les limites YouTube, le parseur LRC, la sérialisation et le décodage des ressources audio. Le workflow GitHub choisit automatiquement un simulateur iPhone disponible et exécute ces tests.

## Organisation

```text
Blusic.xcodeproj/             Projet et scheme Xcode partagés
Blusic/
  BlusicApp.swift            Point d’entrée et injections
  Models.swift               Modèles Codable et parseur LRC
  LibraryStore.swift         Persistance, imports audio et historique
  AudioPlayer.swift          Moteur audio, cache et commandes système
  MusicServices.swift        YouTube, LRCLIB, CSV/M3U et trousseau
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
