# Fond rythmé — correctif des flux progressifs, Soryn iPhone 1.15

Le fond du **lecteur développé**, y compris l’écran de paroles, réagit au signal
audio natif réellement rendu. Pas de battements aléatoires, de minuterie simulant
la musique, d’accès au microphone ni de service distant.

## Effet visuel

- Intensité globale, basses (filtre passe-bas à 160 Hz) et attaques graves.
- Zoom/déplacement doux du fond flouté et légère teinte de la couleur d’accent.
- Intensité réglable dans **Réglages → Ton univers** ou les réglages du son.
  Activé par défaut à 50 %, indépendamment des animations de pochette.
- À 100 %, zoom supplémentaire ≤10 %, déplacement ≤34 px horizontal/26 px vertical,
  rotation ≤2° et variation d’opacité ≤8 %. La modulation utilise les couleurs de
  la pochette, et non plus une teinte d’accent qui pouvait masquer le mouvement.
  Lissage, décroissance et intervalle entre attaques
  évitent des changements secs ; le texte garde son dégradé sombre stable.
- « Réduire les animations », pause, volume nul, intensité nulle, fermeture du
  lecteur et passage en arrière-plan suspendent l’animation et l’analyse.
  Les taps AVAudioEngine sont retirés ; sur AVPlayer, le tap reste installé mais
  ne calcule plus d’énergie, afin de ne pas reconfigurer le son à chaque pause.

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
sont pris en charge. **Les fichiers HTTP progressifs lus par AVPlayer sont
maintenant analysés aussi**, avec `MTAudioProcessingTap` dans un `AVAudioMix`.
Le callback restitue directement les buffers source d’Apple, sans les modifier.
Il accepte le PCM entrelacé et non entrelacé ; aucun second lecteur ni
téléchargement du fichier complet n’est créé pour l’animation.

AVPlayer peut décoder à l’avance : les mesures de blocs de 1024 échantillons sont
placées dans un tampon circulaire préalloué, avec leur temps de présentation.
Le fond choisit la mesure correspondant à `currentTime`, pas au moment où le
décodage en avance a eu lieu. Les images futures ne battent donc pas avant le son.

Le lecteur vidéo officiel, HLS et les médias protégés ne sont pas analysés par
ce chemin. Un flux qui n’expose pas de PCM garde un fond fixe avec un message
dans les détails audio. Ce n’est pas un métronome ni une détection garantie de
chaque temps musical : l’effet suit les basses, l’énergie et les attaques mesurées.

## Vérifications

Suite native dédiée : graves/aigus de même amplitude, PCM inchangé, silence,
mesures périmées, remise à zéro, bornes visuelles, réduction des animations,
lecture Opus hors ligne avec mesure réelle du rendu, pause/reprise et retrait
du tap sans arrêt de la musique. Le test d’AutoMix vérifie aussi que le signal
reste mesuré pendant le chevauchement et que la pause retire les capteurs.

Quatre tests supplémentaires couvrent le PCM entrelacé inchangé, le choix par
temps de présentation malgré le décodage anticipé, un vrai AAC HTTP progressif
lu par AVPlayer (sans préparation de fichier) et un WAV HTTP à impulsions : le
test exige un mouvement de fond qui varie pendant la lecture réelle. Le serveur
de test écoute uniquement en boucle locale et sert des données de démonstration,
sans faire appel au catalogue. Il ne fait pas partie de l’app distribuée.

La CI Apple est nécessaire pour confirmer l’exécution. Les seuls contrôles
syntaxiques Windows ne prouvent pas le rendu iPhone ; aucune capture statique
ne constitue à elle seule une preuve de synchronisation avec la musique.
