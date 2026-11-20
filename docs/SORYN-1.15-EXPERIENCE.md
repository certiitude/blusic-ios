# Soryn 1.15 — une écoute plus personnelle

Version de travail : **1.15.0 (22)**. Ce document décrit l’implémentation,
pas une IPA publiée ni une validation sur iPhone physique.

## Direction

Moins de panneaux techniques, plus de musique. Fonds encre, surfaces teintées,
titres hiérarchisés, pochettes plus présentes et navigation système conservée.
La couleur d’accent et les apparences sombre/clair/système restent disponibles.
Pas d’abonnement, de compte imposé, de mode DJ ou de nouveau serveur.

### Accueil

- Reprise du morceau courant ou d’une écoute/favori, sans recommencer un morceau
  déjà en lecture. Les titres inaccessibles sont écartés de la reprise hors ligne.
- Accès direct aux favoris et téléchargements ; radio toujours accessible.
- Favoris, historique et classement selon le temps réellement écouté.
- Découverte par couleur musicale choisie. L’ancienne recherche fixe
  « rap français » n’est plus présentée comme une tendance ou un classement.
- En mode hors ligne, pas de recherche catalogue : place aux titres disponibles.
- La consultation de l’accueil ou des résultats ne résout plus automatiquement
  d’adresses audio. Le préchargement du prochain morceau du lecteur est conservé.

### Recherche

- Attente de frappe 350 ms, contre 650 ms précédemment. Cela ne promet pas une
  latence réseau divisée par deux : le fournisseur reste extérieur à l’app.
- Cache **mémoire** de 12 premières pages de métadonnées, durée 5 minutes ;
  catégorie titres/artistes séparée, actualisation explicite possible.
- Identité de requête pour les résultats, erreurs, chargements et pages suivantes.
  Une réponse tardive ne remplace jamais la nouvelle recherche.
- Pagination dédupliquée ; une erreur de page conserve les titres déjà trouvés et
  propose un nouvel essai. Un jeton répété ne crée pas une boucle sans fin.
- Huit recherches récentes maximum, enregistrées seulement lors d’une action
  explicite (validation, choix d’un résultat ou d’une suggestion), jamais à chaque
  frappe. Stockage local distinct de la bibliothèque et de la synchronisation.
  Suppression individuelle et effacement complet avec confirmation.
- En mode hors ligne, recherche uniquement parmi fichiers et téléchargements.

### Bibliothèque et lecteur

- Recherche par titre, artiste et album ; tous les mots sont pris en compte,
  sans distinction de casse ni d’accents. Tris titre/artiste/date et filtre favoris.
- Filtrage des playlists et artistes ; suppression d’une playlist confirmée,
  sans supprimer ses fichiers ni les titres de la bibliothèque.
- Indicateur de lecture reconnu même si un résultat représente le même titre
  avec un UUID temporaire différent. Disponibilité hors ligne affichée correctement.
- Mini-lecteur avec progression isolée : seul le petit indicateur observe l’horloge.
- **File d’attente plein écran** : morceau courant, titres à suivre réordonnables,
  titres précédents de la file. En aléatoire, seuls les titres réellement visités
  dans le cycle sont classés comme déjà écoutés ; le réordonnancement est suspendu
  et la suppression cible les bons identifiants. Modifier la suite ne déplace ni
  ne supprime le morceau courant.
  Toucher un titre conserve la file au lieu de la reconstruire.
- Vider la suite demande confirmation, conserve la lecture et arrête explicitement
  la radio. Les données de bibliothèque ne sont jamais supprimées par cette action.
- Débit/format réels conservés ; diagnostics de démarrage, normalisation et
  préchargement regroupés dans « Détails audio » plutôt qu’empilés sous le titre.
- Un changement de morceau pendant un déplacement sur la barre de progression
  ne peut pas appliquer la position de l’ancien morceau au nouveau.
