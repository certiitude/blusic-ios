# Relais Blusic youtubei.js

Service Node 22 / **youtubei.js 18.3.0**, destiné à relayer un AAC complet vérifié plutôt qu’exposer à l’iPhone une URL Google signée pour une autre IP. Aucune connexion Google, aucun cookie de compte, aucune résolution de CAPTCHA ni génération de PO token.

- `GET /health` : état du serveur, **pas preuve de lecture**.
- `GET /v1/streams/<videoId>` avec `Authorization: Bearer <BLUSIC_RELAY_KEY>` : prépare le fichier complet et renvoie une URL temporaire du relais.
- `GET /v1/audio/<videoId>?ticket=…` : lecture et plages HTTP du fichier préparé. Une page HTML, un refus HTTP ou un fichier incomplet ne sont jamais considérés comme une réussite.
- Cache temporaire limité à 5 titres, 25 Mo par titre, 10 minutes ; aucun catalogue complet ni archive commerciale livrée avec le service.
- Deux préparations simultanées au maximum et 30 résolutions/minute ; pas de proxy d’URL arbitraire.

## Déploiement gratuit préparé

Le `render.yaml` à la racine décrit un service Docker **plan free**, avec clé générée. Le déploiement nécessite de connecter le propriétaire du dépôt à Render et de l’autoriser à lire le dépôt privé. Le plan gratuit peut se mettre en veille : son réveil peut dépasser le délai du lecteur. Les limites et l’offre gratuite de l’hébergeur doivent être vérifiées au moment de la connexion ; aucun paiement n’est configuré ici.

Un serveur annoncé « démarré » ne doit pas être branché comme source par défaut tant que **la lecture complète d’un titre signalé ne passe pas depuis cet hébergeur**. Les réseaux d’hébergement peuvent être bloqués par YouTube.

## État réel du fournisseur

Le diagnostic youtubei.js local sur Coup de tête ne télécharge pas le titre complet : IOS renvoie un échec HTTP, ANDROID_VR exige une connexion/confirmation, ANDROID ne fournit pas d’URL utilisable et ANDROID_MUSIC répond HTTP 400. **Ce service n’est donc pas une solution démontrée aux refus du fournisseur.** Les tests de protocole utilisent un média de test, et ne sont pas présentés comme des tests du catalogue.

```text
npm ci --ignore-scripts
npm test
# Définir BLUSIC_RELAY_KEY (24 caractères minimum), puis :
npm start
```

Ne pas committer `.env` ni la clé ; ne pas recopier des cookies personnels dans le service. Les journaux ne contiennent ni URLs signées ni clé de relais.
