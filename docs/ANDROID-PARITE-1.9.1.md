# Port Android 1.9.1 — parité fonctionnelle

Le port reprend les fonctions de l’app iPhone avec des interfaces Android natives (Compose / Media3), sans lecteur vidéo pour remplacer la lecture audio.

| Fonction | Implémentation Android |
|---|---|
| youtubei.js/SABR embarqué | Même bundle 18.3.0 que l’IPA ; WebView de protocole, pont HTTPS OkHttp, cookies invités propres au résolveur, fichier complet contrôlé par MediaExtractor, lecture Media3 |
| Accès préconfiguré | Jeton application Android distinct, non expirant ; clé maître du relais exclue de l’APK et des sauvegardes ; stockage Android Keystore |
| Haute qualité | Sélection du meilleur AAC réellement offert, paramètre transmis aux sources et caches distincts ; pas de 256 kbit/s inventé |
| Préchargement 45 secondes | Fichier complet, vitesse prise en compte, prochain index réel de Media3 en mode aléatoire, préparation réutilisée |
| Fondu | Deux lecteurs natifs, réglage 0,5–8 s, session média transférée au lecteur entrant, pause et focus audio communs |
| Son | Égaliseur numérique dix bandes 31 Hz–16 kHz avec marge de volume, vitesse 0,5–2×, tonalité ±12 demi-tons liée ou indépendante, volume |
| Paroles | LRCLIB avec contrôle des correspondances, texte/LRC importé, grandes lignes synchronisées, recentrage, décalage temporel et toucher pour chercher |
| File et lecture | Suivant, précédent, aléatoire, répétition, ajouter ensuite/en fin, déplacer/retirer/vider, restauration de file |
| Arrêt et répétition | Minuterie, arrêt à la fin du titre, boucle A–B |
| Catalogue | Chansons ATV YouTube Music, recherche d’artistes, profils et suivi persistant |
| Playlists et imports | Favoris, création/renommage/suppression, CSV à champs cités et séparateurs, JSON, M3U, playlists publiques YouTube et Deezer ; références associées avec contrôle titre/artiste/version, choix manuel si ambigu |
| Sauvegardes | Export/restauration JSON, import d’une sauvegarde iOS, métadonnées et paroles conservées ; fichiers audio à garder séparément |
| Statistiques | Temps d’écoute, aujourd’hui/7 jours, titres les plus écoutés et compteurs de bibliothèque |
| Apparence | Sombre/claire/système, accents, arrondi et animations des pochettes, listes compactes, retours haptiques |
| Performance | Index immuables de bibliothèque, images Coil redimensionnées, listes paresseuses, réseau/disque hors UI, horloge de progression isolée |
| Système Android | Service média, arrière-plan, écran verrouillé, notification, Bluetooth, focus audio et retrait des écouteurs |

Les formats importés restent soumis aux décodeurs Android/Media3 de l’appareil. Les fichiers personnels sont ouverts avec l’autorisation de document persistante ; leur suppression de la bibliothèque ne supprime pas les originaux. Les quatre instrumentaux inclus sont ceux de Blusic Studio.

## Vérifications

Les tests JVM portent sur la compatibilité des anciennes bibliothèques, les réglages, les imports, l’association de versions, le seuil de préparation, la sélection réelle des débits et la réponse du filtre dix bandes. Les scénarios émulateur ajoutent un véritable chevauchement des lecteurs natifs et sa pause, la persistance des nouveaux réglages, les écrans et un fichier de test passant par le pont JavaScript/natif. Le test du pont utilise une fixture originale : il ne prouve pas que YouTube accepte l’adresse IP du simulateur. Le scénario réseau Stephanie reste un test distinct, sans succès inventé ni test ignoré.

## Livraison vérifiée

- [GitHub Actions 40414033885](https://github.com/certiitude/blusic-ios/actions/runs/40414033885), commit `18fa7e1445727817ba20c372509ff8b26fc61977` : **succès global**. La révision précédente `40412260464` avait également réussi ; la dernière ajoute l’isolation du document JavaScript après annulation, les statistiques par jour et les sources HTTPS dans les M3U.
- **15 tests JVM et 8 tests sur émulateur Android 15 réussis**, 0 échec, 0 erreur, 0 ignoré. Compilation Kotlin/Compose, lint, signature cryptographique `apksigner` et inspection du paquet réussis.
- Scénarios natifs : lecture de l’instrumental avec avancement, déplacement à 30 s et pause ; préparation du suivant puis chevauchement de **deux lecteurs** et pause arrêtant les deux ; favoris/playlists et réglages persistants ; lecture réseau de **Stephanie** et déplacement à 30 s ; plages HTTP exactes et refus 403 visible ; annulation d’un travail JavaScript, redémarrage du document et préparation d’un fichier original validé par le pont natif.
- Le scénario du pont JavaScript est une **fixture**, pas un succès d’attestation YouTube. La lecture réseau de Stephanie est vérifiée séparément et ne prouve pas la disponibilité de tous les autres titres ou du chemin SABR depuis tous les réseaux. Les contrôles d’import, d’association et de filtre EQ sont des tests locaux, pas une validation exhaustive de chaque fournisseur distant.
- **APK 1.9.1, versionCode 13**, package `app.blusic.android`, Android **8.0 minimum (API 26)**, cible Android 15 (API 35).
- Fichier : `dist/github/android-40414033885/app-debug.apk`, **58 097 530 octets**.
- SHA-256 : `00aa4346b9636d301958eaddcdc304295b2ca99822be13c136c21cd01639c8f2`.
- Moteur youtubei.js/SABR, licences tierces et configuration Android non expirante présents dans l’APK. La clé maître du relais n’est pas embarquée. L’accès application inclus dans un paquet est récupérable ; le chiffrement de sa copie dans Keystore ne rend pas le paquet secret.
- APK signé avec la **clé de test du runner** ; installable directement, pas une publication Play Store. Une ancienne installation signée avec une autre clé peut refuser la mise à jour : conserver ses données avant toute désinstallation.
- Sept captures natives récupérées et inspectées à `dist/tests/android-40414033885/screenshots/` : accueil, recherche, lecteur, paroles, réglages, haute qualité et égaliseur/tonalité. Le contraste, les contrôles natifs et les nouveaux réglages sont visibles ; la capture paroles montre l’instrumental original sans paroles et ne constitue pas une preuve LRCLIB sur un titre commercial.
