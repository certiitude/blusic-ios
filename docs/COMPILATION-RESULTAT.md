# IPA Blusic réellement compilée

## Exécution vérifiée

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

Cette compilation prouve que le projet produit une application iPhone. Elle ne transforme pas la bibliothèque de démonstration en catalogue commercial universel. L’IPA comprend les imports personnels et l’intégration officielle YouTube décrite dans le README. Les pistes d’autres sources gratuites figurent dans `API-MUSICALES.md` et ne sont pas encore intégrées.
