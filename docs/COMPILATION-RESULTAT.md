# IPA Blusic réellement compilée

## Dernière livraison — 1.5.0

Voir **[RESULTAT-1.5.md](RESULTAT-1.5.md)** : compilation réussie, **51 tests passés**, barre système native, vue paroles testée, favoris corrigés et mesures réseau de **0,75 s à froid / 0,25 s préchargé** sur simulateur. IPA : `dist/github/40139429050/Blusic-unsigned.ipa` (35 356 625 octets, non signée).

## Version 1.1.0 — Invidious intégré et testé

- Exécution : https://github.com/certiitude/blusic-ios/actions/runs/40108900861
- Commit compilé : `cbba3f39902983b91f19859323ef232080641357`.
- Statut final : **success**, compilation Release iPhone **arm64**, Xcode **26.3**.
- **20 tests exécutés, 0 échec** sur iPhone Simulator.
- Le test réseau réel `testLiveInvidiousAACDecodesAndNativePlaybackAdvances` a réussi : recherche du clip officiel `KVpeHSX2ZEY`, récupération d’un **AAC à 130 544 bit/s**, décodage de **170,247 secondes**, signal PCM non silencieux (crête de l’échantillon contrôlé : **0,99575335**), progression du moteur natif, déplacement à 30 s et pause vérifiés.
- Ce test n’est ni une écoute humaine ni une validation de l’arrière-plan sur appareil physique. Il est distinct du simple contrôle des métadonnées effectué lors de la recherche initiale.

**Fichier : `dist/github/40108900861/Blusic-unsigned.ipa`**

- Taille : **35 116 809 octets**.
- Version : **1.1.0**, iOS minimum **17.0**, identifiant `app.blusic.ios`.
- Vérifications après téléchargement : Info.plist **iPhoneOS**, Mach-O **arm64** pour iOS physique, images compilées et quatre démos embarquées présentes.
- **IPA non signée**, à signer pour l’installation sur l’iPhone.

La version 1.1 utilise désormais Invidious sans clé Google pour le catalogue et la lecture audio native. La disponibilité dépend des instances et des contenus YouTube publics ; le flux AAC n’est pas lossless et il ne couvre pas automatiquement toutes les plateformes.

## Historique — version 1.0.0

- Dépôt **privé** autorisé : https://github.com/certiitude/blusic-ios
- Exécution : https://github.com/certiitude/blusic-ios/actions/runs/39665142579
- Commit compilé : `b6cd4f71ee93ac02e261280762901156be6e4eca`.
- Statut final GitHub Actions : **success**.
- Environnement : **macOS 15, Xcode 26.3 (17C529)**.
- Compilation Release pour appareil physique : **réussie**.
- Tests iPhone Simulator : **10 exécutés, 0 échec, `TEST SUCCEEDED`**.
- Il ne s’agit pas d’un test d’écoute manuel ni d’une validation complète de l’interface sur un appareil physique.

## Fichier récupéré sur le PC Windows

`dist/github/39665142579/Blusic-unsigned.ipa`

Contrôles effectués après téléchargement :

- Taille : **35 048 694 octets**.
- Identifiant : `app.blusic.ios`.
- Version : `1.0.0`.
- iOS minimum : **17.0**.
- Plateforme Info.plist : **iPhoneOS**.
- Exécutable : **Mach-O arm64**, plateforme iOS physique vérifiée dans `LC_BUILD_VERSION`.
- Catalogue d’images compilé et quatre fichiers audio présents.
- **Non signé** : aucune entrée `_CodeSignature/CodeResources` ; une signature de sideload reste nécessaire pour l’installation sur l’iPhone.

L’IPA est aussi disponible dans l’artefact **Blusic-iPhone-unsigned-needs-signing** de l’exécution GitHub, pendant sa durée de rétention.

## Catalogue musical : limite inchangée

La compilation initiale 1.0.0 utilisait le lecteur officiel YouTube. **La version 1.1.0 décrite en tête de ce rapport intègre Invidious et a passé son test de lecture native en réseau réel.** Aucune des deux versions ne promet un catalogue universel ou une source YouTube lossless.
