# Blusic 1.5.0 — livraison vérifiée

## Build et fichier

- Commit compilé : `53f6693a17f047ffdb6b6491e6574661b8763c2c`.
- Exécution : https://github.com/certiitude/blusic-ios/actions/runs/40139429050
- Résultat global GitHub Actions : **success**.
- Xcode 26.3, build Release iPhone **arm64**, iOS minimum **17.0**.
- IPA locale : `dist/github/40139429050/Blusic-unsigned.ipa`.
- Taille : **35 356 625 octets**, version **1.5.0**, identifiant `app.blusic.ios`.
- Paquet vérifié après téléchargement : plateforme iPhoneOS, Mach-O arm64 pour iOS physique, images compilées et médias présents.
- **Non signée** : signature de sideload nécessaire avant installation.

## Tests réellement exécutés

**51 tests passés, 0 échec, 0 ignoré**, sur **iPhone 17 Pro Max / iOS 26.2 Simulator**.

Mesures enregistrées dans les logs du test réseau :

- « Salé », Niska, album Commando, identifiant de chanson YouTube Music `zka6uW2aurU`.
- Premier avancement audio à froid : **0,75049 s** ; démarrage complet observé par le test : **0,76403 s**.
- Flux source **AAC 134 130 bit/s** ; durée audio décodée **170,27048 s**, signal non silencieux confirmé.
- Passage au moteur d’effets, déplacement et pause vérifiés.
- « Réseaux » préchargé : premier avancement **0,25110 s**.
- Paroles du fournisseur : **46 lignes synchronisées**.
- **Vue SwiftUI paroles réelle** attachée à une fenêtre : recherche automatique et cache de 46 lignes vérifiés.
- Barre inférieure : présence d’une **UITabBar système** vérifiée, en plus de l’utilisation de `TabView` et `tabViewBottomAccessory` dans le code.
- Favoris : ajout direct d’un résultat non sauvegardé et reconnaissance après une nouvelle recherche (UUID différent) testés.
- CSV Spotify : noms/artiste/durée convertis en identifiant de chanson YouTube Music testé ; collaboration et crédits « feat./avec » pris en compte.
- Fondu natif : deux lecteurs actifs pendant la transition, fin du fondu, désactivation, pause des deux et enchaînement automatique testés.
- Durée doublée et queue silencieuse : durée de conteneur incohérente bornée et segment natif arrêté à la durée déclarée testés.
- Relation vitesse/demi-tons et modes lié/indépendant testés.

Ces mesures concernent le **simulateur et le réseau du runner**, pas le téléphone physique du créateur. Elles ne garantissent pas tous les titres, tous les réseaux ou un départ instantané universel.

## Captures inspectées

Dossier : `dist/screenshots/40139429050/`.

Grand iPhone : accueil, recherche, lecteur, recherche d’artistes, profil, réglages audio et paroles. iPhone SE : accueil, recherche et lecteur.

La barre inférieure et le mini-lecteur sont désormais les composants système d’iOS 26. Le défilement sous leur verre suit le comportement natif Apple. Les images ont été examinées pour le cadrage, les débordements et la lisibilité ; les bannières d’artiste remplissent leur conteneur et les pochettes Google demandent 1024 px.

La capture paroles utilise un **texte d’exemple original**, pour le contrôle visuel. Elle n’est pas présentée comme la preuve du fournisseur ; le test réseau et le test de la vue paroles sont distincts.

## Utilisation des imports

Dans Bibliothèque → + → Importer une playlist :

1. Choisir un CSV Spotify/Apple Music/Soundiiz/TuneMyMusic, ou un lien Deezer public.
2. L’association YouTube Music démarre automatiquement ; attendre le bilan avant Ajouter à Blusic.
3. Les titres trouvés stockent une vraie référence musicale YouTube Music. Les absences ou ambiguïtés sont signalées ; aucune reprise différente ni extrait Deezer de 30 secondes n’est utilisé comme morceau complet.

## Limites explicites

- Aucun `youtubei.js` n’a été ajouté.
- Pas d’AAC 256 kbit/s gratuit garanti : les formats du serveur sont sélectionnés et affichés honnêtement. Le titre testé fournit environ 134 kbit/s ; le 256 de YouTube Music est lié à l’offre Premium.
- Les favoris perdus par une ancienne version avant sauvegarde de leur métadonnée ne peuvent pas être retrouvés à partir d’un UUID seul ; les nouveaux ajouts sont maintenant sauvegardés correctement.
- Les tests manuels d’écoute et d’arrière-plan sur iPhone physique restent nécessaires après signature et installation de cette version.
