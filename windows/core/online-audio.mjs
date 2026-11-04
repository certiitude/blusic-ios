import {createWriteStream} from 'node:fs';
import {stat, rm} from 'node:fs/promises';
import {Readable, Transform} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {parseFile} from 'music-metadata';

export const DEFAULT_INVIDIOUS = ['https://inv.nadeko.net', 'https://invidious.nerdvpn.de', 'https://yt.chocolatemoo53.com'];
export const validID = value => typeof value === 'string' && /^[\w-]{11}$/.test(value);
export function relayConfiguration(value) {
  const url = new URL(value?.url);
  if (url.protocol !== 'https:' || url.username || url.password || url.pathname !== '/' || url.search || url.hash ||
      !/^app\.(?:ios|android|windows)\.[a-f0-9]{64}$/.test(value?.applicationAccess || '') || value.expiresAt !== 0) throw Error('Configuration application du relais invalide.');
  return {url:url.origin, applicationAccess:value.applicationAccess, expiresAt:0};
}
export function publicMediaURL(value, trustedOrigin) {
  const url = new URL(value, trustedOrigin);
  if (url.protocol !== 'https:' || url.username || url.password || url.port && url.port !== '443') throw Error('Adresse audio HTTPS invalide.');
  const host = url.hostname.toLowerCase();
  if (host === 'localhost' || host.endsWith('.local') || host.includes(':') || /^\d+\.\d+\.\d+\.\d+$/.test(host)) throw Error('Adresse audio privée refusée.');
  if (trustedOrigin && url.origin !== new URL(trustedOrigin).origin && !host.endsWith('.googlevideo.com')) throw Error('Hôte audio inattendu.');
  return url;
}
export async function downloadVerifiedAudio({url,path,expectedSize,expectedDuration=0,signal,fetchFunction=fetch,inspectFile=parseFile,bitrate=0,source,trustedOrigin}) {
  let address=publicMediaURL(url,trustedOrigin),response;
  for(let redirects=0;redirects<=3;redirects++){
    response=await fetchFunction(address,{signal,redirect:'manual'});
    if(![301,302,303,307,308].includes(response.status))break;
    const location=response.headers.get('Location');await response.body?.cancel();
    if(redirects===3||!location)throw Error('Redirection audio invalide.');
    address=publicMediaURL(new URL(location,address),trustedOrigin||new URL(url).origin);
  }
  if (!response.ok) throw Error(`Audio refusé (HTTP ${response.status}).`);
  if (!/^audio\/(mp4|x-m4a|aac)(?:;|$)|^application\/octet-stream(?:;|$)/i.test(response.headers.get('Content-Type') || '')) throw Error('La source n’a pas renvoyé un fichier AAC/M4A.');
  const length = expectedSize || Number(response.headers.get('Content-Length'));
  if (!Number.isSafeInteger(length) || length <= 0 || length > 100_000_000) throw Error('Taille audio absente ou hors limites.');
  let received=0, head=Buffer.alloc(0);
  const guard=new Transform({transform(chunk,_,done){received+=chunk.length;if(head.length<64)head=Buffer.concat([head,chunk.subarray(0,64-head.length)]);done(received>length?Error('Réponse audio trop volumineuse.'):null,chunk);}});
  try {
    await pipeline(Readable.fromWeb(response.body),guard,createWriteStream(path,{flags:'wx'}),{signal});
    if (received!==length || !head.includes(Buffer.from('ftyp'))) throw Error('Fichier audio incomplet ou non M4A.');
    const meta=await inspectFile(path,{duration:true});
    if (!(meta.format.duration>0) || expectedDuration>0 && meta.format.duration<expectedDuration-Math.max(2,expectedDuration*.02)) throw Error('Fichier audio tronqué : durée insuffisante.');
    return {path,size:(await stat(path)).size,duration:meta.format.duration,bitrate:bitrate||meta.format.bitrate||0,source};
  } catch(error) {await rm(path,{force:true});throw error;}
}
export async function prepareRelay(videoID,config,path,duration,{fetchFunction=fetch,signal=AbortSignal.timeout(55000)}={}) {
  if(!validID(videoID))throw Error('Identifiant musical invalide.');
  const relay=relayConfiguration(config);
  const response=await fetchFunction(`${relay.url}/v1/streams/${videoID}?quality=high`,{headers:{Authorization:`Bearer ${relay.applicationAccess}`},signal,redirect:'error'});
  if(!response.ok)throw Error(`Relais youtubei.js indisponible (HTTP ${response.status}).`);
  const meta=await response.json(),url=publicMediaURL(meta.url,relay.url);
  if(url.origin!==relay.url)throw Error('Le relais a renvoyé une adresse audio externe.');
  return downloadVerifiedAudio({url,path,expectedSize:Number(meta.size),expectedDuration:duration||Number(meta.duration),signal,fetchFunction,bitrate:Number(meta.bitrate),source:'Relais youtubei.js',trustedOrigin:relay.url});
}
export async function discoverInvidious({fetchFunction=fetch,signal=AbortSignal.timeout(4000)}={}) {
  try{
    const response=await fetchFunction('https://api.invidious.io/',{signal:AbortSignal.any([signal,AbortSignal.timeout(4000)]),redirect:'error'});
    if(!response.ok)return[];
    const rows=await response.json();if(!Array.isArray(rows))return[];
    return rows.filter(row=>Array.isArray(row)&&row[1]?.api===true&&typeof row[1]?.uri==='string').slice(0,30).flatMap(row=>{try{return [publicMediaURL(row[1].uri).origin];}catch{return[];}}).slice(0,3);
  }catch{return[];}
}
export async function prepareInvidious(videoID,instances,path,duration,{fetchFunction=fetch,signal=AbortSignal.timeout(35000),discover=false}={}) {
  if(!validID(videoID))throw Error('Identifiant musical invalide.');
  const failures=[];
  const candidates=[...new Set(instances)].slice(0,4),discovery=discover?discoverInvidious({fetchFunction,signal}):Promise.resolve([]);
  for(let index=0;index<candidates.length;index++) {
    const address=candidates[index];
    try {
      const origin=publicMediaURL(address).origin;
      const endpoint=new URL(`/api/v1/videos/${videoID}`,origin);endpoint.searchParams.set('local','true');
      const response=await fetchFunction(endpoint,{signal:AbortSignal.any([signal,AbortSignal.timeout(5000)]),redirect:'error'});
      if(!response.ok)throw Error(`HTTP ${response.status}`);
      const info=await response.json();
      const candidates=(info.adaptiveFormats||[]).filter(f=>/^audio\/mp4/i.test(f.type||f.mimeType||'')&&f.url).sort((a,b)=>Number(b.bitrate)-Number(a.bitrate));
      const format=candidates[0];if(!format)throw Error('Aucun AAC annoncé');
      const url=publicMediaURL(format.url,origin);
      return await downloadVerifiedAudio({url,path,expectedSize:Number(format.clen||format.contentLength),expectedDuration:duration||Number(info.lengthSeconds),signal,fetchFunction,bitrate:Number(format.bitrate),source:'Invidious',trustedOrigin:origin});
    }catch(error){if(signal.aborted)throw error;failures.push(new URL(address).hostname+': '+String(error.message).slice(0,100));}
    if(index===candidates.length-1&&discover){for(const found of await discovery)if(!candidates.includes(found)&&candidates.length<7)candidates.push(found);discover=false;}
  }
  throw Error('Aucune instance Invidious accessible. '+failures.join(' · '));
}
