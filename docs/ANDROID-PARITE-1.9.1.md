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

Résultats de compilation, tests, captures et chemin de l’APK : à compléter après exécution.
