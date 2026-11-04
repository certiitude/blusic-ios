import {extractFile,listPackage} from '@electron/asar';
import {readFile,readdir,writeFile,mkdir} from 'node:fs/promises';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
import {relayConfiguration} from '../core/online-audio.mjs';
const archive=resolve(process.argv[2]||'../dist/windows-soryn/win-unpacked/resources/app.asar'),mismatches=[];
async function verify(path){const source=await readFile(path),packed=extractFile(archive,path.replaceAll('\\','/'));if(!source.equals(packed))mismatches.push(path);}
for(const path of ['main.mjs','preload.cjs'])await verify(path);
for(const folder of ['core','ui','vendor'])for(const name of await readdir(folder))await verify(join(folder,name));
const config=relayConfiguration(JSON.parse(extractFile(archive,'assets/relay-config.json').toString()));
const files=listPackage(archive),forbidden=files.filter(path=>/^\\(?:test-output|test|tools|resources|account-server)\\/.test(path)||/pairing\.dat|account-session\.dat|account-device\.json|deployment-private|library\.json|\.env$/i.test(path));
const version=JSON.parse(extractFile(archive,'package.json').toString()).version;
const result={version,sourceMatches:mismatches.length===0,mismatches,forbidden,relayConfigured:true,relayHost:new URL(config.url).hostname,applicationAccessExpires:false,configurationContainsOnlyApplicationAccess:true,files:files.length};
const raw=JSON.parse(extractFile(archive,'assets/relay-config.json').toString());if(Object.keys(raw).some(key=>!['url','applicationAccess','expiresAt'].includes(key)))throw Error('Unexpected bundled relay configuration fields');
if(mismatches.length||forbidden.length)throw Error(JSON.stringify(result));
await mkdir(resolve('test-output'),{recursive:true});await writeFile(resolve('test-output/package-check.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));
