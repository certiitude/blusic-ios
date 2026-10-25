# État du relais youtubei.js et du port Android

## Relais réellement déployé

- URL : `https://blusic-audio-relay.onrender.com`.
- Service Render `srv-dbf4git9fdbs738q120g`, **plan Free**, région **Frankfurt**. Aucun paiement n’a été configuré.
- Source : `relay/`, Node 22, youtubei.js 18.3.0 verrouillé dans package-lock.json.
- Clé d’accès générée et conservée hors du dépôt ; intégration iOS avec Trousseau, Android avec Android Keystore. Aucune clé n’est publiée dans ce document ni dans les sauvegardes de bibliothèque.
- Déploiement du commit `4b8e8ec9761b5a435eccedfd3cbfeff433fe8bd9` terminé et déclaré `live` par Render. Cela signifie seulement que le processus HTTP fonctionne.

### Essais réels et blocage restant

Depuis Render, la résolution de **FUTUR AMOUR — L’ange** (`qMAzmGNeDxc`) renvoie HTTP 502 avec **HTTP 403 sur les requêtes YouTube** des clients IOS et ANDROID_VR. Même résultat sur **Stephanie** (`RFzfXv9wzfo`). Le fichier complet n’a pas été obtenu.

Depuis le PC, les premiers octets M4A peuvent être reçus alors que les plages suivantes et le téléchargement youtubei.js échouent. Le client IOS n’a pas fourni de manifeste HLS dans la réponse testée. Le problème ne peut donc pas être déclaré corrigé en recevant un en-tête `ftyp` ou en démarrant un serveur Node. La validation des apps sonde désormais aussi **le milieu du fichier**, pas seulement son ouverture.

**Le relais n’est pas activé par défaut dans les apps tant que sa lecture réelle ne passe pas.** Les demandes de connexion et confirmations du fournisseur ne sont pas contournées. Les tests locaux et GitHub du protocole du relais passent (3 tests), mais utilisent un média de test et ne prouvent pas l’accès au catalogue.

L’offre Render gratuite se met en veille après inactivité et son réveil peut durer environ une minute. Les quotas d’heures et de trafic s’appliquent. Aucun abonnement payant n’est créé et aucune disponibilité illimitée n’est annoncée.

## iOS

L’intégration du relais, la protection de sa clé, le repli vers un fichier validé, l’assemblage de plages et l’invalidation après HTTP 403 sont implémentés. Exécution `40219781332` : **69 tests passés et 2 échoués sur 71**, aucun ignoré ; échecs réseau Damso et Salé conservés. La nouvelle compilation 1.8.0 inclut la vérification d’une plage au milieu du fichier.

## Android

Application native Kotlin/Compose et Media3 dans `android/`. APK de test Android 8+ compilé, signature vérifiée par `apksigner` dans GitHub Actions, ressources et manifeste contrôlés par `tools/verify_apk.py`.

Exécution `40222658806` : compilation, tests unitaires et lint réussis. L’émulateur Android 15 a démarré et exécuté 5 tests : **4 réussis, 1 échoué**. Réussites : vraie lecture d’un instrumental via le service, déplacement à 30 s, pause, écrans, persistance des favoris/playlists et assemblage HTTP sans octets manquants. Échec : lecture réseau Stephanie, délai de démarrage dépassé. Cet échec n’a pas été remplacé par un succès ou ignoré.

Le script de collecte a été corrigé pour récupérer les captures et logcat même lorsqu’un test réseau échoue. Les fichiers de test ne sont pas inclus dans les données de l’APK livré.
