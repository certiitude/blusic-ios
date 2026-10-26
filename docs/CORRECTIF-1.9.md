# Blusic iOS 1.9 — youtubei.js, SABR et lecteur natif

## Diagnostic et recherche

- Les métadonnées iOS et les premiers octets AAC pouvaient répondre alors que la suite du fichier recevait HTTP 403.
- Le [guide PO Token maintenu par yt-dlp](https://github.com/yt-dlp/yt-dlp/wiki/PO-Token-Guide) distingue l’accès aux métadonnées, l’accès au serveur média et l’attestation du client. Une clé du relais Blusic ne remplace pas cette attestation YouTube.
- Le [code actuel des profils yt-dlp](https://github.com/yt-dlp/yt-dlp/blob/master/yt_dlp/extractor/youtube/_base.py) précise les restrictions et changements de versions : les anciennes recettes « changer pour Android VR » ne sont plus une garantie de lecture.
- Les discussions [YouTube.js #724](https://github.com/LuanRT/YouTube.js/issues/724) et [#1124](https://github.com/LuanRT/YouTube.js/issues/1124) ont été lues comme données ; aucun script de commentaire n’a été exécuté tel quel. Les recherches Reddit ont renvoyé un refus HTTP 403 ou une page sans résultats exploitables, donc aucune solution n’est attribuée à Reddit.
- Les profils Safari, Safari mobile, intégré, visionOS et iOS récent ont été comparés sur FUTUR AMOUR : pas de HLS utilisable retourné. Le client web propose un flux **SABR**. Les requêtes SABR renvoyaient HTTP 200 mais le statut média restait `attestation pending` et aucun fichier complet n’était obtenu.

## Premier résultat audio réel

Diagnostic local **FUTUR AMOUR — L’ange**, identifiant `qMAzmGNeDxc` :

- SABR et attestation liée au titre : statut média **accepted**.
- Fichier AAC complet : **2 687 251 octets**, taille égale à celle annoncée, environ **6,5 à 6,8 s** sur le PC de test.
- SHA-256 : `50e78869bdb3b2f0fb7e1d97feff6e85de79495a4df265a90aa914a5dc3c4fb4`.
- Décodage FFmpeg vérifié : **AAC LC, stéréo, 44 100 Hz**, durée **165,86 s**, signal non silencieux (pic environ −11,48 dBFS dans l’extrait décodé). Aucun réencodage AAC appliqué.
- Le nouveau relais SABR a été déployé sur Render, mais ses requêtes YouTube reçoivent encore HTTP 403 depuis ce réseau. Ce résultat local n’est donc pas présenté comme une réussite depuis Render.

## Modification iOS

- Le moteur **youtubei.js/SABR est embarqué dans l’IPA**, avec ses licences, pour résoudre l’audio depuis l’iPhone plutôt que dépendre uniquement du réseau Render.
- WebKit sert seulement de moteur JavaScript/DOM de résolution. Le fichier complet est assemblé, contrôlé par AVAudioFile et confié au **lecteur audio natif**, avec arrière-plan, égaliseur, vitesse/tonalité et commandes système.
- Un seul travail de résolution sur l’appareil à la fois ; annulation, délai de préparation borné, contrôle des tailles et des hôtes réseau. Les fichiers validés rejoignent le cache audio existant.
- Le relais youtubei.js distant est également préconfiguré dans le build. L’accès application est **sans expiration et sans quota d’écoutes Blusic**. La clé d’administration Render et la clé maître du serveur ne sont pas intégrées au paquet. Les limites du plan gratuit et les restrictions YouTube restent applicables.
- L’accès contenu dans le paquet est nécessairement récupérable dans une IPA ; il n’est pas présenté comme un secret impossible à extraire. La sauvegarde JSON de bibliothèque ne l’exporte pas.

## Révision de préparation — build 12

- Session invitée éphémère cohérente entre les requêtes de métadonnées, d’attestation et de média ; aucun cookie de compte importé. Le transport Node utilise un CookieJar et le transport iOS le stockage mémoire de sa propre URLSession éphémère.
- Le pont natif lit les réponses par blocs avec contre-pression plutôt que charger toute la réponse réseau en mémoire avant de la transmettre à JavaScript. Les callbacks et le fichier temporaire sont liés à un identifiant de travail pour qu’une annulation précédente ne puisse pas effacer la préparation suivante.
- La préparation complète du prochain titre commence à **45 secondes réelles de la fin**, en tenant compte de la vitesse. Le titre choisi est conservé en mode aléatoire et le fichier préparé est transmis au lecteur natif lors de Suivant/du fondu. Une modification de la file ou de la source invalide la préparation.
- Vérifications locales : **6 tests Node réussis**, syntaxe des 22 fichiers Swift et ressources vérifiées. FUTUR AMOUR est encore récupéré entièrement par Node : **2 687 251 octets en 8,38 s**.
- Le test du même bundle navigateur avec transport Node et session invitée reste en échec : **1 132 349 / 2 687 251 octets**, statut d’attestation `2` et arrêt du flux. La présence d’une preuve n’est pas présentée comme son acceptation.
- Une attestation fraîche via l’API YouTube WAA `Create`, ainsi que l’installation de son interpréteur par un élément script du DOM, ont également été essayées dans le diagnostic navigateur : même blocage. Ces essais n’ont pas été conservés comme correctifs dans le moteur livré.

## Résultat Xcode du build 12

- [Exécution GitHub Actions 40401811662](https://github.com/certiitude/blusic-ios/actions/runs/40401811662), commit `79241e4`, macOS 15.7.9 / Xcode 26.3 / iPhone 17 Pro Max Simulator iOS 26.2.
- **Compilation iPhone arm64 réussie**, paquet vérifié : version **1.9.0, build 12**, minimum iOS 17.0, **35 855 738 octets**, moteur et licences embarqués, accès application préconfiguré non expirant. IPA non signée à `dist/github/40401811662/Blusic-unsigned.ipa`.
- **77 tests réussis, 3 échoués, 0 ignoré sur 80**. Les quatre nouveaux tests passent : seuil de 45 secondes avec vitesse variable ; réutilisation du fichier lors de Suivant avec chevauchement des deux lecteurs natifs ; même titre préchargé en lecture aléatoire ; callbacks d’annulation ne pouvant pas supprimer le fichier du travail suivant.
- Le premier essai du test de fondu observait l’état sortant conservé pendant le chargement, avant que le titre entrant commence. L’attente a été corrigée pour exiger la première progression audio entrante ; les exigences de chevauchement et d’absence de seconde résolution sont conservées.
- Réseaux démarre depuis le préchargement de test en **0,25 s** et Stephanie passe la lecture native et le déplacement à **30,87 s**, via Invidious. Ces réussites ne sont pas attribuées au chemin SABR sur l’appareil.
- Les échecs restent **Damso en accès direct**, **Salé via l’instance Invidious historique**, et **FUTUR AMOUR via le moteur embarqué/secours**. Pour FUTUR AMOUR, YouTube répond encore « Connectez-vous pour confirmer que vous n’êtes pas un robot » sur le réseau du simulateur ; le relais de secours expire.
- Le service Render a reçu les changements de session (`1b96265`) et est démarré, mais le test avec l’accès application échoue encore en HTTP 502 après **53,8 s**, avec refus YouTube 403 et expiration de secours.
- Treize captures natives grand/compact ont été récupérées à `dist/tests/40401811662/screenshots/`. Les vues lecteur et paroles ont été inspectées. Elles montrent les fichiers démo de l’application et ne constituent pas une preuve de lecture des titres refusés.

**Le préchargement et le paquet sont vérifiés ; la correction générale des refus du fournisseur n’est pas validée. Aucun succès sur l’iPhone physique de l’utilisateur n’est affirmé.**
