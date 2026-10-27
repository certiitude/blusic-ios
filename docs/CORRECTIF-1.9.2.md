# Blusic 1.9.2 — interface Android, images, performances et préchargement

## Corrections Android

- Les blocs de liste qui émettaient plusieurs éléments dans la même cellule utilisent désormais une colonne : titre de playlist et compteur, titre de file et bouton, commandes de chaque titre, séparateur/EQ, messages d’erreur et texte du relais.
- Le lecteur calcule la place disponible. La pochette diminue sur petit écran ou police agrandie, les métadonnées longues ont leurs propres lignes et une zone défilante ; progression et commandes restent accessibles. Mini-lecteur et profils artistes ont des largeurs contraintes et une troncature explicite.
- Les pochettes sont demandées à la taille physique de l’écran, avec un plafond de 1 536 pixels pour la grande vue. Les dimensions Google non signées reconnues sont remplacées par la taille souhaitée ; les autres URLs et les URLs signées restent intactes. Retour à l’URL originale si la variante HD échoue. Les pochettes de fichiers importés sont conservées jusqu’à 1 536 pixels au lieu de 512 pour les nouveaux imports.
- Diagnostic réel du catalogue : image reçue initialement **120 × 120**, variante demandée reçue **1 024 × 1 024**. Ce résultat vérifie les dimensions retournées par le fournisseur, pas une garantie que chaque original du catalogue possède davantage de détails.
- Cache images mémoire borné à 48 Mo (ou un huitième du tas si inférieur) et disque 80 Mo ; requêtes d’images mémorisées, tailles limitées et cache HD distinct de l’ancien.
- Les mutations identiques ne réécrivent plus le JSON ; les index des titres sont réutilisés lorsque seul l’historique change. L’interface reçoit un état sans l’historique de statistiques, évitant une recomposition globale toutes les cinq secondes d’écoute. Métadonnées courantes et de file mises en cache au lieu de reparsées à chaque tick ; réglages audio/focus appliqués lors des changements pertinents.
- Le mode automatique ne reste plus bloqué jusqu’à 32 secondes sur un résolveur local lent avant d’essayer les autres sources : moteur local et secours se recouvrent avec un léger décalage ; premier accès validé conservé, autres tentatives annulées.

## Relais préconfiguré

- URL et accès application Android injectés dans l’APK ; activation et persistance au premier démarrage sans adresse ni clé à saisir.
- Une copie de clé manquante dans Keystore est réparée depuis la configuration embarquée. Une désactivation explicite ou un serveur personnalisé sont respectés.
- Carte « Relais Blusic préconfiguré · activé » et bouton de restauration en un geste ; saisie manuelle réservée à un panneau avancé facultatif.
- Accès application sans expiration ni quota d’écoutes Blusic ; la clé maître reste hors du paquet. La disponibilité YouTube et les limites Render Free demeurent indépendantes de cette configuration.

## Préchargement iOS et Android

- Après un échec ou un délai dépassé de préparation, nouvelle tentative sans limite de nombre tant que ce titre demeure celui à préparer.
- Pause progressive **1, 2, 4, 8, puis 10 secondes** entre les échecs, plafond 10 secondes. Chaque tentative reste bornée à 35 secondes, sans boucle réseau serrée.
- URL échouée invalidée avant de réessayer. Même tâche/résultat réutilisé pour Suivant et le fondu. Pause, annulation ou changement de file/source arrêtent les essais.
- Les nouvelles tentatives n’arrêtent pas le titre courant. Elles ne garantissent pas une absence de silence si le fournisseur reste inaccessible jusqu’à la fin de ce titre.

## Vérifications finales

### Android — compilation et émulateur locaux

- Commit applicatif **`cfbdd2d`** ; outils officiels isolés dans le répertoire temporaire autorisé, JDK 17, Gradle 8.11.1, SDK 35. Aucun paiement engagé, aucune modification de configuration système nécessaire.
- Les nouvelles exécutions GitHub Actions ont été bloquées avant démarrage par la facturation/limite du compte (`40420763023`). La compilation et la suite émulateur ont donc été terminées sur ce PC, sans prétendre que cette exécution GitHub a réussi.
- **20 tests JVM réussis**, 0 échec/ignoré ; lint réussi. Cas : sélection et décodage HD, index réutilisés, réparation de clé, absence de limite de nombre d’essais et annulation, course des sources.
- **11 tests sur Android 15 émulé réussis**, 0 échec, 0 erreur, 0 ignoré. Incluent lecture réseau Stephanie et recherche à 30 s, fondu à deux lecteurs/pause, fichier original via pont JavaScript, relais préconfiguré persistant, aucune écriture pour 20 ajouts déjà présents et mutations identiques, petit écran **720 × 1 280 avec police ×1,3**, titre/artiste non superposés et commandes accessibles.
- Fixture de décodage Coil : miniature **160 pixels**, grande image **960 pixels** ; test réel des dimensions du fournisseur distinct : **120 → 1 024 pixels**.
- Scénario index : 2 500 titres / 2 000 mises à jour d’historique, **4,26 ms** sur la machine locale de test, mêmes index conservés. Ce chiffre n’est pas une mesure des FPS sur le téléphone de l’utilisateur.
- Dix captures finales à `dist/tests/android-local-1.9.2/screenshots/` ; vues lecteur, réglages, relais, égaliseur et petit écran/file examinées.
- APK **1.9.2 versionCode 14**, Android 8+, **58 113 930 octets** : `dist/local/android-1.9.2/Blusic-1.9.2.apk`.
- SHA-256 : `1cc71ca0a0ccc1730d4747c13fa3af0a6b20d73b2c87863de78eb340d6a5472b`.
- Signature v2 validée par `apksigner`, contenu vérifié par `verify_apk.py` : moteur/mentions tierces et accès préconfiguré présents. Signature de développement locale, différente de celle d’anciens runners : sauvegarder les données avant toute désinstallation si Android refuse la mise à jour.

### iOS — Xcode et simulateur

- [GitHub Actions 40419399204](https://github.com/certiitude/blusic-ios/actions/runs/40419399204), commit `e0ec2f4` : compilation iPhone arm64 réussie, IPA **1.9.2 build 14**, **35 869 083 octets**, iOS 17 minimum, non signée.
- Fichier : `dist/github/40419399204/Blusic-unsigned.ipa` ; configuration relais non expirante et moteur embarqué vérifiés.
- **84 tests réussis sur 87, 3 échecs réseau, 0 ignoré**. Les deux nouveaux tests de reprise passent : plus de vingt échecs simulés avant réussite ; préparation réelle du suivant avec deux échecs, réutilisation du résultat puis annulation des nouveaux essais à la pause.
- Les trois échecs restent ceux des accès réseau Damso direct, Salé via Invidious et FUTUR AMOUR depuis le réseau du simulateur. Ils ne sont pas masqués. Ces échecs n’invalident pas les tests locaux de reprise, mais interdisent d’affirmer une disponibilité totale du catalogue.
