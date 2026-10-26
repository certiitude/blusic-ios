# Blusic Android

Application native **Kotlin / Jetpack Compose**, Android **8.0 minimum (API 26)**, cible Android 15 (API 35). Lecteur **Media3 / ExoPlayer** dans un service média : lecture en arrière-plan, commandes de notification et écran verrouillé, focus audio, Bluetooth et arrêt quand la sortie se déconnecte.

## Version 1.9.1

- Accueil sombre, pochettes, accès rapide, récents et démonstrations Blusic Studio.
- Recherche de **chansons YouTube Music**, pagination et recherche locale ; filtre ATV pour ne pas confondre chanson et clip vidéo.
- Bibliothèque persistante, favoris, playlists et import audio via le sélecteur de documents Android, sans permission globale de stockage.
- Lecteur, file d’attente, lecture aléatoire, répétition, déplacement, vitesse et tonalité liée (ou vitesse à hauteur constante).
- Paroles LRCLIB automatiques, cache, lignes synchronisées si disponibles, toucher pour se déplacer et recentrage après défilement manuel.
- Accès audio automatique, direct ou Invidious configurable ; validation du contenu et lecture HTTP par plages bornées de 256 Ko. Les refus du fournisseur restent affichés.
- Images redimensionnées par Coil, listes paresseuses, réseau et disque hors du thread UI ; seules les petites vues de progression suivent l’horloge.

Les fonctions avancées ont été portées : youtubei.js/SABR sur l’appareil et relais préconfiguré, haute qualité, préparation complète à 45 s, fondu entre deux lecteurs, EQ dix bandes, tonalité indépendante, imports CSV/Deezer/YouTube avec association, sauvegardes JSON, profils/suivi d’artistes, statistiques, minuterie/boucle A–B et réglages d’apparence. Détails et vérifications dans [le rapport de parité](../docs/ANDROID-PARITE-1.9.1.md).

Les démonstrations et pochettes originales sont réutilisées depuis les ressources du projet iOS ; aucun média commercial n’est inclus. Le bundle JavaScript et ses licences sont générés par `native-resolver`, et l’accès application Android est injecté par `tools/configure_relay.py` en CI, sans clé d’administration ni clé maître du relais.

## Compilation

Ouvrir le dossier `android/` dans Android Studio avec **JDK 17**, SDK 35 et **Gradle 8.11.1**. Le workflow `.github/workflows/android.yml` installe les outils puis exécute :

```text
gradle :app:assembleDebug :app:testDebugUnitTest :app:lintDebug :app:assembleDebugAndroidTest
gradle :app:connectedDebugAndroidTest
```

APK : `app/build/outputs/apk/debug/app-debug.apk`. Il s’agit d’un APK de test signé avec la clé de débogage du runner, installable directement après autorisation Android d’installer depuis la source choisie. Ce n’est pas une version Play Store et une clé de distribution durable n’a pas été configurée. Les builds de runners différents peuvent demander la désinstallation de l’ancien APK si leur clé de test diffère ; conserver sa bibliothèque avant une désinstallation.

## Validation

Version actuelle **1.9.1** : [exécution `40414033885`](https://github.com/certiitude/blusic-ios/actions/runs/40414033885), **succès global**, **15 tests JVM + 8 tests sur émulateur Android 15**, aucun échec/ignoré. Le fondu avec deux lecteurs, la pause, les nouvelles préférences, l’annulation/reprise du pont et la lecture réseau de Stephanie sont couverts. APK récupéré et vérifié à `dist/github/android-40414033885/app-debug.apk` (58 097 530 octets) ; sept captures inspectées. [Rapport détaillé](../docs/ANDROID-PARITE-1.9.1.md).

Les tests unitaires couvrent les métadonnées musicales, l’exclusion des vidéos, les URLs, les plages HTTP, la persistance JSON et les paroles. Les tests sur émulateur Android lisent un vrai instrumental via le service, vérifient l’avancement et le déplacement à 30 s, la pause, les écrans et une restauration de favoris/playlist. Captures réelles extraites de l’émulateur.

La première livraison **1.0.0**, GitHub Actions [`40234869261`](https://github.com/certiitude/blusic-ios/actions/runs/40234869261), avait **7 tests unitaires JVM et 5 tests sur émulateur Android 15** réussis. Cet historique et ses limites sont conservés dans [le rapport commun](../docs/RELAIS-ET-ANDROID.md).

Un test de lecture ne prouve pas la disponibilité de tout le catalogue réseau. Les mêmes fournisseurs tiers peuvent refuser une lecture sur Android comme sur iOS ; le moteur local est essayé avant les accès de secours. Le relais préconfiguré reste soumis aux refus réseau YouTube et aux limites Render Free.
