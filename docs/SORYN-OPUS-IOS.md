# Soryn iPhone 1.12 — Opus original VBR

## Utilisation

Réglages → Qualité audio → Format préféré → **HQ · Opus natif VBR**.
Sans abonnement ni compte obligatoire. Le catalogue reste YouTube Music.
L’iPhone prépare l’audio lui-même ; le PC n’a pas besoin de rester allumé.

Le mode sélectionne le flux audio public YouTube **itag 251, WebM/Opus**.
Il copie ses paquets compressés dans un CAF que le moteur audio Apple décode
nativement, sans réencodage, sans encodeur Opus/FFmpeg distribué et sans vidéo.
Le débit affiché est la taille des paquets audio divisée par la durée utile,
et non le débit annoncé par le serveur ni le débit du fichier CAF avec ses en-têtes.

**160 kbit/s n’est pas garanti** : c’est du VBR. Deux fichiers complets obtenus
via SABR le 5 novembre 2026 donnent environ 115 kbit/s et 129 kbit/s audio moyen.
Ce n’est ni du lossless ni une offre de qualité Premium.

Si Opus est inaccessible ou refusé par le décodeur natif, la lecture essaie le
meilleur AAC disponible et l’indique par **« Secours AAC · Opus indisponible »**.
La préparation initiale peut prendre plusieurs secondes : le morceau complet
est vérifié avant de démarrer. Les titres privés, DRM ou indisponibles ne sont
pas rendus accessibles par ce mode.

## Hors ligne et compatibilité

- Cache Opus CAF et cache AAC séparés ; aucun ancien fichier AAC réinterprété comme Opus.
- Les téléchargements Opus sont séparés des téléchargements AAC existants.
- Un secours AAC après un échec Opus ne remplace pas un téléchargement déjà présent.
- Une suppression depuis la liste Téléchargements ne retire que la variante affichée.
- Bibliothèque, playlists, favoris, comptes facultatifs et imports personnels conservés.
- Identifiant `app.blusic.ios` et dossiers historiques inchangés. Mettre à jour avec
  la même signature Apple ; sauvegarder avant toute réinstallation, sans supprimer
  l’ancienne application pour une simple mise à jour.
- iOS 17 minimum, IPA non signée à signer avant installation.

## Validation

- Tests Node déterministes : sélection du format public, copie bit-identique de
  chaque paquet, durée et trim, TOC, fichiers corrompus, plages HTTP bornées et
  clusters WebM de taille inconnue.
- Vérification Apple `AVAudioFile` sur macOS et tests sur simulateur iPhone :
  décodage réel non silencieux, seek, transfert de fichier et coexistence hors
  ligne AAC/Opus. Les fixtures proviennent d’un instrumental original du projet,
  pas d’un morceau commercial embarqué.
- Test réseau natif distinct et strict : le secours AAC ne peut pas le faire
  réussir. Son résultat est consulté séparément de celui des tests déterministes.
- Aucun iPhone physique disponible ici : ne pas confondre le simulateur avec
  une validation sur l’appareil du créateur ou une disponibilité universelle des sources.
