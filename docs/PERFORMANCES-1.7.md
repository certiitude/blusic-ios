# Blusic 1.7 — performances et erreur du relais audio

## Référence mesurée avant optimisation

Exécution : https://github.com/certiitude/blusic-ios/actions/runs/40208485629
Commit : `631b24dc9f25828eae1cf64ab11fbf423074c45a`.
Xcode Debug, iPhone 17 Pro Max / iOS 26.2 Simulator, runner macOS 15.

- Bibliothèque artificielle de **2 500 titres et 20 000 événements d’écoute** : cinq lectures de playlist et de récents prennent **10 158,54 ms**. La préparation d’une file de 2 500 titres prend **1 058,98 ms**.
- Vue SwiftUI réelle n’affichant que le titre : **6 réévaluations en 1,5 s** pendant que l’horloge avance. Vue de progression : 6 réévaluations également.
- Ce sont des coûts du scénario de test, pas des temps garantis sur l’iPhone de l’utilisateur ni une mesure de FPS de l’application entière.

## Modifications à vérifier

- Observation iOS 17 par propriété : l’horloge ne doit plus invalider l’accueil et toutes les lignes. Progression du lecteur dans un sous-composant séparé.
- Index par identifiant et source, caches de collections dérivées, ajout des files/playlists en lot.
- Sauvegardes JSON encodées et écrites par un acteur séparé, révisions monotones empêchant une ancienne sauvegarde d’écraser une plus récente ; protection et écriture atomique conservées.
- Images décodées/réduites hors du thread de l’interface, cache mémoire de vignettes et regroupement des requêtes identiques. Petites lignes : taille adaptée ; grande pochette : jusqu’à 1024 px. Arrière-plan flouté calculé sur une surface réduite.
- Conteneurs de défilement paresseux, pas de chargement de toutes les pochettes des longues listes au premier affichage.

## Cas audio signalé

Capture de l’utilisateur : HTTP 500 de `yt.chocolatemoo53.com`, mini-lecteur « Stéphanie ».

Depuis ce PC, recherche musicale et accès réel aux premiers octets : **Stephanie — Nafeesisboujee**, identifiant `RFzfXv9wzfo`, AAC 131 662 bit/s, HTTP 206, en-tête MP4 valide ; métadonnées + 4 096 octets en **0,187 s**. Le relais répondait de nouveau pendant ce diagnostic. Ambre répond aussi ; Damso reste HTTP 500 sur le relais. Cela montre une disponibilité variable, pas une résolution universelle du problème.

Le code essaie une fois de nouveau les erreurs serveur transitoires, puis teste séparément les métadonnées relayées et directes. Une erreur d’un mode ne doit plus empêcher l’autre d’être essayé. Les demandes de connexion/confirmation du fournisseur ne sont pas contournées. Le test iOS de lecture et déplacement sur Stephanie reste nécessaire.

## Résultats après optimisation

À compléter avec la nouvelle compilation et ses mesures. Aucun gain chiffré annoncé avant leur exécution.
