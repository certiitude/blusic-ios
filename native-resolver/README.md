# youtubei.js / SABR embarqué dans l’IPA

Ce module est compilé en une ressource JavaScript iOS. Il utilise **youtubei.js 18.3.0**, **GoogleVideo 5.0.1** et **BgUtils 4.0.3** pour résoudre un flux AAC avec le protocole SABR et une attestation d’origine propre au titre.

WebKit exécute le protocole et son environnement DOM. **Il ne contient pas de lecteur vidéo ou audio utilisé pour la lecture** : les octets AAC sont transmis avec acquittement à Swift, validés avec AVAudioFile puis lus par AVAudioEngine. Les accès réseau sont effectués par URLSession depuis l’iPhone, avec une liste d’hôtes HTTPS autorisés, sans cookies de compte ni clé Render transmise à Google.

Le transport garde les cookies anonymes de sa propre session éphémère, lit les réponses par blocs de 32 Kio et lie les callbacks/fichiers temporaires à chaque travail. Il ne partage pas les cookies Safari. Une annulation ancienne ne peut pas effacer le fichier d’une nouvelle résolution.

Cette exécution locale évite que la lecture dépende uniquement d’une adresse IP de datacenter Render. Le fournisseur peut néanmoins refuser l’attestation ou le contenu ; ces échecs doivent rester visibles dans les tests. Aucun résultat n’est déclaré fonctionnel uniquement parce qu’un jeton a été généré ou qu’une réponse HTTP 200 a été reçue.

```text
npm ci --ignore-scripts --no-audit --no-fund
npm run build
```

La commande génère `Blusic/YouTubeiResolver.js` et `Blusic/ThirdPartyResolverLicenses.txt`, copiés par Xcode dans l’IPA. Le workflow iOS exécute cette compilation avant Xcode et vérifie la présence du moteur dans le paquet final. Les ressources générées sont exclues de Git.

Le relais distant reste un secours configurable. L’IPA peut inclure son URL et un accès **application sans expiration**, qui ne donne aucun droit d’administration Render et ne permet pas de signer de nouveaux liens audio. Cet accès client est récupérable dans une IPA ; le stocker ensuite dans le trousseau ne rend pas le contenu du paquet secret. La clé maître du serveur reste hors de l’IPA et du dépôt. Aucun quota d’écoutes n’est ajouté par Blusic ; les limites techniques de l’hébergeur et les autorisations du fournisseur restent applicables.
