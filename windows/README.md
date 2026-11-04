# Soryn pour Windows

Application de bureau Windows 10/11 x64, construite avec Electron. Pas un site vitrine : bibliothèque sur disque, import/copie de fichiers audio, lecture audio Windows, file, volume, vitesse/tonalité liées, commandes multimédias, favoris, playlists, catalogue YouTube Music et téléchargements persistants. Le moteur youtubei.js/SABR du projet est embarqué, avec secours Invidious et relais application préconfiguré ; aucune clé maître ni clé d’administration n’est incluse.

## Version 1.1 — interface et catalogue

- Navigation, surfaces et listes redessinées : inspiration Spotify/Apple Music et transparences teintées de tryLiner, tout en conservant le nom, le logo et le bleu Soryn. Aucun code, logo ou média de ces applications n’est redistribué.
- Accueil fondé sur la bibliothèque réelle, pochettes/présentation des playlists, filtres Musique/Playlists, recherche locale sans accents, tris et présentation grille/liste conservés après redémarrage. Les tris ne réécrivent pas l’ordre sauvegardé des playlists.
- Lecteur fixe, panneau En lecture/À suivre escamotable, vraie file à venir, fenêtre compacte et paroles enregistrées plus lisibles. Réduction des animations respectée.
- Recherche distante **Titres, Albums, Artistes, Playlists**, pagination des résultats, ouverture des sélections et ajout des titres chargés à une playlist locale. Les profils artistes exposent les titres renvoyés par leur page publique, pas une discographie intégrale inventée.
- Recherche de titres : chansons identifiées par YouTube Music, sans repli sur une recherche générale de vidéos. Une playlist publique explicitement ouverte peut contenir des clips ou des vidéos musicales ajoutées par son auteur ; leur audio est alors accessible au même lecteur, sans lecteur vidéo. Aucun accès à un compte Google, à une bibliothèque personnelle privée ou à un catalogue légalement indisponible n’est promis.
- Résolution en parallèle sur ce PC, relais youtubei.js et instances Invidious : premier fichier AAC complet, de taille et durée vérifiées, avant lecture. Pas de clé à saisir dans l’app, pas d’encodage artificiel vers 256 kbit/s ni de promesse de disponibilité universelle.

## Démarrer / compiler

Node 22.12+ et npm :

```powershell
cd windows
npm ci
node node_modules/electron/install.js
node tools/prepare.mjs
npm start
npm test
npm run smoke
npm run build
```

Les fichiers sont générés dans `dist/windows-soryn/` : installateur NSIS et exécutable portable. Le téléchargement du runtime Electron reste nécessaire après `npm ci` avec Electron 45. La compilation prend les images de `docs/branding/`, les quatre instrumentaux originaux de `Blusic/Audio/` et les modules de résolution de `relay/`. Le résultat est autonome, sans Node à installer pour l’utilisateur.

Avant `prepare.mjs` ou le build, configurer `SORYN_RELAY_ACCESS` et éventuellement `SORYN_RELAY_URL` dans l’environnement de compilation, ou générer `windows/assets/relay-config.json` avec `tools/configure_windows_relay.py --application-access-file <capacité-application-déjà-émise>`. Le build refuse une configuration absente/invalide. Ce fichier généré est ignoré par Git et ne contient que l’accès application non expirant accepté par le relais existant (compatible iOS/Android), jamais sa clé maître. Le workflow utilise le secret application déjà provisionné dans ce dépôt. L’app installée ne demande pas de configuration manuelle.

## Associer l’iPhone

1. Sur un **Wi-Fi privé**, ouvrir **Synchroniser → Activer la synchronisation locale** sur le PC.
2. Autoriser Soryn dans le pare-feu Windows **sur le réseau privé seulement**, si Windows le demande. Aucun réglage du pare-feu n’est modifié automatiquement.
3. Copier le lien privé affiché. Sur l’iPhone équipé de **Soryn 1.11.0+**, ouvrir **Réglages → Synchroniser avec Windows**, coller le lien et associer.
4. Garder les deux apps ouvertes pendant l’échange. L’iPhone vérifie ensuite toutes les 15 secondes au premier plan. Désactiver le partage sur le PC ferme l’écoute réseau ; révoquer les associations invalide les anciennes clés.

