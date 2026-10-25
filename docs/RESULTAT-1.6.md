# Blusic 1.6.0 — sources audio et paroles

## Diagnostic local

- Titre signalé : **Damso — Dieu ne ment jamais**, identifiant `-WXpT4Ej2No`.
- L’instance initiale renvoie HTTP 500 pour ce titre. Les alternatives essayées renvoient DNS introuvable, HTTP 401/403/502 ; aucune instance française fonctionnelle validée.
- Test youtubei.js 18.3.0 : client IOS utilisable, AAC 131 055 bit/s, lecture HTTP 206 des 4 096 premiers octets en environ 0,8 s sur le PC Windows. Le client WEB n’a pas fourni d’URL utilisable dans ce test.
- La même requête iOS minimale, reproduite sans Node : HTTP 206, en-tête MP4 `ftyp` présent, 4 096 octets reçus, environ **0,22 s** sur ce PC. Cette mesure inclut métadonnées et premiers octets, **pas le démarrage AVPlayer sur iPhone**.
- Aucun jeton de connexion, cookie de compte, déchiffrement de formats protégés ou serveur Node n’est ajouté à l’app. L’accès reste non officiel et peut devenir indisponible.

## Modifications

- Nouvelle source directe native `DirectAudioService`, sélection automatique avec le relais Invidious, validation courte du fichier avant sélection, annulation des perdants.
- Choix de source persistant optionnel pour garder les anciennes bibliothèques lisibles.
- Erreurs réseau/HTML/JSON distinguées ; formats AAC incomplets ignorés ; délais réduits.
- Vue paroles dédiée sur la hauteur disponible, animations et centrage, suspension du suivi pendant une lecture manuelle, bouton Recentrer, respect de Réduire les animations.
- Captures prévues sur grand iPhone et iPhone SE, avec paroles originales de démonstration.

## Vérifications

- Contrôles locaux de syntaxe et ressources : réussis, **21 fichiers Swift**, sans prétendre à une compilation Xcode.
- Première exécution : https://github.com/certiitude/blusic-ios/actions/runs/40206073868 — compilation iPhone arm64 réussie ; **54 tests passés et 2 tests échoués sur 56**, aucun ignoré. Les échecs de lecture concernent Damso et Salé : YouTube exige une confirmation anti-robot depuis le réseau du runner ; le relais renvoie HTTP 500. Le test préchargé Réseaux passe (premier avancement : environ 0,25 s). Les contrôles du secours HTTP 403 et du mode direct passent.
- Paroles : captures grand iPhone et iPhone SE inspectées, grand texte lisible et commandes présentes ; test de la vue SwiftUI réelle récupérant automatiquement 46 lignes LRCLIB réussi.
- L’IPA de cette première exécution conservait une étiquette de version 1.5.0 : correction du plist pour suivre les variables Xcode, avec contrôle statique empêchant cette divergence à l’avenir. **Ce fichier intermédiaire n’est pas la livraison finale.**
- Nouvelle compilation avec version corrigée : https://github.com/certiitude/blusic-ios/actions/runs/40207059244 — IPA 1.6.0 arm64 compilée ; **55 tests passés et 2 échoués sur 57**, aucun ignoré. Les deux échecs réseau restent visibles. La version suivante et ses résultats sont décrits dans [le rapport 1.7](PERFORMANCES-1.7.md).
- Aucun test sur l’iPhone physique de l’utilisateur réalisé depuis ce poste.
