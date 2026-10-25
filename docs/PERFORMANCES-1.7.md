# Blusic 1.7 — performances et erreur du relais audio

## Référence mesurée avant optimisation

Exécution : https://github.com/certiitude/blusic-ios/actions/runs/40208485629
Commit : `631b24dc9f25828eae1cf64ab11fbf423074c45a`.
Xcode Debug, iPhone 17 Pro Max / iOS 26.2 Simulator, runner macOS 15.

- Bibliothèque artificielle de **2 500 titres et 20 000 événements d’écoute** : cinq lectures de playlist et de récents prennent **10 158,54 ms**. La préparation d’une file de 2 500 titres prend **1 058,98 ms**.
- Vue SwiftUI réelle n’affichant que le titre : **6 réévaluations en 1,5 s** pendant que l’horloge avance. Vue de progression : 6 réévaluations également.
- Ce sont des coûts du scénario de test, pas des temps garantis sur l’iPhone de l’utilisateur ni une mesure de FPS de l’application entière.

## Modifications vérifiées

- Observation iOS 17 par propriété : l’horloge ne doit plus invalider l’accueil et toutes les lignes. Progression du lecteur dans un sous-composant séparé.
- Index par identifiant et source, caches de collections dérivées, ajout des files/playlists en lot.
- Sauvegardes JSON encodées et écrites par un acteur séparé, révisions monotones empêchant une ancienne sauvegarde d’écraser une plus récente ; protection et écriture atomique conservées.
- Images décodées/réduites hors du thread de l’interface, cache mémoire de vignettes et regroupement des requêtes identiques. Petites lignes : taille adaptée ; grande pochette : jusqu’à 1024 px. Arrière-plan flouté calculé sur une surface réduite.
- Conteneurs de défilement paresseux, pas de chargement de toutes les pochettes des longues listes au premier affichage.

## Cas audio signalé

Capture de l’utilisateur : HTTP 500 de `yt.chocolatemoo53.com`, mini-lecteur « Stéphanie ».

Depuis ce PC, recherche musicale et accès réel aux premiers octets : **Stephanie — Nafeesisboujee**, identifiant `RFzfXv9wzfo`, AAC 131 662 bit/s, HTTP 206, en-tête MP4 valide ; métadonnées + 4 096 octets en **0,187 s**. Le relais répondait de nouveau pendant ce diagnostic. Ambre répond aussi ; Damso reste HTTP 500 sur le relais. Cela montre une disponibilité variable, pas une résolution universelle du problème.

Le code essaie une fois de nouveau les erreurs serveur transitoires, puis teste séparément les métadonnées relayées et directes. Une erreur d’un mode n’empêche plus l’autre d’être essayé : test contrôlé HTTP 500 réussi. Les demandes de connexion/confirmation du fournisseur ne sont pas contournées.

**Test iOS réel du lecteur sur Stephanie réussi** : premier avancement en **2,5026 s**, durée **127 s**, AAC **132 kbit/s via Invidious**, déplacement à 30 s puis position observée **30,827 s**. Le test de Réseaux préchargé passe également, premier avancement **0,2523 s**. Ce sont des mesures sur le réseau du runner, pas sur le téléphone de l’utilisateur.

Le diagnostic complémentaire des octets confirme aussi pourquoi une réponse HTTP 200 ne suffit pas : pour Salé, le mode direct du relais a renvoyé une page `text/html` au lieu d’un M4A, tandis que l’accès Google depuis ce PC renvoie bien un MP4. Les adresses directes obtenues auprès de l’instance renvoient parfois HTTP 403 sur un autre réseau. Aucun de ces retours n’est présenté comme une lecture réussie.

## Résultats après optimisation

Exécution : https://github.com/certiitude/blusic-ios/actions/runs/40209946605
Commit de l’app testée : `69be0229cc01ba460bb5e32c671c10f01781a137`.
Même protocole et configuration iPhone Simulator que la référence :

| Mesure | Avant | Après |
| --- | ---: | ---: |
| 5 lectures playlist/récents, 2 500 titres et 20 000 écoutes | 10 158,54 ms | **28,20 ms** |
| Préparation d’une file de 2 500 titres | 1 058,98 ms | **3,68 ms** |
| Réévaluations de la vue titre en 1,5 s de lecture | 6 | **0** |
| Réévaluations de la vue progression sur le même intervalle | 6 | **6** |

Les opérations de bibliothèque testées sont environ 360 fois plus rapides, et la préparation de cette file environ 288 fois plus rapide. **Cela ne signifie pas que l’application entière ou les flux réseau sont 360 fois plus rapides**, et ce n’est pas une mesure de FPS sur appareil physique.

Cache d’image testé : source JPEG **2048 × 1024**, vignette décodée **128 × 64**, coût bitmap **32 768 octets**, **une seule requête** malgré les demandes concurrentes et la réutilisation. Les grandes pochettes gardent une demande jusqu’à 1024 px. Test des écritures : aucune écriture JSON sur le thread principal, ancien instantané rejeté au profit du plus récent. Tests des index après modification et de la conservation des identifiants de playlists/favoris lors d’une restauration : réussis.

## Build et bilan exact

- Compilation Release **iPhone arm64** et vérification du paquet : réussies.
- Version **1.7.0**, build **8**, iOS minimum **17.0**, bundle `app.blusic.ios`.
- IPA locale : `dist/github/40209946605/Blusic-unsigned.ipa`, **35 468 687 octets**, non signée.
- Suite : **63 tests passés, 2 tests échoués sur 65, 0 ignoré**. Le workflow global reste donc en échec, malgré la compilation réussie.
- Échecs maintenus visibles : Damso en mode direct (confirmation anti-robot exigée par YouTube sur le réseau GitHub), et Salé (refus direct et réponse non audio du relais). Les essais automatiques et la validation des données ne peuvent pas garantir la disponibilité d’un fournisseur tiers.
- Captures inspectées : accueil grand/compact, lecteur grand/compact, paroles grand/compact et deux positions de suivi, profil d’artiste. Les paroles de capture sont du texte original de démonstration ; le test LRCLIB distinct récupère automatiquement **46 lignes** dans la vraie vue SwiftUI.
- Les mesures et tests sur le téléphone physique de l’utilisateur restent à confirmer après installation de cette IPA.