- Le fond réactif et AutoMix restent intégrés, avec leurs limites documentées.
- Correctif du fond progressif : accès au PCM AVPlayer par audio mix, mesures
  alignées sur le temps de présentation, mouvement des couleurs plus visible.
  [Architecture, limites et tests HTTP réels](SORYN-REACTIVE-BACKGROUND.md).

## Compatibilité et réseau

Identifiant **app.blusic.ios**, format de bibliothèque et réglages existants
inchangés. Opus original, AAC ancien, imports, playlists, favoris et comptes
facultatifs restent pris en charge. Aucun nouvel encodeur ni service payant.

Le mode hors ligne empêche aussi de **nouvelles** requêtes de pochettes pour les
vues et l’écran verrouillé : fichiers locaux ou images déjà en mémoire seulement.
Ce n’est pas un coupe-circuit de toutes les activités réseau de l’app : une
synchronisation de compte explicitement activée reste indépendante, et une
requête d’image déjà lancée peut finir en arrière-plan.

Le catalogue YouTube Music reste non officiel ; sa disponibilité n’est pas garantie.
Ni les temps réseau ni la consommation batterie n’ont été mesurés sur appareil
physique pour cette version : aucun facteur d’amélioration chiffré n’est annoncé.

## Vérifications et preuves

- Dix tests XCTest dédiés : réponses périmées, annulation pendant la frappe,
  isolation hors ligne, expiration du cache, pagination/erreurs/nouveaux essais,
  historique effaçable, filtrage, identité musicale et sécurité de la file native.
- Sept tests Python pour l’outil de capture, trois pour la sélection des suites.
- Contrôle syntaxique des 32 fichiers Swift et des références Xcode sous Windows.
  Ce n’est **pas** une compilation/type-check Swift Apple.
- La CI compile l’IPA arm64, exécute les suites natives, puis les régressions Opus,
  hors ligne, normalisation et synchronisation, séparément des diagnostics réseau.
- Captures sur grand iPhone et iPhone SE compatible avec le SDK : accueil,
  recherche, bibliothèque, lecteur, file, paroles, son, mode clair et gros caractères.
  Bibliothèque de démonstration hors ligne isolée en mémoire ; aucune donnée
  personnelle n’est modifiée. Une capture n’est ni un test de lecture du catalogue
  ni une preuve de synchronisation visuelle avec la musique.
- L’outil exige un PID confirmé, encore présent avant la capture, un en-tête PNG
  et des dimensions d’écran cohérentes. Un lancement expiré reste un échec.

**À compléter après la CI :** résultat exact des suites, inspection des captures,
vérification de l’IPA récupérée. Aucune livraison finale n’est déduite des seuls
contrôles Windows. Signature Apple encore nécessaire pour installer l’IPA non signée.

### Résultat intermédiaire du 20 novembre 2026

[Exécution 44719852936](https://github.com/certiitude/blusic-ios/actions/runs/44719852936),
commit `178a61e`, **avant le correctif du fond progressif** : compilation arm64 et
IPA non signée générée ; sur simulateur, fond natif 4/4, expérience 10/10,
normalisation 10/10, Opus/hors ligne 13/13 et comptes/appairage 6/6 réussis.

La CI n’est pas verte : radio/AutoMix 8/9 (le test POST supposait `httpBody`,
alors que URLSession fournit un `httpBodyStream`) ; suite déterministe 128/130
(même test et mesure instantanée du fond juste après la commande `node.play()`,
avant un premier callback de rendu dans une exécution). Les corrections gardent
les assertions sur le JSON réellement envoyé et sur du PCM réellement mesuré
pendant le chevauchement, avec une attente bornée pour le thread audio.

Les captures échouent à la terminaison d’une application absente sur le simulateur
fraîchement redémarré. L’outil vérifie désormais un PID vivant avant de demander
la terminaison ; il ne transforme toujours aucun délai expiré en capture réussie.
Les diagnostics réseau séparés gardent des échecs sur deux titres (refus de
source/anti-robot), sans les masquer comme une réussite du catalogue.

Ces résultats intermédiaires ne valident ni les changements suivants ni une IPA
finale. La nouvelle suite doit être exécutée de nouveau, puis les captures revues.
