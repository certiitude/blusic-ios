# Vérifications réalisées

Environnement local : Windows, Python 3.12. Un runner macOS GitHub Actions a ensuite été connecté avec l’autorisation du créateur.

## Compilation et XCTest réellement exécutés

L’exécution https://github.com/certiitude/blusic-ios/actions/runs/39665142579 a terminé en **success** avec **Xcode 26.3** : compilation Release iPhone arm64 réussie, packaging vérifié, puis **10 XCTest exécutés avec 0 échec** sur iPhone Simulator. L’IPA non signée de 35 048 694 octets est récupérée sur le PC. Rapport détaillé dans `COMPILATION-RESULTAT.md`.

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

## Tests manuels restant à effectuer

- Écoute, ergonomie, rendu Liquid Glass, AirPlay, vidéo YouTube et arrière-plan sur iPhone physique : liste dans `RECETTE-IPHONE.md`.

## Non revendiqué

Aucune installation sur iPhone physique, capture du rendu iOS ou vérification manuelle de lecture en arrière-plan, d’AirPlay, de lecteur YouTube ou de rendu Liquid Glass n’est revendiquée. Le passage des tests unitaires ne valide pas l’accès à un catalogue musical universel.
