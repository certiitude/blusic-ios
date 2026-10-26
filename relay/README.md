# Relais Blusic youtubei.js

Service Node **22.22.2 minimum** / **youtubei.js 18.3.0**, destiné à relayer un AAC complet vérifié plutôt qu’exposer à l’iPhone une URL Google signée pour une autre IP. Le chemin WEB/SABR utilise GoogleVideo 5.0.1, BgUtils 4.0.3 et une attestation d’origine liée au titre dans un DOM isolé. La session invitée conserve uniquement ses propres cookies éphémères ; aucune connexion Google, aucun cookie de compte importé et aucune résolution de CAPTCHA.

- `GET /health` : état du serveur, **pas preuve de lecture**.
- `GET /v1/streams/<videoId>` avec un accès application dans `Authorization: Bearer …` : prépare le fichier complet et renvoie une URL temporaire du relais. L’accès application non expirant ne permet pas de signer de tickets ; la clé maître `BLUSIC_RELAY_KEY` reste côté serveur.
- `GET /v1/audio/<videoId>?ticket=…` : lecture et plages HTTP du fichier préparé. Une page HTML, un refus HTTP ou un fichier incomplet ne sont jamais considérés comme une réussite.
- Cache temporaire limité à 5 titres, 25 Mo par titre, 10 minutes ; aucun catalogue complet ni archive commerciale livrée avec le service.
- Deux préparations simultanées au maximum ; aucun quota d’écoutes ou de résolutions par minute ajouté par Blusic. Les limites de ressources et de trafic de l’hébergement gratuit s’appliquent. Pas de proxy d’URL arbitraire.

## Déploiement gratuit

Le `render.yaml` à la racine décrit un service Node **plan free**, avec clé générée ; un Dockerfile est également fourni. Le service autorisé par le propriétaire est déployé à `https://blusic-audio-relay.onrender.com`, région Frankfurt. Le plan gratuit peut se mettre en veille : son réveil peut dépasser le délai du lecteur. Aucun paiement n’est configuré ici.

Le relais est un secours préconfiguré derrière le moteur embarqué dans l’IPA. Un serveur annoncé « démarré » n’est pas une preuve de lecture : **la récupération complète d’un titre signalé doit passer depuis cet hébergeur**. Les réseaux d’hébergement peuvent être bloqués par YouTube.

## État réel du fournisseur

Le chemin SABR a récupéré des fichiers complets depuis le réseau du PC de diagnostic : FUTUR AMOUR (**2 687 251 octets**), Coup de tête (**2 311 731 octets**) et 21 rue de l’impasse (**3 162 998 octets**), en environ **7,4 à 7,8 secondes**, y compris avec l’hôte Innertube natif utilisé sur Render. Cela ne nécessite pas de serveur PC pour les utilisateurs : ce résultat décrit uniquement l’environnement de vérification.

Le déploiement `1b96265` est démarré sur Render, mais le test authentifié avec l’accès application de FUTUR AMOUR échoue encore : **HTTP 502 après 53,8 secondes**, avec refus amont **403** et expiration du secours. **Ce service n’est donc pas une solution démontrée aux refus depuis Render.** Les six tests de protocole/session utilisent des fixtures et ne remplacent pas les tests du catalogue.

```text
npm ci --ignore-scripts
npm test
# Définir BLUSIC_RELAY_KEY (24 caractères minimum), puis :
npm start
```

Ne pas committer `.env` ni la clé ; ne pas recopier des cookies personnels dans le service. Les journaux ne contiennent ni URLs signées ni clé de relais.
