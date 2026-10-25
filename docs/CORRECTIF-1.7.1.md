# Correctif iOS 1.7.1 — refus du lecteur progressif et HTTP 403

Les nouvelles captures signalent deux étapes distinctes : le premier contrôle URLSession reçoit un en-tête M4A valide, mais AVPlayer refuse ensuite le flux distant (« erreur inconnue »), puis l’instance de secours renvoie HTTP 403 ou une page HTML. Les exemples comprennent Coup de tête (Luv0), jolie cicatrice et 21 rue de l’impasse.

## Modifications

- Diagnostic réel sur Coup de tête : `Range: bytes=0-` renvoie HTTP 403 ; `Range: bytes=0-262143` renvoie HTTP 206 avec 262 144 octets et une taille totale de 2 311 731 octets. Le chargement du fichier est donc assemblé par plages finies de 256 Ko, avec vérification de Content-Range, taille totale et continuité, avant décodage.
- **Le diagnostic du fichier complet échoue encore sur des plages suivantes (HTTP 403)** pour Coup de tête, jolie cicatrice et 21 rue de l’impasse depuis ce PC. Le mode `range` en paramètre de requête employé par youtubei.js a également été essayé, sans réussite du fichier complet. Le correctif ne prétend donc pas rendre ces morceaux accessibles : la validation est renforcée avec une seconde plage, afin de ne plus accepter le seul en-tête initial comme preuve de disponibilité.

- Avant d’abandonner une source validée parce qu’AVPlayer la refuse, essai du **fichier audio complet via URLSession**, puis validation AVAudioFile et lecture dans le moteur natif. Ce chemin de secours est limité à 8 secondes et au délai global de démarrage de 20 secondes ; il reste annulable.
- Au plus un essai de fichier par adresse et deux adresses par lecture. Un échec ne crée pas une boucle de relance.
- Les URL de flux d’une lecture complètement échouée sont invalidées ; Réessayer doit obtenir une nouvelle résolution, pas réutiliser une adresse défaillante pendant 120 secondes.
- Une réponse HTTP 403 ou HTML n’est pas acceptée comme de l’audio. Les refus de connexion du fournisseur ne sont pas contournés.
- Le domaine et le code de l’erreur AVFoundation sont conservés dans le diagnostic ; les URL signées et leurs paramètres ne sont pas affichés.

## Vérifications prévues

- Lecteur progressif simulé indisponible, fichier local original valide, autre fournisseur indisponible : la musique doit démarrer grâce au fichier, puis permettre un déplacement.
- Annulation pendant la préparation : aucun redémarrage ultérieur.
- HTTP 403 lors du contrôle média : échec conservé, pas de mise en cache ; la tentative suivante obtient une URL fraîche. Invalidation explicite également testée.
- Compilation et suite iPhone Simulator à exécuter. Ces tests contrôlés ne prouvent pas que tous les contenus tiers sont accessibles depuis l’iPhone physique.
