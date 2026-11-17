# Fond rythmé — Soryn iPhone 1.14.1

Le fond du **lecteur développé**, y compris l’écran de paroles, réagit au signal
audio natif réellement rendu. Pas de battements aléatoires, de minuterie simulant
la musique, d’accès au microphone ni de service distant.

## Effet visuel

- Intensité globale, basses (filtre passe-bas à 160 Hz) et attaques graves.
- Zoom/déplacement doux du fond flouté et légère teinte de la couleur d’accent.
- Intensité réglable dans **Réglages → Ton univers** ou les réglages du son.
  Activé par défaut à 50 %, indépendamment des animations de pochette.
- À 100 %, zoom supplémentaire ≤5 %, déplacement ≤16 px horizontal/10 px vertical
  et variation de teinte ≤4 %. Lissage, décroissance et intervalle entre attaques
  évitent des changements secs ; le texte garde son dégradé sombre stable.
- « Réduire les animations », pause, volume nul, intensité nulle, fermeture du
  lecteur et passage en arrière-plan suspendent l’animation et retirent les taps.

## Audio et performance

Un tap en lecture seule sur le mixeur natif analyse de petits blocs PCM. Il ne
change ni les échantillons ni le gain ni les fichiers téléchargés. Le callback
ne fait pas d’appel réseau, de travail d’interface ou de décodage de fichier.
Une prise de verrou non bloquante permet de perdre une mesure plutôt que de
faire attendre le rendu audio. Le fond seul se redessine au maximum à 24 Hz :
ni les paroles ni les commandes du lecteur n’observent des valeurs audio à 24 Hz.

Pendant un fondu/AutoMix, le lecteur sortant conserve son propre capteur et le
fond suit le plus fort des deux signaux mesurés. Les taps sont retirés avant une
reconfiguration du graphe, puis recréés sur le nouveau mixeur, sans doublon.

Opus/CAF, AAC préparé, téléchargements et fichiers locaux lisibles nativement
sont pris en charge. **Un flux AVPlayer progressif non préparé garde un fond fixe** :
on ne remplace pas une vraie mesure par des mouvements fictifs. Dans les réglages
du son, « Préparer les effets et le fond rythmé » prépare explicitement le fichier
complet ; l’animation ne provoque pas à elle seule un téléchargement supplémentaire.
Le lecteur vidéo officiel n’est pas analysé.

## Vérifications

Suite native dédiée : graves/aigus de même amplitude, PCM inchangé, silence,
mesures périmées, remise à zéro, bornes visuelles, réduction des animations,
lecture Opus hors ligne avec mesure réelle du rendu, pause/reprise et retrait
du tap sans arrêt de la musique. Le test d’AutoMix vérifie aussi que le signal
reste mesuré pendant le chevauchement et que la pause retire les capteurs.

La CI Apple est nécessaire pour confirmer l’exécution. Les seuls contrôles
syntaxiques Windows ne prouvent pas le rendu iPhone ; aucune capture statique
ne constitue à elle seule une preuve de synchronisation avec la musique.
