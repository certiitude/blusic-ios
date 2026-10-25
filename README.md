# Blusic

**Ta musique, simplement.** Application iPhone native en SwiftUI, pensée autour d’une interface sombre, de pochettes immersives et d’un lecteur en verre translucide. Identité adaptée de l’icône Blusic fournie ; ergonomie mobile inspirée des captures et d’Apple Music.

**Nouvelle IPA compilée : 1.7.0 — optimisations mesurées, 63 tests passés sur 65.** [IPA, comparaison avant/après et limites réseau restantes](docs/PERFORMANCES-1.7.md). Deux tests de source audio restent en échec ; la compilation réussie n’est pas présentée comme une validation de tout le catalogue. Vérifie la version dans les réglages après installation.

## Version 1.7 — optimisation mesurée

- Observation SwiftUI par propriété : la vue témoin affichant seulement le titre passe de 6 à 0 recalculs sur 1,5 s de lecture, tandis que la progression continue de s’actualiser.
- Index de bibliothèque, ajout des grandes files en une mutation, sauvegarde hors du thread de l’interface, images adaptées à leur taille et mises en cache après décodage, longues listes paresseuses.
- Nouvelle vérification de l’erreur HTTP 500 signalée et test de lecture du titre Stephanie ; nouvel essai borné des erreurs serveur transitoires et des modes de métadonnées.
- [Mesures de référence, protocole et résultats après optimisation](docs/PERFORMANCES-1.7.md) : scénario de grande bibliothèque de 10 158,54 à 28,20 ms ; file de 2 500 titres de 1 058,98 à 3,68 ms. Lecture et déplacement sur Stephanie réussis, démarrage d’environ 2,5 s sur le simulateur.

## Version 1.6 — accès audio direct et paroles agrandies

- **Réglages → Sources audio** : automatique, YouTube direct ou relais Invidious. L’accès direct reprend nativement le contexte iOS validé avec youtubei.js, sans ajouter de serveur Node ni de bibliothèque JavaScript à l’app.
- En automatique, le relais peut démarrer après 350 ms ; la première source dont les octets M4A sont accessibles gagne. Une URL renvoyant HTTP 403 ne suffit plus à être sélectionnée. Les requêtes restantes sont annulées.
- Mise en tampon bloquée : autre accès après 4 s ; limite globale de démarrage ramenée de 35 à 20 s. Erreurs distinctes pour HTTP, page HTML, JSON invalide et champs incompatibles. Un format incomplet ne masque plus les formats AAC valides.
- **Paroles en grand**, sans défilement imbriqué du lecteur : pochette et titre compacts, texte 34 pt adaptable, ligne centrée, animation de taille/netteté et défilement à ressort. Le défilement manuel suspend le suivi ; « Recentrer » le reprend. Les effets de mouvement respectent le réglage d’accessibilité.
- Aucun serveur français fonctionnel n’a été validé. Le CDN direct est choisi par Google selon le réseau, sans garantie de localisation ni de latence.
- État des essais et de la compilation : [rapport 1.6](docs/RESULTAT-1.6.md).

## Version 1.5 — navigation système et imports automatiques

- La barre de navigation personnalisée est remplacée par **la vraie `TabView` d’iOS**. Sur iOS 26, le système dessine sa barre Liquid Glass et son **`tabViewBottomAccessory`** pour le mini-lecteur. Sur iOS antérieur, la barre d’onglets native standard est conservée. Aucun faux fond de barre en verre n’est dessiné par un HStack.
- **L’association CSV → YouTube Music démarre automatiquement** après lecture du fichier, avant l’ajout de la playlist. Même comportement pour les liens Deezer. Les collaborations séparées par point-virgule, les crédits « feat./avec » et les durées Spotify en millisecondes sont pris en compte ; les versions live/remix restent distinctes. Les absences ou ambiguïtés sont signalées.
- **Favoris** : un résultat de recherche est sauvegardé avant d’être ajouté aux favoris. L’état du cœur est reconnu par l’identité musicale persistante même si une nouvelle recherche crée un autre UUID temporaire.
- **Pochettes haute résolution** : demandes 1024 px sur les hôtes Google/YouTube reconnus, avec conservation du ratio des bannières et repli sur l’URL initiale si nécessaire. Les URL signées d’autres fournisseurs ne sont pas réécrites.
- Les paroles sont également testées **dans la vraie vue SwiftUI attachée à une fenêtre iPhone**, pour vérifier le déclenchement automatique et leur mise en cache, en plus du test API. Les anciens titres vidéo « Artiste - Titre » sont normalisés pour la recherche de paroles.
- `youtubei.js` n’est pas ajouté. Le catalogue continue d’utiliser le client public de métadonnées existant et Invidious pour l’audio.

