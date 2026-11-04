# Comptes facultatifs Soryn

Soryn reste utilisable sans connexion : écoute, imports, bibliothèque locale et téléchargements ne nécessitent aucun compte. La synchronisation Wi-Fi sans compte reste disponible.

Le compte pseudo/mot de passe permet de fusionner les références de titres, playlists, favoris, artistes suivis, paroles sauvegardées et historique entre appareils sur Internet. Les octets audio, chemins de fichiers privés, réglages et lecture en cours restent locaux. Déconnexion et suppression du compte conservent la bibliothèque locale. Sans e-mail, aucune récupération automatique du mot de passe n'est proposée.

## Sécurité et persistance

- Serveur dédié Node/PostgreSQL, base Supabase séparée du projet préexistant.
- Requêtes SQL paramétrées, mots de passe scrypt salés, jetons aléatoires de 30 jours stockés uniquement hachés en base.
- Session protégée par Windows DPAPI / trousseau iOS ; aucun mot de passe utilisateur, accès PostgreSQL ou clé d'administration embarqué dans les applications.
- HTTPS côté clients ; TLS avec certificat et nom d'hôte vérifiés vers le pooler IPv4 Supabase. Le certificat CA public est inclus côté serveur uniquement.
- RLS activé et droits PUBLIC/anon/authenticated retirés des quatre tables Soryn. Data API désactivée. Le backend autorise chaque opération à partir du compte de la session, jamais d'un identifiant de compte fourni par le client.
- Fusion à trois états par appareil avec accusé de réception : une réponse perdue n'efface pas les ajouts jamais reçus. Les UUID Swift en majuscules et PostgreSQL en minuscules sont rapprochés correctement.
- Le serveur conserve les métadonnées : **ce n'est pas du chiffrement de bout en bout**.

## Hébergement gratuit

Le service utilise Render gratuit et Supabase gratuit, sans abonnement payant autorisé. Soryn n'ajoute pas de quota d'écoute ni de date d'expiration de l'application. Les limites et politiques des hébergeurs s'appliquent néanmoins : sommeil à froid Render, heures gratuites partagées entre services, mise en pause éventuelle Supabase, stockage et trafic gratuits limités. Une disponibilité permanente ou illimitée ne peut donc pas être garantie. Les sessions expirent après 30 jours et nécessitent une reconnexion ; la bibliothèque locale reste utilisable.

## Tests reproductibles

```powershell
cd account-server
npm ci
npm test
```

La suite utilise le vrai moteur PostgreSQL embarqué PGlite, de vrais échanges HTTP et deux clients Windows, avec stockage sécurisé injecté pour les tests uniquement. `SORYN_TEST_DATABASE_PRIVATE` permet au test `clients.test.mjs` de vérifier aussi une base PostgreSQL réelle en utilisant un fichier privé hors dépôt ; seuls ses comptes de test sont supprimés.

`account-server/test/ios-server.mjs` expose une fixture locale utilisée par le test natif Swift `testSorynOptionalAccountTwoDevicesAndLocalPreservation` et par `windows/tools/account-ui-check.mjs`. Ce dernier ouvre le vrai Electron avec un profil isolé et le vrai stockage DPAPI Windows. Aucun profil personnel ni fichier audio de l'utilisateur n'est modifié.
