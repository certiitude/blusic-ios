# Soryn pour Windows

Application de bureau Windows 10/11 x64, construite avec Electron. Pas un site vitrine : bibliothèque sur disque, import/copie de fichiers audio, lecture audio Windows, file, volume, vitesse/tonalité liées, commandes multimédias, favoris, playlists, recherche de chansons YouTube Music et téléchargements persistants. Le moteur youtubei.js/SABR du projet est embarqué ; aucune clé maître ni clé d’administration n’est incluse.

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

## Associer l’iPhone

1. Sur un **Wi-Fi privé**, ouvrir **Synchroniser → Activer la synchronisation locale** sur le PC.
2. Autoriser Soryn dans le pare-feu Windows **sur le réseau privé seulement**, si Windows le demande. Aucun réglage du pare-feu n’est modifié automatiquement.
3. Copier le lien privé affiché. Sur l’iPhone équipé de **Soryn 1.11.0+**, ouvrir **Réglages → Synchroniser avec Windows**, coller le lien et associer.
4. Garder les deux apps ouvertes pendant l’échange. L’iPhone vérifie ensuite toutes les 15 secondes au premier plan. Désactiver le partage sur le PC ferme l’écoute réseau ; révoquer les associations invalide les anciennes clés.

Le lien contient une clé aléatoire de 256 bits : ne pas le publier. La clé est protégée par DPAPI/safeStorage sur Windows et le trousseau sur iOS. Les échanges HTTP locaux contiennent exclusivement des enveloppes AES-256-GCM authentifiées, jamais la clé en clair. Nonces aléatoires, identifiant de requête, fenêtre temporelle et rejet des répétitions. L’iPhone refuse les adresses publiques et les redirections ; le serveur refuse les origines navigateur.

### Données partagées

- Références de titres, métadonnées/paroles enregistrées, playlists, favoris, artistes suivis et historique.
- Fusion à trois états par appareil, retraits de favoris et de playlists propagés. Les ajouts identiques du catalogue sont dédupliqués avec réaffectation des références. Historique de session fusionné par maximum, pas additionné deux fois.
- Conflit simultané sur un même champ : priorité au PC ; suppression concurrente d’une entité modifiée : conservation de l’entité modifiée. Une modification effectuée sur l’iPhone pendant une requête reste locale jusqu’à l’échange suivant.

### Données qui restent locales

- **Pas de transfert des octets audio**, fichiers personnels ni téléchargements ; les fichiers locaux sont représentés sur l’autre appareil par une référence non résolue. Ils doivent y être importés séparément. Les fichiers personnels d’origine ne sont pas effacés par un échange.
- Réglages, file/position de lecture, clés de relais et chemins privés non partagés. Ce n’est pas une télécommande ni une synchronisation via Internet. L’iPhone fonctionne avec le PC éteint.

Les données Windows vivent dans `%APPDATA%/Soryn/`, les téléchargements dans `Downloads/` séparément du cache. Écriture atomique et copie `.bak` de la bibliothèque ; une bibliothèque illisible est conservée au lieu d’être remplacée par les démos. Désinstaller ne supprime pas les données applicatives.

## Limites de cette première version Windows

- Les accès YouTube restent non officiels et peuvent refuser certains titres. La recherche ne prouve pas qu’un fichier est lisible. L’AAC est compressé, sans promesse 256 kbit/s ni lossless.
- Le fichier en ligne est entièrement préparé, avec taille et durée vérifiées, avant lecture. Une préparation peut être annulée ; les échecs de playlist n’empêchent pas les titres suivants.
- L’égaliseur, la tonalité indépendante, les profils artistes, les imports de services/CSV, le fondu et les paroles recherchées automatiquement de l’iPhone ne sont pas encore portés à Windows. Les paroles déjà sauvegardées sont affichables. Les fonctionnalités iOS existantes restent dans l’app iPhone.
- Paquets Windows non signés par un certificat commercial. L’IPA iPhone doit être signée pour être installée. Le nom affiché est Soryn, mais l’identifiant iOS `app.blusic.ios` et les dossiers historiques sont conservés pour la continuité des données.

## Vérifications

- `npm test` : stockage/reprise, fusion/déduplication, retraits/conflits, chiffrement/authentification, vrai échange HTTP, rejet de répétitions et d’origines navigateur, parsing du catalogue.
- `npm run smoke` : vraie application Electron, lecture WAV et seek 30 s, pause, favoris, playlist, protocole chiffré dans l’app en cours, mise en page 1000×700, vitesse, recherche réseau et captures. Profil temporaire séparé ; aucune donnée du créateur utilisée.
- Le workflow macOS lance `test/ios-server.mjs`, puis XCTest envoie de vraies enveloppes CryptoKit au serveur Node. Ce test ne remplace pas un essai sur iPhone physique ni celui du pare-feu et du Wi-Fi de l’utilisateur.