## Version 1.4 — transitions et paroles automatiques

- **Réglages → Écoute → Fondu entre les titres** : activable/désactivable, durée de **0,5 à 8 secondes**. Le lecteur conserve le titre sortant pendant la préparation du suivant puis croise leurs gains, sans nouvel encodage audio. Deux lecteurs progressifs ou deux graphes natifs peuvent se chevaucher. La pause arrête les deux.
- La transition automatique prépare le titre suivant à l’approche de la fin. Le fondu réel est limité au temps restant du titre sortant ; un serveur indisponible peut empêcher un chevauchement sans coupure.
- Le préchargement prépare désormais un **lecteur silencieux mis en tampon**, pas uniquement une URL, afin de réduire le délai après un toucher.
- **Paroles** : recherche automatique à l’ouverture, repli sur recherche titre/artiste principal si l’album ou les crédits diffèrent. Un champ synchronisé vide ne masque plus des paroles non synchronisées disponibles.
- Les erreurs du fournisseur, les instrumentaux et l’absence de paroles restent explicitement affichés. Le test réseau vérifie la présence de lignes synchronisées pour un titre connu, sans recopier le texte dans les logs. Les captures de la vue paroles emploient un texte de démonstration original.

La suite inclut **43 tests** à exécuter sur iPhone Simulator : performances, durée bornée, vitesse/demi-tons, artistes, imports, fondu activé/désactivé, arrêt des deux lecteurs, enchaînement automatique et paroles.

## Version 1.3 — durée, vitesse liée, artistes et imports

- **Fin du morceau bornée par la durée du catalogue** : une estimation AAC/conteneur doublée ne prolonge plus la lecture par une queue silencieuse. Le segment natif et le lecteur progressif s’arrêtent à cette borne.
- **Vitesse et tonalité liées par défaut** : `vitesse = 2^(demi-tons/12)`. +12 donne ×2, −12 donne ×0,5. Le lecteur progressif et le moteur natif utilisent le varispeed, sans réencodage AAC ni étirement temporel dans ce mode. Le mode indépendant reste disponible.
- **Liquid Glass** rétabli sur les commandes d’en-tête, le mini-lecteur et les onglets, avec un fond et un espace séparés pour conserver l’absence de superpositions.
- **Recherche → Catalogue → Artistes** : profils YouTube Music, photo, description disponible, titres et suivi local dans Blusic. Les artistes suivis sont conservés dans la bibliothèque et les sauvegardes.
- **Import direct de playlists Deezer publiques**, sans utiliser les extraits de 30 secondes. **Spotify / Apple Music / autres : CSV**, puis bouton d’association à YouTube Music avec progression et annulation. Une correspondance douteuse, une reprise ou une version live différente n’est pas acceptée automatiquement.
- Les références restantes peuvent être associées au premier lancement ou choisies manuellement via « Trouver le titre sur YouTube Music ».

La recherche d’une source gratuite garantissant l’AAC 256 kbit/s n’a pas produit de fournisseur suffisamment vérifié pour l’ajouter : [détails et sources](docs/QUALITE-AUDIO.md). Le lecteur sélectionne toujours le meilleur AAC réellement annoncé, y compris 256 kbit/s si l’instance le fournit. Il ne transforme pas artificiellement un flux 128 kbit/s en « 256 ».

## Site vitrine Windows et iOS

Le dossier **[`website/`](website/README.md)** contient le site Blusic prêt pour Vercel : design Liquid Glass sombre, logo animé au démarrage, animations au défilement, aperçu Windows, illustration iPhone, démo audio et téléchargements Windows/IPA iOS. Dans Vercel : **Root Directory `website`**, **Framework Other**, aucune commande de build, sortie **`.`**.

## Version 1.2 — recherche musicale, chargement borné, interface compacte

