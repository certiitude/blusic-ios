# Soryn Windows 1.0.0

Application de bureau Windows 10/11 x64, autonome : nouveau logo Soryn, interface sombre/bleu brume et typographie Plus Jakarta Sans, inspirées du guide fourni.

## Installer

- `Soryn-1.0.0-Setup.exe` : installateur classique.
- `Soryn-1.0.0-portable.exe` : utilisation sans installation.

**Exécutables non signés par un certificat commercial.** Windows peut afficher un avertissement d’éditeur inconnu. Les sources et les rapports de vérification sont dans ce dépôt privé.

## Fonctions

Lecture audio, volume, vitesse/tonalité liées, file, commandes multimédias, favoris et playlists, import/copie de fichiers personnels, recherche de chansons YouTube Music, préparation AAC avec validation du fichier et de sa durée, téléchargements persistants séparés du cache, sauvegarde/fusion JSON.

**La synchronisation iPhone nécessite Soryn iPhone 1.11.0, dont la validation est encore en cours au moment de cette publication Windows. L’ancienne IPA Blusic 1.10.0 n’a pas cette fonction.** L’appairage prévu : même Wi-Fi privé, Windows → Synchroniser → copier le lien privé ; iPhone → Réglages → Synchroniser avec Windows → coller le lien. Les deux apps doivent être ouvertes. Aucun compte/cloud ; échanges AES-256-GCM.

La synchronisation porte sur les références des titres, playlists, favoris, artistes suivis, paroles enregistrées et historique. **Pas de transfert des octets audio**, des clés, des réglages ni de télécommande de lecture. Chaque appareil conserve ses propres imports et téléchargements.

L’égaliseur, la tonalité indépendante, le fondu, les imports de services/CSV, les profils artistes et la recherche automatique de paroles ne sont pas encore portés à Windows. Les paroles déjà sauvegardées sont affichables. Les sources YouTube peuvent refuser certains titres ; pas de garantie 256 kbit/s ni lossless.

## Résultats de vérification

- Version livrée construite localement depuis le code Windows du commit `b623a1b` ; installateur et portable générés. Les métadonnées PE et l’icône affichent Soryn.
- **14/14 tests unitaires/protocole**, notamment persistance, fusions, retraits, déduplication, chiffrement, vrai échange HTTP, refus de répétitions et protection des ajouts en cas de réponse perdue.
- **14/14 vérifications du vrai Soryn.exe empaqueté**, sans erreur JavaScript : décodage WAV/AAC, seek30s, pause, favoris, playlist, échange chiffré, fenêtre1000×700, vitesse, recherche20résultats, lecture de Stephanie et téléchargement rejoué sans réseau après redémarrage complet.
- **5/5 contrôles supplémentaires** : vrai import et lecture WAV ; rejet d’un fichier non audio sans bloquer les suivants ; sauvegarde avec les champs Swift requis ; réimport sans perdre la source locale ; référence supprimée depuis le protocole iPhone sans effacer le fichier personnel du PC.
- Audit npm : **0 vulnérabilité signalée**. Paquet vérifié : résolveur embarqué, worker, logo, police et licences présents ; aucun profil de test ni bibliothèque personnelle inclus.
- Le workflow Windows `40720896389` a également compilé le bureau et passé les13 tests de cette révision initiale. Le test « réponse perdue » a été ajouté ensuite et passe localement.

### SHA-256

```text
25014b04518c3b88495bd0bc0e1d7b51b11b1a73f02f5af84b499c20990a57d1  Soryn-1.0.0-Setup.exe
843031874250bb5712cb7e5187faf2743eb7f57e19f75fb946d2c601adc1bcd0  Soryn-1.0.0-portable.exe
```

Les tests ne constituent pas un essai sur l’iPhone physique, le Wi-Fi ou le pare-feu du créateur. [Documentation complète et compilation](../windows/README.md).
