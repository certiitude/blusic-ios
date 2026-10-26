# Blusic 1.9.1 — Audio haute qualité

## Formats réellement proposés

Inspection anonyme youtubei.js 18.3.0, client WEB, sans compte ni abonnement importé :

| Titre | AAC proposé | Opus proposé (maximum annoncé) |
|---|---:|---:|
| FUTUR AMOUR | 131 042 bit/s | 154 935 bit/s |
| Coup de tête | 131 180 bit/s | 144 832 bit/s |
| 21 rue de l’impasse | 131 342 bit/s | 135 316 bit/s |
| Stephanie | 131 662 bit/s | 129 490 bit/s |

Il s’agit des débits `bitrate` annoncés, pas d’une mesure constante de chaque seconde du fichier ; les débits moyens peuvent être inférieurs. **Aucun AAC 256 kbit/s n’a été proposé pour ces quatre titres avec cet accès.** Un débit supérieur entre deux codecs ne prouve pas à lui seul une meilleure qualité audible. Opus/WebM n’est pas activé dans cette version : son décodage par le chemin AVAudioFile utilisé par Blusic n’est pas validé.

Le diagnostic complet en mode haute qualité a récupéré FUTUR AMOUR (**2 687 251 octets, 131 042 bit/s, 7,65 s**) et Coup de tête (**2 311 731 octets, 131 180 bit/s, 8,26 s**) depuis le PC de vérification. Le mode conserve donc le meilleur AAC disponible sans inventer un débit supérieur. Ce diagnostic Node ne constitue pas un test de lecture depuis le réseau de l’iPhone.

Reproduction : `node tools/probe_audio_quality.mjs <chemin-absolu-vers-relay> qMAzmGNeDxc rdpuziaOHJI Cy0Gz0PZzNA RFzfXv9wzfo` ; puis `node relay/diagnose.mjs qMAzmGNeDxc --high-quality` après installation des dépendances du relais.

## Réglage

- **Réglages → Qualité audio → Audio haute qualité**, désactivé par défaut pour conserver le comportement standard.
- Standard : AAC usuel autour de 128 kbit/s (plafond de sélection de 160 000 bit/s pour tenir compte du débit maximal annoncé). Si le seul AAC dépasse ce plafond, il reste utilisable.
- Haute qualité : meilleur débit AAC réellement proposé et compatible, y compris un AAC supérieur à 160 kbit/s s’il est disponible. Aucun format Premium n’est créé ou déverrouillé par ce réglage.
- Pas de réencodage ni de suréchantillonnage. Le débit affiché par le lecteur reste celui de la source obtenue.
- Réglage persistant, compatible avec les anciennes bibliothèques ; appliqué aux prochaines lectures et à la préparation du suivant sans interrompre le titre actuel.
- Caches fichier, URL et préparation séparés par qualité : un ancien téléchargement standard ne masque pas une nouvelle résolution haute qualité.
- Le paramètre est transmis au moteur embarqué, au relais youtubei.js, à l’accès direct et au secours Invidious. Les tickets média du relais sont liés à la qualité demandée ; l’ancien protocole standard reste compatible.

## Vérification

Les tests couvrent la sélection d’un AAC supérieur lorsqu’il est réellement offert (fixture), le repli au débit existant sans fausse promesse, la conservation du lecteur natif, la transmission du paramètre au relais, l’isolation des caches et la nouvelle préparation du suivant après changement de qualité. Les résultats Xcode et l’IPA seront ajoutés après compilation.
