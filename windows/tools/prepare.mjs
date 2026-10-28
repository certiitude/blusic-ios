import {mkdir, copyFile, cp} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {dirname, resolve} from 'node:path';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '../..');
const out = resolve(root, 'windows');
await mkdir(resolve(out, 'vendor'), {recursive: true});
await mkdir(resolve(out, 'assets'), {recursive: true});
for (const name of ['provider.mjs', 'sabr.mjs', 'origin.mjs', 'guest-http.mjs', 'audio-quality.mjs']) {
  await copyFile(resolve(root, 'relay', name), resolve(out, 'vendor', name));
}
await cp(resolve(root, 'Blusic/Audio'), resolve(out, 'assets/audio'), {recursive: true});
for (const name of ['night', 'rain', 'orbit', 'metro']) {
  await copyFile(resolve(root, `Blusic/Assets.xcassets/cover-${name}.imageset/cover-${name}.png`), resolve(out, `assets/cover-${name}.png`));
}
await copyFile(resolve(root, 'docs/branding/soryn-icon.png'), resolve(out, 'assets/logo.png'));
await copyFile(resolve(root, 'docs/branding/soryn-mascot.png'), resolve(out, 'assets/mascot.png'));
await copyFile(resolve(root, 'docs/branding/soryn.ico'), resolve(out, 'assets/soryn.ico'));
await copyFile(resolve(root, 'LICENSE.md'), resolve(out, 'LICENSE.md'));
await copyFile(resolve(out, 'resources/PlusJakartaSans.ttf'), resolve(out, 'assets/PlusJakartaSans.ttf'));
await copyFile(resolve(out, 'resources/OFL-PlusJakartaSans.txt'), resolve(out, 'assets/OFL-PlusJakartaSans.txt'));
await copyFile(resolve(root, 'Blusic/ThirdPartyResolverLicenses.txt'), resolve(out, 'assets/ThirdPartyResolverLicenses.txt'));
console.log('Soryn: assets and embedded audio resolver prepared.');
