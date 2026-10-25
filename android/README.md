# Blusic Android

Application native **Kotlin / Jetpack Compose**, Android **8.0 minimum (API 26)**, cible Android 15 (API 35). Lecteur **Media3 / ExoPlayer** dans un service média : lecture en arrière-plan, commandes de notification et écran verrouillé, focus audio, Bluetooth et arrêt quand la sortie se déconnecte.

## Première version

- Accueil sombre, pochettes, accès rapide, récents et démonstrations Blusic Studio.
- Recherche de **chansons YouTube Music**, pagination et recherche locale ; filtre ATV pour ne pas confondre chanson et clip vidéo.
- Bibliothèque persistante, favoris, playlists et import audio via le sélecteur de documents Android, sans permission globale de stockage.
- Lecteur, file d’attente, lecture aléatoire, répétition, déplacement, vitesse et tonalité liée (ou vitesse à hauteur constante).
- Paroles LRCLIB automatiques, cache, lignes synchronisées si disponibles, toucher pour se déplacer et recentrage après défilement manuel.
- Accès audio automatique, direct ou Invidious configurable ; validation du contenu et lecture HTTP par plages bornées de 256 Ko. Les refus du fournisseur restent affichés.
- Images redimensionnées par Coil, listes paresseuses, réseau et disque hors du thread UI ; seules les petites vues de progression suivent l’horloge.

Les démonstrations et pochettes originales sont réutilisées depuis les ressources du projet iOS par la configuration Gradle ; aucun média commercial n’est inclus. Les fonctions avancées iOS (EQ 10 bandes, fondu entre deux lecteurs, import CSV avec association) ne sont pas encore portées dans cette première version Android.

## Compilation

Ouvrir le dossier `android/` dans Android Studio avec **JDK 17**, SDK 35 et **Gradle 8.11.1**. Le workflow `.github/workflows/android.yml` installe les outils puis exécute :

```text
gradle :app:assembleDebug :app:testDebugUnitTest :app:lintDebug :app:assembleDebugAndroidTest
gradle :app:connectedDebugAndroidTest
```

APK : `app/build/outputs/apk/debug/app-debug.apk`. Il s’agit d’un APK de test signé avec la clé de débogage du runner, installable directement après autorisation Android d’installer depuis la source choisie. Ce n’est pas une version Play Store et une clé de distribution durable n’a pas été configurée. Les builds de runners différents peuvent demander la désinstallation de l’ancien APK si leur clé de test diffère ; conserver sa bibliothèque avant une désinstallation.

## Validation

Les tests unitaires couvrent les métadonnées musicales, l’exclusion des vidéos, les URLs, les plages HTTP, la persistance JSON et les paroles. Les tests sur émulateur Android lisent un vrai instrumental via le service, vérifient l’avancement et le déplacement à 30 s, la pause, les écrans et une restauration de favoris/playlist. Captures réelles extraites de l’émulateur.

La livraison finale GitHub Actions [`40234869261`](https://github.com/certiitude/blusic-ios/actions/runs/40234869261) réussit : **7 tests unitaires JVM et 5 tests sur émulateur Android 15**, dont lecture réelle en ligne de Stephanie et déplacement à 30 s. La signature du paquet est vérifiée par `apksigner` et cinq captures réelles sont récupérées et inspectées. Le diagnostic, le chemin de l’APK et les résultats exacts sont dans [le rapport commun](../docs/RELAIS-ET-ANDROID.md).

Un test de lecture ne prouve pas la disponibilité de tout le catalogue réseau. Les mêmes fournisseurs tiers peuvent refuser une lecture sur Android comme sur iOS ; le relais youtubei.js déployé reçoit encore des HTTP 403 de YouTube et n’est pas activé par défaut.
