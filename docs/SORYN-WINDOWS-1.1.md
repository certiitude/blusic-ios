# Soryn Windows 1.1.0 — interface, catalogue et compte facultatif

## Nouvelle interface

- Navigation et bibliothèque plus lisibles, surfaces sobres et légèrement translucides teintées par la pochette, accent bleu Soryn. Inspiration Spotify, Apple Music et tryLiner, sans reprendre leurs logos, leur code ni leurs médias.
- Accueil fondé sur tes morceaux réels ; onglets Tout/Musique/Playlists ; présentations de playlists avec pochettes.
- Recherche locale par titre/artiste/album, insensible aux accents, tris, grille/liste et préférences conservées après redémarrage. Les tris ne modifient pas l’ordre sauvegardé.
- Lecteur fixe ; panneau En lecture/À suivre que l’on peut fermer ; sur petite fenêtre, le panneau s’ouvre en superposition au lieu d’écraser la bibliothèque. Paroles déjà enregistrées agrandies et réduction des animations respectée.

## YouTube Music et accès audio

- Recherche publique **Titres, Albums, Artistes, Playlists**, avec pagination. Ouverture des albums/artistes/playlists et ajout des titres chargés à une playlist locale.
- La recherche Titres reste centrée sur les chansons de YouTube Music, sans repli sur une recherche générale de vidéos. Dans une playlist explicitement ouverte, l’audio des vidéos musicales choisies par son auteur peut aussi être lu. Les recommandations du fournisseur ne sont pas confondues avec la suite de la playlist.
- Trois accès audio automatiques : **youtubei.js/SABR sur ce PC**, **Invidious** (instances initiales + annuaire public des API annoncées actives) et **relais youtubei.js préconfiguré**. Le premier fichier AAC complet et validé est retenu.
- **Aucune clé à saisir dans l’app.** Le paquet contient seulement une capacité application non expirante acceptée par le relais existant ; aucune clé maître ou d’administration n’est embarquée. Les accès n’imposent pas de quota d’écoutes propre à Soryn ; les limites des fournisseurs demeurent.
- Pas de téléchargement préalable de tout YouTube Music : le catalogue est interrogé à la demande. Ni disponibilité universelle, ni bibliothèque Google privée, ni qualité 256 kbit/s ou lossless garanties. Un résultat de recherche ne prouve pas que son audio est accessible.
- Test réseau du relais : santé HTTP200, accès application non refusé, **résolution audio HTTP502** sur le titre testé. Le relais est préconfiguré, mais sa lecture audio n’est pas annoncée comme validée. Les autres accès restent utilisables indépendamment.

## Compte facultatif

Connexion pseudo/mot de passe uniquement pour synchroniser les métadonnées de bibliothèque entre iPhone et PC par Internet. L'écoute, les imports, les téléchargements et la bibliothèque locale restent accessibles sans compte. La synchronisation Wi-Fi sans compte reste disponible. Déconnexion et suppression du compte ne suppriment pas la bibliothèque locale. Voir [sécurité, tests et limites de l'hébergement gratuit](SORYN-ACCOUNTS.md).

## Installation et données

**Windows 10/11 x64** : `Soryn-1.1.0-Setup.exe` ou `Soryn-1.1.0-portable.exe`. Exécutables non signés par un certificat commercial ; Windows peut avertir de l’éditeur inconnu.

Installer la nouvelle version sans supprimer les données de l’ancienne. Même identifiant `app.soryn.desktop`, même dossier `%APPDATA%/Soryn/`, même format de bibliothèque : fichiers personnels, favoris, playlists et téléchargements conservés. Le protocole de synchronisation local iPhone n’est pas remplacé par un service cloud ; cette publication PC ne constitue pas une nouvelle validation de l’IPA iPhone.

## Vérifications

- **26/26 tests unitaires/protocole** : stockage, fusions, sécurité des échanges, parsing du catalogue, filtre/tri non destructifs, configuration du relais, sélection Invidious, rejet d’audio tronqué ou d’adresses privées et redirections non autorisées.
- [Compilation GitHub Actions Windows 41869159489](https://github.com/certiitude/blusic-ios/actions/runs/41869159489) réussie sur le commit `7d18767`, avec les tests et le relais application injecté depuis le secret de CI.
- **10 scénarios UI** : accueil, onglets, filtre et remise à zéro, grille/liste, tri, lecture d’une sélection filtrée, playlists, favoris, file, paroles, réglages/raccourcis, préférences et réduction des animations ; écrans1440px,1280×800,1000×700 et980×680.
- **8 contrôles du vrai catalogue** : recherche et pagination de titres ; albums, artistes, playlists ; ouverture/import d’album ; ouverture des propres titres d’une playlist ; configuration présente sans clé exposée dans l’état envoyé au renderer.
- Les scripts `windows/tools/smoke.mjs`, `ui-check.mjs`, `catalog-ui-check.mjs` et `smoke-import.mjs` lancent la vraie application avec des profils temporaires séparés. Les captures ne remplacent pas les tests audio.
- Audit des dépendances embarquées : aucune vulnérabilité signalée au moment du contrôle. Des alertes modérées existent dans les outils de développement non distribués.

Les preuves de compilation/UI/catalogue ci-dessus concernent d'abord la refonte au commit `7d18767`, avant l'ajout des comptes. Pour les comptes : cinq suites backend/clients passent, dont deux clients HTTP contre la vraie base Supabase ; six scénarios Electron avec le vrai DPAPI Windows passent, sans erreur JavaScript (inscription, fusion distante, redémarrage, déconnexion et suppression). La nouvelle compilation et la validation native iPhone sont suivies séparément ; ne pas assimiler une vérification statique Swift à une compilation Xcode.

Voir aussi [`windows/README.md`](../windows/README.md) pour la compilation, les limites et l’appairage iPhone.
