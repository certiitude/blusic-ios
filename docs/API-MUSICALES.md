# Recherche d’une source musicale pour Blusic

## Demande

API gratuite, morceaux complets, très bonne qualité si possible lossless, sans publicité, avec les titres commerciaux disponibles sur les grandes plateformes.

## Conclusion

Aucune offre vérifiée ne garantit simultanément un catalogue universel, l’écoute gratuite sans publicité et le lossless. Le fait qu’une API permette de rechercher des métadonnées n’implique pas qu’elle donne accès à l’audio complet.

La piste communautaire la plus proche vérifiée ici pour un grand catalogue sans clé Google est **Invidious**, basé sur le catalogue YouTube public. **Jamendo** propose explicitement du **FLAC**, mais sur son propre catalogue de musique indépendante.

## Invidious : vérification effectuée

- Documentation : https://docs.invidious.io/api/
- Liste du projet : https://docs.invidious.io/instances/
- API de disponibilité : https://api.invidious.io/
- Instance communautaire évaluée : `https://yt.chocolatemoo53.com` (API activée dans la liste au moment du test).
- Une recherche `GET /api/v1/search?q=Niska%20Sal%C3%A9&type=video` a renvoyé le clip officiel « Niska - Salé » et son identifiant `KVpeHSX2ZEY`.
- `GET /api/v1/videos/KVpeHSX2ZEY` a renvoyé une durée de 170 secondes et des formats audio, dont **AAC à 130 544 bit/s / 44,1 kHz / stéréo** et **Opus à 153 666 bit/s / 48 kHz / stéréo**.
- Ce sont des flux **avec pertes**, pas du FLAC et pas une garantie de débit pour tous les morceaux.
- Le test vérifie la recherche et les métadonnées des flux ; **aucun test d’écoute de ces flux dans Blusic ou sur iPhone n’a encore été effectué**.
- Une autre instance, `invidious.nerdvpn.de`, a répondu **HTTP 401** au même type de recherche. Les instances publiques ne sont donc pas interchangeables ni garanties.
- Le projet impose l’absence de publicité à ses instances publiques listées, mais signale également des problèmes de blocage par YouTube.

**Périmètre :** contenus publics accessibles sur YouTube selon la région et la disponibilité. Ce n’est pas un accès aux bibliothèques privées Spotify/Apple Music, ni une garantie de retrouver chaque titre de ces services.

**État du code :** Invidious est intégré dans la version **1.1.0** : recherche sans clé, import de playlists, résolution des flux et lecture AAC native. La compilation et les essais de cette version sont suivis séparément de la compilation initiale 1.0.0.

## Jamendo : FLAC documenté, catalogue indépendant

- API : https://developer.jamendo.com/v3.0/tracks
- Formats documentés : `mp31`, `mp32` (VBR), `ogg`, **`flac`**, via `audioformat`.
- Client ID requis ; usage gratuit non commercial dans les conditions publiées.
- Catalogue Jamendo indépendant, pas les catalogues complets des majors et autres plateformes.
- Les licences, autorisations de téléchargement et disponibilités doivent être suivies par morceau.
- Documentation des conditions : https://devportal.jamendo.com/api_terms_of_use

Le support de FLAC est documenté ; aucun accès client Jamendo n’a été créé et aucun flux FLAC Jamendo n’a été testé pendant cette recherche.

## Autres offres vérifiées

| Offre | Constat |
| --- | --- |
| Audius | API ouverte pour rechercher et écouter son propre catalogue. Ne constitue pas un catalogue commercial universel ; qualité à vérifier selon les contenus. https://docs.audius.org/ |
| YouTube Music | L’aide Google indique jusqu’à 256 kbit/s AAC/Opus pour la qualité élevée Premium. Pas une source lossless. https://support.google.com/youtubemusic/answer/9076559?hl=fr |
| Apple Music / MusicKit | Intégration officielle d’un vaste catalogue ; abonnement utilisateur requis pour la lecture du catalogue. Le service Apple Music propose le lossless, sans que cela donne des URL FLAC libres à réutiliser dans un autre moteur. https://developer.apple.com/musickit/ |
| Spotify Web Playback SDK | Nécessite un abonnement Premium. Une API de catalogue gratuite ne fournit pas l’écoute gratuite illimitée. https://developer.spotify.com/documentation/web-playback-sdk |
| Relais communautaires de services Hi-Fi | Certains projets nécessitent des identifiants et un refresh token du service amont. Leur existence ne démontre pas un accès gratuit autonome et universel. Aucun accès à un flux protégé n’a été tenté. |
| API JioSaavn publiques essayées | `saavn.dev` était injoignable depuis l’outil de recherche ; l’endpoint testé sur `jiosaavn-api.vercel.app` a répondu 404. Aucune qualité ni disponibilité de catalogue n’a été validée. |

## Choix technique possible

Pour viser un grand catalogue gratuit, **évaluer Invidious avec les vrais morceaux souhaités et des essais de lecture iPhone**, afficher le codec/débit réellement fournis et prévoir une adresse de service modifiable. Ne pas afficher une étiquette « Lossless » sur une source AAC/Opus, même après conversion en WAV/FLAC.

Pour le FLAC gratuit, proposer Jamendo comme catalogue indépendant complémentaire ou utiliser les fichiers sans perte personnels. Cela ne remplace pas une offre commerciale universelle.
