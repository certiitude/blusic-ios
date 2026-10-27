# Blusic iOS 1.10.0 — téléchargements hors ligne

## Utilisation

- Menu **… d’un titre → Télécharger pour écouter hors ligne**.
- Dans une playlist/sélection : **Télécharger cette sélection**, ou appui long sur une playlist → **Télécharger la playlist**.
- **Bibliothèque → Téléchargements** et **Réglages → Téléchargements hors ligne** : titres en attente, préparation, échecs et bouton de nouvel essai, annulation, taille des fichiers, lecture de la sélection téléchargée, suppression individuelle ou globale avec confirmation.
- La section **Hors ligne** regroupe les fichiers importés, démonstrations et téléchargements terminés. Une icône indique les téléchargements dans les listes.

## Stockage et lecture

- Les téléchargements sont des copies persistantes dans **Application Support/Blusic/Downloads**, pas le cache temporaire. Pas d’expiration automatique ; exclusion de sauvegarde iCloud pour ne pas y dupliquer les fichiers récupérables.
- Copie atomiquement indexée après contrôle de décodage AVAudioFile, de durée, taille et espace disque disponible. Une réponse HTML, un 403 ou un fichier incomplet n’est jamais annoncé comme téléchargé.
- Les identifiants/source du titre, ses favoris et ses playlists ne sont pas remplacés. Le lecteur cherche le fichier téléchargé **avant tout accès réseau**, quelle que soit la qualité actuellement choisie ; il le lit avec le même moteur natif, le déplacement, les effets et le fondu.
- Les fichiers terminés sont relus après redémarrage de l’application. La suppression d’un téléchargement garde le titre et les playlists. Une sauvegarde JSON de bibliothèque n’embarque pas les fichiers audio téléchargés.
- Les pochettes disponibles sont copiées localement après téléchargement ; leur échec n’invalide pas le fichier audio. Les paroles déjà obtenues sont conservées par la bibliothèque.
- La préparation explicite des téléchargements est séquentielle pour limiter l’espace et le nombre de résolutions. Un titre en échec ne bloque pas les suivants et peut être relancé. Annulation disponible pendant la préparation.
- Pour une référence CSV/Deezer, la correspondance catalogue doit être suffisamment sûre ; un titre ambigu est signalé plutôt que remplacé arbitrairement.
- **Garder l’app ouverte pendant la préparation.** L’assemblage youtubei.js utilise WebKit et n’est pas annoncé comme un téléchargement illimité en arrière-plan : iOS peut suspendre le processus. Les fichiers terminés restent écoutables en arrière-plan sans connexion.

## Vérifications prévues

Tests iOS ajoutés : copie persistante et relecture après réouverture du stockage ; lecture native/seek à 30 s avec un chargeur réseau qui doit ne jamais être appelé ; téléchargement d’une playlist poursuivi après un échec et sans doublons ; suppression conservant la bibliothèque ; annulation sans entrée partielle ; rejet des fichiers tronqués et des chemins non autorisés dans le manifeste.

Ces scénarios emploient les fichiers originaux de démonstration comme fixtures. Ils ne remplacent pas une validation de téléchargement depuis chaque fournisseur.

## État de vérification et de compilation

- Contrôles statiques Windows réussis : syntaxe des **24 fichiers Swift**, références Xcode, plist et ressources. Cela ne constitue **pas** un type-check Xcode ni une exécution des nouveaux tests.
- Version préparée : **1.10.0 build 15**, iPhone iOS 17 minimum. Quatre scénarios de test ajoutés, dont lecture sans appel au chargeur réseau, reprise après réouverture du stockage, gestion des échecs et annulation.
- [Exécution GitHub Actions 40501346409](https://github.com/certiitude/blusic-ios/actions/runs/40501346409), commit `0a9d840` : **bloquée avant démarrage**, aucune étape Xcode exécutée. Annotation GitHub : paiements récents échoués ou limite de dépenses nécessitant une vérification dans la facturation du compte.
- **Aucune nouvelle IPA produite, aucun test simulateur des téléchargements annoncé réussi.** La dernière IPA 1.9.2 n’inclut pas cette fonction. Il faut rétablir l’accès aux runners macOS puis compiler, exécuter les tests et inspecter les captures pour livrer l’IPA 1.10.0.
- Aucun paiement ni changement de budget n’a été effectué. La compilation iOS ne peut pas être remplacée par le build Android local sur ce PC Windows.

## Livraison Xcode vérifiée après déblocage

- GitHub Actions a pu redémarrer. L’exécution `40502525343` a révélé un argument par défaut `Self.defaultRoot` refusé par Swift ; correction avec le nom explicite du type.
- [Exécution 40502866535](https://github.com/certiitude/blusic-ios/actions/runs/40502866535), commit **`d7f2f685ddba216514b5e098b184a55f52cf4ec5`** : compilation iPhone arm64 réussie avec Xcode 26.3 ; **88 tests réussis sur 91, 3 tests en échec, 0 ignoré** sur iPhone 17 Pro Max Simulator iOS 26.2.
- **Les quatre nouveaux tests hors ligne passent** : stockage persistant après réouverture et lecture native/seek à 30 s sans aucun appel au chargeur réseau ; playlist avec un titre refusé et poursuite des autres sans doublons ; annulation sans entrée complète ; rejet d’audio tronqué et de chemins non autorisés. Ces vérifications utilisent les instrumentaux originaux du projet comme fixtures.
- Les trois échecs sont les accès réseau historiques **Damso direct, Salé via Invidious, FUTUR AMOUR via moteur embarqué/secours**. Ils restent visibles et ne sont pas présentés comme résolus par les téléchargements. La fonction hors ligne ne peut enregistrer que les titres dont la source fournit réellement un fichier complet.
- IPA physique iPhoneOS **1.10.0 build 15**, minimum iOS 17, **35 991 665 octets** : `dist/github/40502866535/Blusic-unsigned.ipa`. Vérification du paquet arm64, moteur embarqué et accès relais non expirant réussie avec `verify_ipa.py --require-youtubei`. **Non signée**, à signer pour installation.
- Captures à `dist/tests/40502866535/screenshots/`, notamment `large-downloads.png` et `compact-downloads.png`, inspectées. Elles montrent l’écran de gestion vide ; la persistance et la lecture d’un fichier téléchargé sont vérifiées par les tests, pas déduites de ces images.
- Une exécution supplémentaire `40506010725`, ne changeant que l’ordre de collecte des artefacts et sa limite de temps, a été annulée une fois les preuves du premier run disponibles : le code applicatif livré reste celui de `d7f2f68`.
