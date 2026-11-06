# Normalisation audio — Soryn iPhone

**Réglages → Écoute → Normalisation audio**, ou dans l’écran des réglages du son.
Option désactivée par défaut pour conserver le volume des installations existantes.
L’activation prend effet au prochain titre ; la désactivation retire immédiatement
le gain, y compris sur le titre sortant d’un fondu.

## Traitement

- Analyse native de tout le fichier mono/stéréo en PCM Float32, hors du fil de
  l’interface et du rendu audio, par petits blocs et avec annulation.
- Pondération K BS.1770, blocs 400 ms et pas 100 ms, portes −70 LUFS et −10 LU
  relatives. Un fichier plus court que 400 ms utilise son énergie pondérée complète.
- Cible **−16 LUFS par titre**, amplification maximale **+12 dB**. Le gain est
  réduit si nécessaire pour laisser **2 dB de marge sur les crêtes échantillonnées**.
  Ce n’est pas un limiteur true-peak suréchantillonné certifié ; une cible n’est
  pas atteinte si la marge de crête ou la limite d’amplification l’interdit.
- Gain constant à la lecture, avant égaliseur/vitesse/tonalité, indépendant du
  volume choisi par l’utilisateur et de l’enveloppe de fondu. Pas d’AGC, pas de
  compression de dynamique, pas de réencodage, pas de modification des téléchargements.
- Résultats mémorisés dans un cache local purgeable, invalidé quand le chemin,
  la taille ou la date de modification du fichier change. Aucune analyse envoyée
  au compte ou à un serveur.

Opus/CAF, AAC, fichiers personnels et téléchargements utilisent le même moteur.
Un flux progressif est d’abord préparé en fichier complet ; la première lecture
peut donc être plus longue. Les titres suivants déjà préchargés sont aussi analysés.
Si la préparation ou l’analyse est impossible, la lecture reste disponible au
volume d’origine et l’écran du son indique que la normalisation est indisponible.
Les lectures via le lecteur vidéo officiel ne sont pas traitées.

## Vérifications automatisées

Tests natifs dédiés : signal de référence 1 kHz à 44,1/48 kHz (−20 LUFS stéréo,
confirmé indépendamment avec FFmpeg ebur128, outil de test uniquement), pondération
mono/stéréo, silence et passages calmes exclus par les portes, rapprochement de
deux niveaux, plafond de gain et de crête, cache et fichier modifié, annulation,
lecture/seek Opus hors ligne sans appel réseau, préparation AAC et désactivation.
Les tests de fondu existants sont également rejoués. Un contrôle statique Windows
ne remplace pas ces tests Apple : leurs résultats figurent séparément dans la CI.
