# Vérifications réalisées

Environnement de création : Windows, Python 3.12. Pas de macOS, Xcode, SDK iOS ou iPhone accessibles dans cette session.

## Contrôles exécutés

`python tools/check_project.py` a terminé avec le statut **PASS** :

- Analyse syntaxique des **18 fichiers Swift**, incluant les tests ; sans vérification des types ni des API du SDK Apple.
- Analyse du fichier OpenStep `project.pbxproj`, résolution de ses références et présence de chaque source dans sa phase de compilation.
- Présence des ressources audio dans la phase de copie du bundle.
- Validation des deux plists XML et du scheme partagé.
- Validation des références des catalogues d’images et de l’icône RGB opaque 1024 × 1024.
- Décodage des en-têtes et du PCM des quatre WAV : **48 secondes, deux canaux, 44 100 Hz, 16 bits**.
- Crête maximale **27 851/32 767**, pas d’écrêtage détecté ; niveau RMS non nul pour chaque morceau.

Les contrôles ont notamment permis de corriger une référence de source Xcode et de simplifier les publishers de persistance. Une revue du moteur a également corrigé le remplacement des sources importées, la déduplication des files/playlists, l’arrêt d’un chargement en pause et la reprise après fin de morceau. Ces changements restent à confirmer à l’exécution native.

## Préparé mais non exécuté ici

- **10 XCTest** pour LRC, CSV, M3U, IDs YouTube, sauvegarde et décodage des fichiers embarqués.
- Workflow GitHub Actions pour les exécuter sur iPhone Simulator et compiler une IPA non signée pour appareil physique.
- Liste de tests manuels dans `RECETTE-IPHONE.md`.

## Non revendiqué

Aucun build Xcode réussi, aucune installation iPhone, aucune capture du rendu iOS, aucune vérification de lecture en arrière-plan, d’AirPlay, de lecteur YouTube ou de Liquid Glass natif n’est revendiquée avant une exécution sur l’environnement Apple.
