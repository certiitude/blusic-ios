# Soryn iPhone 1.14 — radio personnalisée et AutoMix

Périmètre demandé : **radio personnalisée + AutoMix seulement, pas de mode DJ**.
Les versions précédentes des téléchargements et la normalisation sont conservées.

## Radio personnalisée

- Accueil → **Ta radio personnalisée**, ou menu d’un titre → **Lancer la radio**.
- Recommandations de la radio publique YouTube Music du morceau de départ.
  Seules les entrées audio ATV sont acceptées : les clips OMV ne sont pas un
  remplacement accepté. Le 17 novembre 2026, une requête réelle a renvoyé 48
  chansons ATV parmi 50 entrées pour Stephanie. Ce constat ne garantit pas
  la disponibilité audio de tous les titres ni la qualité d’une future réponse.
- Classement local : favoris et temps d’écoute, alternance d’artistes quand
  possible, identité canonique YouTube et exclusion des répétitions dans la session.
- Les titres passés tôt sont exclus de la session. **Moins de ce titre** conserve
  une exclusion locale persistante, réinitialisable depuis l’écran de radio.
- La file est alimentée par lots, sans compte obligatoire. Arrêter la radio ne
  coupe pas le morceau et ne supprime pas la file ; une sélection manuelle
  arrête la génération. Les réponses réseau tardives d’une radio arrêtée sont ignorées.
- En lecture hors ligne uniquement, aucun appel au catalogue radio : sélection
  parmi les morceaux locaux et téléchargés. Si le catalogue est indisponible,
  la bibliothèque locale sert de secours, explicitement indiqué.
- Quand les candidats uniques sont épuisés, Soryn l’indique plutôt que de
  répéter silencieusement les mêmes morceaux ou de prétendre découvrir du nouveau.

## AutoMix

**Réglages → Écoute → AutoMix**, également disponible dans les réglages du son
et sur l’écran de radio. Désactivé par défaut. Activation à partir des prochaines
lectures ; le réglage classique de fondu reste conservé, mais AutoMix a priorité.

Ce n’est pas un simple changement de nom du fondu :

1. Décodage natif en petits blocs, hors interface/rendu, sans réencodage ni
   modification du fichier. Analyse d’une enveloppe d’énergie de 10 ms.
2. Repérage des zones actives et estimation d’un tempo/grille par corrélation
   des transitoires. Les fichiers analysés sont mis en cache avec invalidation
   par taille/date/numéro de fichier.
3. Si les deux tempos ont une confiance suffisante et un écart ≤4 % (en
   considérant aussi les lectures moitié/double tempo), choix d’une sortie sur
   battement estimé et d’une entrée alignée. Chevauchement autour de 8 battements,
   borné de 3 à 8 secondes.
4. Adaptation temporaire du tempo entrant avec le time-pitch natif, sans
   changement de hauteur ; retour progressif au tempo normal après la transition.
5. Courbe de mélange lissée et normalisée (somme des gains ≤1). Volume utilisateur
   et normalisation par morceau restent indépendants.

Si les tempos sont incertains/éloignés, les morceaux trop courts ou les réglages
de vitesse/tonalité manuels actifs : fondu doux sans adaptation rythmique. Un
flux progressif doit être préparé en fichier complet ; si cela échoue, la lecture
continue avec un fondu simple et le lecteur l’indique. Boucle A–B, répétition d’un
seul titre, arrêt en fin de morceau et pause empêchent la transition automatique.

### Limites importantes

Approche inspirée du comportement d’AutoMix, **pas une copie ni une promesse
d’équivalence avec Apple Music**. Pas de séparation des voix, détection fiable
des phrases/refrains, analyse harmonique ni garantie de premier temps de mesure.
La grille est une estimation ; le déclenchement dépend du moteur natif et de
sa préparation, ce n’est pas une garantie de synchronisation parfaite à l’échantillon.
Les premières analyses peuvent augmenter le délai et consommer de la batterie.
Mono/stéréo 8–192 kHz, fichiers jusqu’à deux heures ; sinon secours simple.

## Validation

Suite Apple dédiée : classement/déduplication/exclusions radio, parser radio
avec faux réseau déterministe, alimentation/arrêt, mode hors ligne sans appel
catalogue et réponses tardives. AutoMix : signaux à impulsions connus, silence
sans BPM inventé, limites du plan, courbes de gain, analyse native Opus inchangée,
puis vrai chevauchement de deux fichiers natifs 120/118 BPM avec contrôle du
time-pitch et arrêt des deux lecteurs sur pause.

Les résultats de cette suite, de la suite Opus/hors ligne et des tests réseau
doivent être publiés séparément. Les contrôles statiques Windows ne constituent
pas une compilation Xcode ni une preuve d’exécution iPhone. Aucun iPhone physique
n’est disponible ici : validation Apple sur simulateur et IPA à signer.
