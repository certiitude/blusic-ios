# Recette iPhone — Blusic 1.1

## Statut de ce livrable

Projet natif généré sous Windows, puis **compilé avec Xcode 26.3 sur GitHub Actions**. Les **10 XCTest ont réussi sur iPhone Simulator** et une IPA physique arm64 non signée a été récupérée. Voir `COMPILATION-RESULTAT.md`. Les essais manuels ci-dessous restent nécessaires ; les tests unitaires ne prouvent pas le fonctionnement audio/UI complet sur iPhone.

## Compilation

- [ ] Xcode ouvre le projet et affiche les cibles Blusic et BlusicTests.
- [ ] Build du scheme Blusic pour iPhone Simulator avec Xcode 16+.
- [x] Build avec Xcode 26.3 réussi, incluant la compilation de la branche `glassEffect`. Rendu visuel à vérifier séparément.
- [x] 10 tests unitaires passent sur le simulateur iPhone via GitHub Actions.
- [ ] Signature par une Team Apple et installation sur iPhone physique.
- [ ] L’icône reprend le symbole blanc sur fond noir et l’écran de lancement n’émet pas de flash blanc.

## Première écoute hors ligne

- [ ] Au premier lancement, quatre originaux sont disponibles, sans compte ni réseau.
- [ ] Lecture de Bleu nuit : vrai son ; la progression avance et le bouton pause arrête l’audio.
- [ ] Recherche locale par titre et par artiste ; ouvrir Blusic Studio dans Artistes.
- [ ] Titre suivant/précédent ; changement de titre effectif, pas simplement un changement de texte.
- [ ] Déplacer la progression à 10 s puis à 30 s : le son change de position sans sauter au titre suivant.
- [ ] Fin du dernier titre en mode répétition désactivée : arrêt. Répétition un/tout et aléatoire fonctionnent.
- [ ] Changement de vitesse et de tonalité indépendants, testé à l’oreille.
- [ ] EQ actif/inactif et presets audibles ; réinitialiser à neutre.
- [ ] Boucle A à 5 s / B à 12 s : retour à A ; suppression de la boucle.

## Audio système, impérativement sur appareil

- [ ] Verrouiller l’écran pendant au moins 3 min et écouter ; aucun arrêt ni silence prolongé.
- [ ] Ouvrir une autre app ; l’audio natif continue.
- [ ] Métadonnées et pochette sur l’écran verrouillé ; tester pause/reprise/seek/suivant.
- [ ] Passer un appel ou déclencher Siri : interruption propre ; reprise uniquement si iOS l’autorise.
- [ ] Débrancher les écouteurs ou couper Bluetooth : pause sans diffusion intempestive.
- [ ] Reconnecter une sortie et reprendre la lecture.
- [ ] Envoyer vers une enceinte AirPlay ; changer de route en cours de lecture.
- [ ] Tester la minuterie et l’arrêt en fin de morceau, également en arrière-plan.

## Fichiers, playlists et persistance

- [ ] Import MP3, ALAC, FLAC et WAV personnels ; titre/artiste/durée/pochette extraits si présents.
- [ ] Fichier corrompu ou DRM : erreur explicite et aucune entrée faussement lisible.
- [ ] Écouter un fichier importé en mode avion et écran verrouillé.
- [ ] Créer, renommer, ajouter des morceaux, déplacer leur ordre et supprimer une playlist.
- [ ] Favoris : ajout/retrait, fermeture complète puis relance, données conservées.
- [ ] `examples/playlist.csv` : quatre morceaux associés aux originaux existants.
- [ ] Export CSV puis réimport ; titres/accents/ordre conservés.
- [ ] Import CSV d’une autre plateforme : sources manquantes signalées ; toucher un titre puis choisir un fichier pour l’associer.
- [ ] Import M3U HTTPS : attendre la mise en cache, lire ; erreur claire sur URL inaccessible.
- [ ] Export JSON puis import sur installation distincte : fusion sans effacement ; médias absents explicitement à réassocier.
- [ ] Supprimer un import : il disparaît des playlists, de la file et des favoris ; original externe conservé.

## Paroles et services

- [ ] Import `examples/paroles.lrc` sur un morceau : ligne courante change avec la musique.
- [ ] Toucher une ligne : déplacement effectif ; menu de décalage et défilement automatique testés.
- [ ] LRCLIB : morceau trouvé, instrumental, titre introuvable et réseau coupé.
- [ ] Recherche → Catalogue : trouver un titre via Invidious sans clé Google et charger les pages suivantes.
- [ ] Lire un titre Invidious dans le lecteur natif ; vérifier que la durée dépasse celle d’un extrait et que l’audio avance.
- [ ] Tester EQ, vitesse, tonalité et arrière-plan sur une piste Invidious.
- [ ] Changer d’instance, tester son API, simuler une instance HTTP 401/403 et vérifier les erreurs et le secours.
- [ ] Rejouer un titre : identifiant stable, favoris conservés, aucun stockage durable de son URL signée.
- [ ] Ouvrir le lecteur officiel via le menu : vérifier que le moteur natif est en pause et que les contrôles vidéo restent visibles.
- [ ] Vidéo refusée/intégration bloquée : bouton Ouvrir dans YouTube utilisable.
- [ ] Fermer le lecteur vidéo : l’audio de la vidéo s’arrête.
- [ ] Importer une playlist publique de plus de 50 titres : pagination complète.
- [ ] Instance inaccessible, API bloquée, playlist privée, absence de flux AAC : erreur lisible.

## Interface et statistiques

- [ ] iPhone SE, taille standard et Pro Max : ni contrôle hors écran ni chevauchement du mini-lecteur.
- [ ] Mode clair/sombre/système, six accents, arrondis et listes compactes.
- [ ] VoiceOver, grande taille de texte et Réduire les animations ; les réglages audio restent manipulables.
- [ ] Compteur à zéro sur une nouvelle installation ; 30 secondes réelles produisent une écoute.
- [ ] Une pause ne compte pas du temps ; les vidéos YouTube n’augmentent pas le temps natif.
- [ ] Statistiques jour/semaine/mois cohérentes ; classement fondé sur le temps réellement écouté.

## Limites connues

- Aucun résultat de ces tests d’appareil n’est revendiqué avant leur exécution.
- JSON : métadonnées uniquement, pas un conteneur de fichiers audio.
- Cache HTTPS : téléchargement préalable, pas un moteur de streaming HLS ni un téléchargement YouTube.
- Pas de synchronisation iCloud de la bibliothèque, OAuth Spotify/Apple Music, crossfade, widgets ou CarPlay.
- Le lecteur YouTube peut être refusé selon la vidéo et le contexte WebKit ; le lien officiel reste disponible.
