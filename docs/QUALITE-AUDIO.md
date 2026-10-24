# Qualité audio et variation de vitesse

## AAC 256 kbit/s et YouTube Music

L’aide officielle Google indique que la sélection de qualité élevée, jusqu’à **256 kbit/s AAC/Opus**, concerne **YouTube Music Premium** :

https://support.google.com/youtubemusic/answer/9076559?hl=fr

La présence du catalogue public YouTube Music dans une application ne donne pas automatiquement les droits ou URL de lecture Premium. Les formats réellement observés via l’instance Invidious testée sont des AAC autour de **130–134 kbit/s**. Le code choisit le meilleur format AAC/M4A annoncé et peut utiliser 256 kbit/s si un serveur autorisé le propose ; il ne l’annonce jamais sans l’avoir reçu.

## Autres pistes vérifiées

- **JioSaavn / saavn.sumit.co** : les requêtes d’évaluation ont répondu **HTTP 429** ; `saavn.dev` était inaccessible. Un débit et un catalogue utilisables n’ont donc pas été validés, et aucun de ces services n’est ajouté par défaut à Blusic.
- **Jamendo** : FLAC documenté sur le catalogue indépendant, usage API gratuit non commercial sous conditions. Ce n’est pas le catalogue complet des grands services commerciaux. https://developer.jamendo.com/v3.0/tracks
- **Apple Music / MusicKit** : catalogue commercial, mais abonnement utilisateur requis pour la lecture. https://developer.apple.com/musickit/
- **Deezer API publique** : métadonnées de playlists et extraits ; Blusic utilise uniquement les métadonnées pour les imports, jamais l’URL d’extrait comme si c’était le morceau complet.

Aucune API gratuite et fiable couvrant tout le catalogue commercial avec un minimum garanti d’AAC 256 kbit/s n’a été identifiée dans ces vérifications. Aucun compte Premium, identifiant partagé ou nouveau service payant n’est configuré automatiquement.

## Mode vitesse / tonalité liées

Relation exacte :

`vitesse = 2^(demi_tons / 12)`

`demi_tons = 12 × log2(vitesse)`

Exemples : +1 ≈ ×1,05946 ; +7 ≈ ×1,49831 ; +12 = ×2 ; −12 = ×0,5.

- Lecture progressive : `AVAudioTimePitchAlgorithm.varispeed`.
- Fichier préparé / local : `AVAudioUnitVarispeed`, avec l’unité d’étirement temporel contournée.
- Aucune nouvelle compression MP3/AAC n’est appliquée par ces réglages.
- Le signal est rééchantillonné : ce changement de vitesse n’est pas bit-perfect et ne restaure pas l’information déjà perdue dans la source AAC.
- Le mode indépendant emploie le traitement spectral/TimePitch et peut produire des changements de timbre, surtout aux réglages extrêmes.

La qualité et le débit affichés décrivent la source réellement reçue, pas une conversion destinée à afficher un chiffre plus élevé.
