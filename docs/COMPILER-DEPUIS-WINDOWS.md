# Compiler Blusic en .ipa depuis Windows

La compilation est pilotée depuis ton PC et exécutée sur un **Mac hébergé par GitHub Actions**. Aucun Mac personnel, serveur à louer ou SDK Apple à installer sous Windows n’est nécessaire.

## Ce qui est préparé

- Workflow `.github/workflows/ios.yml` : runner standard **macOS 15**, **Xcode 26.3**, cible physique **iPhone arm64**, Release, signature désactivée.
- Construction de la véritable app Xcode puis packaging en **`Payload/Blusic.app`**.
- Contrôle du fichier : Info.plist iPhoneOS, exécutable Mach-O arm64, plateforme iOS physique (pas Simulator), catalogue d’images compilé et quatre fichiers audio.
- Publication du fichier **`Blusic-unsigned.ipa`** comme artefact téléchargeable, conservé 7 jours.
- Exécution des tests sur un simulateur iPhone compatible après la production de l’IPA. Un échec des tests est signalé, même si le binaire a pu être construit.
- Utilitaire `tools/github_ipa.py` pour se connecter, lancer précisément une compilation et récupérer son IPA automatiquement dans `dist/github/<execution>/`.

## Connexion GitHub

Python 3 et Git sont déjà présents sur ce PC. La commande suivante utilise GitHub CLI officiel, téléchargé en version portable si nécessaire et vérifié par SHA-256 :

```powershell
python tools/github_ipa.py login
```

La page **https://github.com/login/device** te demande un code temporaire affiché par la CLI. Valide uniquement dans le navigateur. Aucun mot de passe Apple ou GitHub n’est nécessaire dans le chat ou le projet.

La connexion autorise la gestion du dépôt privé et des workflows. Le code doit être envoyé dans le dépôt GitHub autorisé avant de pouvoir être compilé. L’utilitaire ne crée pas de dépôt, ne fait pas de commit et n’envoie pas tes modifications automatiquement.

## Lancer et récupérer l’IPA

Une fois le dépôt privé créé et le projet envoyé :

```powershell
python tools/github_ipa.py build --repo TON-COMPTE/blusic-ios
```

Après configuration du dépôt Git local, tu peux aussi double-cliquer sur **`Compiler IPA.cmd`**. Le dépôt est alors détecté depuis le dossier du projet.

L’utilitaire :

1. Déclenche `ios.yml` sur la branche `main`, avec un identifiant de demande unique.
2. Retrouve exactement cette exécution et affiche son URL.
3. Suit les étapes Xcode et les tests.
4. Télécharge l’IPA produite dans `dist/github/<numéro>/Blusic-unsigned.ipa`.
5. Vérifie son architecture et ses ressources, puis affiche son chemin.

Il compile **le code présent sur GitHub**, pas les modifications locales non envoyées. En cas d’erreur de compilation, il affiche les logs et ne prétend pas avoir créé une IPA.

Tu peux également aller dans le dépôt : **Actions → Build and test Blusic iOS → Run workflow**, puis télécharger **Blusic-iPhone-unsigned-needs-signing** dans **Artifacts**. Décompresse l’archive de téléchargement pour obtenir le `.ipa` à l’intérieur.

## Installer l’IPA sur l’iPhone depuis Windows

Le fichier est une **vraie IPA compilée mais non signée**. Il faut la signer pour ton iPhone avant installation. **AltStore Classic pour Windows** peut signer et installer une IPA personnelle à l’aide de ton compte Apple ; la documentation officielle est ici :

- https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows
- https://altstore.io/

Avec AltServer/AltStore configurés, utilise l’import de l’IPA dans AltStore. Suis les instructions officielles concernant iTunes/iCloud et la connexion à l’iPhone. Le Mode développeur peut être nécessaire sur iOS. Les signatures gratuites doivent généralement être renouvelées tous les 7 jours ; ce n’est pas une publication App Store/TestFlight.

La compilation d’une IPA non signée ne demande **ni abonnement Apple Developer payant ni certificat Apple**. Le compte Apple intervient au moment de la signature/installation.

## Coût de la compilation distante

Selon la documentation GitHub vérifiée lors de la préparation : les runners standard sont gratuits pour les dépôts publics. Un dépôt **privé** utilise le quota Actions inclus dans le compte et les tarifs macOS applicables au-delà. Ce projet reste privé ; aucun paiement, moyen de paiement ou dépassement payant n’est activé automatiquement par les scripts.

Si le compte a épuisé ses minutes et ne permet pas les dépassements, GitHub bloquera l’exécution. Documentation : https://docs.github.com/en/billing/concepts/product-billing/github-actions