- La recherche interroge maintenant **les chansons de YouTube Music** (`WEB_REMIX`, filtre chansons, résultats `MUSIC_VIDEO_TYPE_ATV`) : vrais titres, artistes, albums et pochettes. Les clips `OMV`, podcasts et résultats vidéo non identifiés comme chansons sont écartés. Aucun repli silencieux sur la recherche générale de vidéos.
- **Invidious résout l’audio** des identifiants retournés par YouTube Music. Il n’est plus la source de recherche du catalogue principal.
- **Lecture progressive AVPlayer** : le morceau commence sans attendre le fichier complet. Le relais est essayé avant l’accès direct ; un autre accès est essayé si la mise en tampon échoue. Les premières adresses audio sont anticipées pendant la consultation des résultats. Délais bornés, bouton Annuler et arrêt d’un démarrage qui dépasse **35 secondes**.
- Le lecteur affiche le **temps de démarrage mesuré**, dès que l’horloge audio avance. Cela ne constitue pas une garantie de démarrage instantané sur tous les réseaux.
- La vitesse et le volume fonctionnent pendant la lecture progressive. L’égaliseur et la tonalité indépendants passent par le moteur complet : le bouton **Préparer les effets audio** charge le fichier en parallèle, puis reprend la même position dans AVAudioEngine. Si la préparation échoue, la musique progressive continue. Une préparation est aussi demandée si des effets sont déjà activés.
- Toucher le bouton lecture pendant le chargement **annule** au lieu de recommencer indéfiniment la même requête.
- Un cache validé peut être rejoué directement : son index est réutilisé pendant 24 h (10 min pour les faibles débits). Après expiration, une résolution en ligne est à nouveau nécessaire. Les données audio restent dans le cache purgeable par iOS, pas dans une bibliothèque hors ligne permanente.
- Accueil recentré sur les captures initiales : **fond noir, Accès rapide, rangées de pochettes carrées et titres compacts**. Suppression du grand bandeau éditorial et des slogans. Le classement local n’apparaît que si l’historique réel le permet.
- Images dimensionnées dans un conteneur borné ; lecteur et onglets réservés dans une zone distincte du contenu défilant, pour éviter les débordements et superpositions.
- Captures natives grand iPhone et iPhone SE ajoutées au workflow. Elles utilisent les vrais écrans et le catalogue en réseau ; le mini-lecteur et le lecteur de prévisualisation utilisent une démo locale pour vérifier la mise en page.

YouTube Music est interrogé par son endpoint web public non officiel, sans connexion à un compte Google. Cela ne synchronise ni les achats ni la bibliothèque personnelle d’un compte et ne garantit pas la disponibilité de chaque titre. L’audio reste AAC compressé.

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

**La compilation distante de la version 1.1.0 a réussi** : [résultat et IPA récupérée](docs/COMPILATION-RESULTAT.md). Les **20 tests iPhone Simulator passent**, dont le test réseau réel de lecture native Invidious. L’IPA obtenue est non signée et doit encore être signée pour ton appareil, par exemple avec AltStore Classic sous Windows. Ce dépôt ne contient ni certificat, ni profil Apple, ni compte de signature.

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

1. **Le catalogue public YouTube Music** pour la recherche de chansons, puis **l’API Invidious** pour les playlists et la résolution des flux. Aucun compte ni clé API Google requis.
2. **Le moteur AVAudioEngine** pour les flux AAC/M4A. Les pistes ne stockent que leur identifiant vidéo et leur instance d’origine ; les URL signées temporaires sont résolues à la lecture.
3. Le relais média de l’instance en premier, un essai direct en secours et des instances de secours annonçant une API active si nécessaire, avec une échéance totale de chargement de 35 s.
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

**Ces contrôles statiques ne constituent pas un test iPhone.** En complément, la compilation **Xcode 26.3** et les **20 XCTest** ont réussi sur GitHub Actions, dont le test réseau Invidious : voir [le rapport](docs/COMPILATION-RESULTAT.md). Le rendu réel, le lecteur vidéo officiel, AirPlay et le maintien audio écran verrouillé restent à vérifier manuellement sur appareil. Voir [`docs/RECETTE-IPHONE.md`](docs/RECETTE-IPHONE.md).

### À lancer sur Mac

```bash
xcodebuild -list -project Blusic.xcodeproj
xcodebuild -project Blusic.xcodeproj -scheme Blusic \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

Dans Xcode : **Product → Test**. La suite contient désormais **25 tests**, dont les imports, la compatibilité des sauvegardes, la pagination Invidious, les erreurs HTTP, le filtrage des chansons YouTube Music, l’annulation et le dépassement du délai global. **Un test en réseau réel** cherche une chanson YouTube Music, démarre la lecture progressive à froid (sans fichier audio complet en cache), mesure le premier avancement avec un seuil de 12 s, vérifie l’audio complet et un signal PCM non silencieux, puis teste le passage au moteur d’effets, le seek et la pause sur simulateur. Ce test nécessite une instance fonctionnelle et ne se transforme pas en réussite quand le réseau échoue. Le temps réellement observé figure dans les logs ; ce seuil de test ne signifie pas une promesse de démarrage instantané sur un iPhone physique.

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
