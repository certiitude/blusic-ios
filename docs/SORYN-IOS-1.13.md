# Soryn iPhone 1.13 — fiabilité et hors-ligne

## Correctif du rejet « paquets Opus »

Une ancienne sauvegarde pouvait refuser un vrai fichier Opus déjà décodable :
elle lisait le pointeur `streamDescription` d’un `AVAudioFormat` temporaire. Le
format lu pouvait ne plus être celui du fichier. Une première correction de
durée de vie a permis le test Opus normalisé hors ligne, mais ne centralisait
pas les autres vérifications.

Le nouveau `NativeAudioInspection` copie maintenant les propriétés du fichier
avec **AudioFileGetProperty** dans des valeurs possédées. Résolveur, cache,
lecture et téléchargements partagent cette identification. Pour Opus, on vérifie
aussi qu’il existe des paquets et que le décodeur Apple lit le début, le milieu
et la fin. Aucune confiance dans la seule extension `.caf` ou dans une étiquette
« Opus » ; un AAC déguisé reste rejeté. Aucun encodeur ajouté.

Un test natif parcourt 12 fois la chaîne complète : spool → cache → sauvegarde
persistante → redémarrage du stockage, en comparant les octets CAF originaux.
Les résultats réels de CI sont nécessaires avant de déclarer le correctif validé.

## Changements utilisables

- Recherche par titre/artiste dans les téléchargements, filtres Opus/AAC,
  classement alphabétique ou par date.
- Nombre de titres uniques séparé du nombre de fichiers : AAC + Opus du même
  morceau ne compte plus comme deux chansons. File de lecture sans doublons.
- Relance de tous les échecs et maintien du format demandé au moment de l’ajout,
  même si le réglage global change entre-temps.
- File de téléchargements en attente conservée localement après fermeture :
  bouton **Reprendre la file**, jamais de relance réseau automatique à l’ouverture.
  Une requête interrompue recommence sa préparation ; ce n’est pas une reprise
  des octets partiellement reçus ni une extension de téléchargement en arrière-plan.
- **Vérifier les téléchargements** détecte fichiers absents, taille modifiée,
  format incompatible et Opus indécodable aux positions contrôlées. **Réparer**
  retélécharge la variante sans supprimer préalablement le fichier et sans
  écraser l’autre variante valide. Ce contrôle n’est pas un hash d’intégrité
  intégral ni une preuve que chaque seconde d’un fichier est sans défaut.
- Les fichiers manquants restent visibles pour réparation, plutôt que de
  disparaître silencieusement du catalogue local.
- **Lecture hors ligne uniquement** : aucune nouvelle résolution ou préparation
  réseau audio, y compris le préchargement. Recherche, pochettes et comptes sont
  indépendants ; les téléchargements manuels restent possibles.
- Le secours AAC enregistré est indiqué explicitement. Un AAC existant reste
  conservé si une nouvelle tentative Opus ne peut obtenir qu’un AAC.
- Annuler puis réessayer immédiatement un téléchargement ne permet plus aux
  callbacks de l’ancien essai d’effacer l’état du nouveau.

## Normalisation et validation

Le cache d’analyse lit désormais les attributs actuels du fichier à chaque appel
(taille, date et numéro de fichier), sans réutiliser les métadonnées mémorisées
d’un objet URL. Cela corrige une analyse périmée après modification du fichier.
Le test avec silence est comparé à la référence indépendante ebur128 −20,3 LUFS,
qui inclut les blocs de 400 ms partiellement silencieux aux frontières.

Les tests déterministes, l’intégration comptes locale et les essais réseau
externes doivent être distingués. Un test réseau strict Opus ne peut pas réussir
en jouant un secours AAC. Les sources peuvent encore refuser certains morceaux.
Le 17 novembre 2026, le diagnostic Node/SABR a récupéré de nouveau Stephanie
en entier : 1 867 477 octets WebM, 6 349 paquets, 126,969 s, 114 826 bit/s audio
moyen. Ce contrôle réseau Node n’est pas à lui seul une preuve de lecture iPhone.

## Mettre à jour

Même identifiant `app.blusic.ios`, mêmes dossiers de bibliothèque et téléchargements,
champs Codable nouveaux facultatifs. **Ne pas désinstaller l’ancienne app** pour
la mettre à jour ; conserver la même signature et sauvegarder avant réinstallation.
IPA iOS 17+, non signée, nécessitant une signature Apple. Aucun iPhone physique
disponible dans cet environnement ; validation native via simulateur macOS.

## Priorités suivantes (pas des fonctions déjà livrées)

« 100× mieux » n’est pas une mesure que l’on peut promettre. La suite utile :
mesurer le délai de premier son/cache, limiter le coût batterie des analyses,
ajouter des tests d’interface pour les parcours recherche → écoute → hors ligne,
puis améliorer la découverte et l’accessibilité sans ajouter de dépendance payante.
