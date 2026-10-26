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

## Vérifications à terminer

Compilation iPhone arm64, exécution réelle du moteur embarqué sur iPhone Simulator, décodage natif, lecture et déplacement à 90 s sur FUTUR AMOUR, vérification de la configuration du paquet final. **Aucun succès sur l’iPhone physique de l’utilisateur n’est encore affirmé.**
