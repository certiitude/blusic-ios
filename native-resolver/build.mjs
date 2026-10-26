import {build} from 'esbuild';
import {readFile,writeFile,readdir} from 'node:fs/promises';
import {join} from 'node:path';

await build({entryPoints:['resolver.mjs'],bundle:true,platform:'browser',format:'iife',target:'safari17',outfile:'../Blusic/YouTubeiResolver.js'});
const manifest=JSON.parse(await readFile('package.json','utf8'));
const visited=new Set(),notices=['Blusic youtubei.js/SABR resolver — third-party software notices.\n'];
async function collect(name){
  if(visited.has(name))return;visited.add(name);
  const root=join('node_modules',name),pkg=JSON.parse(await readFile(join(root,'package.json'),'utf8'));
  notices.push(`\n=== ${name} ${pkg.version} (${pkg.license || 'see license'}) ===\n`);
  const files=(await readdir(root)).filter(file=>/^(licen[sc]e|copying|notice)(\..*)?$/i.test(file));
  for(const file of files)notices.push(await readFile(join(root,file),'utf8'));
  if(!files.length && name==='@bufbuild/protobuf'){
    // This npm package includes only dist/, so recover its license from the
    // exact matching upstream release and retain the embedded BSD notice.
    const response=await fetch(`https://raw.githubusercontent.com/bufbuild/protobuf-es/v${pkg.version}/LICENSE`);
    if(!response.ok)throw Error('Cannot retrieve matching protobuf license');
    const license=await response.text();if(!license.includes('Apache License'))throw Error('Unexpected protobuf license');
    notices.push(license);
    const varint=await readFile(join(root,'dist/esm/wire/varint.js'),'utf8');
    notices.push(varint.split('/**')[0]);
  }else if(!files.length)throw Error(`Missing third-party license for ${name}`);
  for(const dependency of Object.keys(pkg.dependencies||{}))await collect(dependency);
}
for(const name of Object.keys(manifest.dependencies))await collect(name);
await writeFile('../Blusic/ThirdPartyResolverLicenses.txt',notices.join('\n'));
console.log(`Packaged resolver and ${visited.size} third-party notices`);