Le lien contient une clé aléatoire de 256 bits : ne pas le publier. La clé est protégée par DPAPI/safeStorage sur Windows et le trousseau sur iOS. Les échanges HTTP locaux contiennent exclusivement des enveloppes AES-256-GCM authentifiées, jamais la clé en clair. Nonces aléatoires, identifiant de requête, fenêtre temporelle et rejet des répétitions. L’iPhone refuse les adresses publiques et les redirections ; le serveur refuse les origines navigateur.

### Données partagées

- Références de titres, métadonnées/paroles enregistrées, playlists, favoris, artistes suivis et historique.
- Fusion à trois états par appareil, retraits de favoris et de playlists propagés. Les ajouts identiques du catalogue sont dédupliqués avec réaffectation des références. Historique de session fusionné par maximum, pas additionné deux fois. Le dernier état commun ne progresse qu’après confirmation de réception par l’iPhone : une réponse perdue ne peut pas faire passer un ajout PC jamais reçu pour une suppression côté iPhone.
- Conflit simultané sur un même champ : priorité au PC ; suppression concurrente d’une entité modifiée : conservation de l’entité modifiée. Une modification effectuée sur l’iPhone pendant une requête reste locale jusqu’à l’échange suivant.

### Données qui restent locales

- **Pas de transfert des octets audio**, fichiers personnels ni téléchargements ; les fichiers locaux sont représentés sur l’autre appareil par une référence non résolue. Ils doivent y être importés séparément. Les fichiers personnels d’origine ne sont pas effacés par un échange.
- Réglages, file/position de lecture, clés de relais et chemins privés non partagés. Ce n’est pas une télécommande ni une synchronisation via Internet. L’iPhone fonctionne avec le PC éteint.

Les données Windows vivent dans `%APPDATA%/Soryn/`, les téléchargements dans `Downloads/` séparément du cache. Écriture atomique et copie `.bak` de la bibliothèque ; une bibliothèque illisible est conservée au lieu d’être remplacée par les démos. Désinstaller ne supprime pas les données applicatives.

## Limites de cette première version Windows

- Les accès YouTube restent non officiels et peuvent refuser certains titres. La recherche ne prouve pas qu’un fichier est lisible. L’AAC est compressé, sans promesse 256 kbit/s ni lossless.
- Le fichier en ligne est entièrement préparé, avec taille et durée vérifiées, avant lecture. Une préparation peut être annulée ; les échecs de playlist n’empêchent pas les titres suivants.
- L’égaliseur, la tonalité indépendante, les imports de services/CSV, le fondu et les paroles recherchées automatiquement de l’iPhone ne sont pas encore portés à Windows. Les paroles déjà sauvegardées sont affichables. Les fonctionnalités iOS existantes restent dans l’app iPhone.
- Paquets Windows non signés par un certificat commercial. L’IPA iPhone doit être signée pour être installée. Le nom affiché est Soryn, mais l’identifiant iOS `app.blusic.ios` et les dossiers historiques sont conservés pour la continuité des données.

## Vérifications

- `npm test` : stockage/reprise, fusion/déduplication, retraits/conflits, chiffrement/authentification, vrai échange HTTP, rejet de répétitions et d’origines navigateur, parsing du catalogue.
- `npm run smoke` : vraie application Electron, lecture WAV et seek 30 s, pause, favoris, playlist, protocole chiffré dans l’app en cours, mise en page 1000×700, vitesse, recherche réseau et captures. Profil temporaire séparé ; aucune donnée du créateur utilisée.
- `npm run test:ui` : vues, filtres, tri, grille/liste, contenu joué, panneau/file, raccourcis, persistance des préférences, absence de débordement sur 980×680/1000×700/1280×800, captures des écrans réels.
- `node tools/catalog-ui-check.mjs` : vrai catalogue YouTube Music, catégories, pagination, album/playlist et import de sélection ; configuration du relais visible sans exposer l’accès application au renderer.
- Le workflow macOS lance `test/ios-server.mjs`, puis XCTest envoie de vraies enveloppes CryptoKit au serveur Node. Ce test ne remplace pas un essai sur iPhone physique ni celui du pare-feu et du Wi-Fi de l’utilisateur.
