import {randomUUID} from 'node:crypto';
import {swiftNow} from './library.mjs';
const dictionaries = (key, value) => {
  if (!value || typeof value !== 'object') return [];
  return [...(value[key] && typeof value[key] === 'object' ? [value[key]] : []), ...Object.values(value).flatMap(child => dictionaries(key, child))];
};
const values = (key, value) => {
  if (!value || typeof value !== 'object') return [];
  return [...(typeof value[key] === 'string' ? [value[key]] : []), ...Object.values(value).flatMap(child => values(key, child))];
};
export function parseSearch(root, {allowUnlabelledSongs=false,allowPlaylistVideos=false}={}) {
  if (root.error) throw Error('Le catalogue a refusé la recherche.');
  const seen = new Set();
  return dictionaries('musicResponsiveListItemRenderer', root).flatMap(row => {
    const types = values('musicVideoType', row);
    const playlistVideo=types.some(type=>['MUSIC_VIDEO_TYPE_OMV','MUSIC_VIDEO_TYPE_UGC'].includes(type));
    if ((!types.includes('MUSIC_VIDEO_TYPE_ATV') && !(allowUnlabelledSongs&&!types.length) && !(allowPlaylistVideos&&playlistVideo)) || playlistVideo&&!allowPlaylistVideos || row.musicItemRendererDisplayPolicy === 'MUSIC_ITEM_RENDERER_DISPLAY_POLICY_GREY_OUT') return [];
    const columns = (row.flexColumns || []).map(c => c.musicResponsiveListItemFlexColumnRenderer?.text?.runs || []);
    const title = columns[0]?.map(r => r.text || '').join('');
    const id = row.playlistItemData?.videoId || values('videoId', columns[0])[0];
    if (!/^[\w-]{11}$/.test(id || '') || !title || seen.has(id)) return [];
    seen.add(id);
    const runs = columns.slice(1).flat(), artists = [], albums = [];
    let artistID;
    for (const run of runs) {
      const browse = run.navigationEndpoint?.browseEndpoint?.browseId;
      if (browse?.startsWith('UC')) { artists.push(run.text); artistID ||= browse; }
      if (browse?.startsWith('MPRE')) albums.push(run.text);
    }
    const fixedRuns=(row.fixedColumns||[]).flatMap(c=>c.musicResponsiveListItemFixedColumnRenderer?.text?.runs||[]);
    const durationText = [...runs,...fixedRuns].find(r => /^\d{1,3}:\d{2}(?::\d{2})?$/.test(r.text))?.text;
    const thumbs = dictionaries('musicThumbnailRenderer', row).flatMap(x => dictionaries('thumbnail', x)).flatMap(t => t.thumbnails || []).sort((a, b) => b.width - a.width);
    const cover = (thumbs.find(t => t.width <= 640) || thumbs[0])?.url;
    return [{id: randomUUID().toUpperCase(), title, artist: [...new Set(artists)].join(', '), album: albums[0] || '', duration: durationText?.split(':').reduce((a, b) => a * 60 + Number(b), 0) || 0,
      source: 'invidious', location: id, artwork: 'cover-night', ...(cover?.startsWith('https://') ? {artworkURL: cover} : {}), addedAt: swiftNow(), isExplicit: values('iconType', row).includes('MUSIC_EXPLICIT_BADGE'), musicCatalog: playlistVideo?'youtube-music-video':'youtube-music', ...(artistID ? {artistID} : {})}];
  });
}
const filters={songs:'EgWKAQIIAWoMEA4QChADEAQQCRAF',albums:'EgWKAQIYAWoMEA4QChADEAQQCRAF',artists:'EgWKAQIgAWoMEA4QChADEAQQCRAF',playlists:'EgWKAQIoAWoMEA4QChADEAQQCRAF'};
const text=value=>typeof value==='string'?value:value?.runs?.map(r=>r.text||'').join('')||value?.simpleText||'';
function artwork(value){return dictionaries('thumbnail',value).flatMap(t=>t.thumbnails||[]).concat(dictionaries('musicThumbnailRenderer',value).flatMap(t=>t.thumbnail?.thumbnails||[])).filter(t=>typeof t.url==='string'&&t.url.startsWith('https://')).sort((a,b)=>(b.width||0)-(a.width||0))[0]?.url;}
function continuation(root){return dictionaries('nextContinuationData',root)[0]?.continuation||dictionaries('continuationCommand',root)[0]?.token||null;}
export function parseEntities(root,kind) {
  const seen=new Set();
  const rows=[...dictionaries('musicResponsiveListItemRenderer',root),...dictionaries('musicTwoRowItemRenderer',root)];
  return rows.flatMap(row=>{
    const columns=(row.flexColumns||[]).map(c=>c.musicResponsiveListItemFlexColumnRenderer?.text);
    const title=text(row.title)||text(columns[0]);
    const endpoints=dictionaries('browseEndpoint',row.navigationEndpoint||{}).concat(dictionaries('browseEndpoint',row.title||columns[0]||{}));
    const id=endpoints.map(e=>e.browseId).find(id=>typeof id==='string'&&(kind==='artists'?/^(UC|MPLA)/.test(id):kind==='albums'?/^MPRE/.test(id):/^(VL|PL|RDCL|RDEM)/.test(id)));
    if(!id||!title||seen.has(id))return[];seen.add(id);
    return [{id,title,kind,subtitle:text(row.subtitle)||columns.slice(1).map(text).filter(Boolean).join(' · '),artworkURL:artwork(row)}];
  });
}
async function call(endpoint,payload,token) {
  if(token!==undefined&&token!==null&&(typeof token!=='string'||token.length>20000))throw Error('Pagination invalide.');
  const version = '1.20261021.01.00';
  const url=new URL(`https://music.youtube.com/youtubei/v1/${endpoint}`);url.searchParams.set('prettyPrint','false');if(token)url.searchParams.set('continuation',token);
  const response = await fetch(url, {method: 'POST', signal: AbortSignal.timeout(15000),
    headers: {'Content-Type': 'application/json', Origin: 'https://music.youtube.com', 'X-YouTube-Client-Name': '67', 'X-YouTube-Client-Version': version},
    body: JSON.stringify({...(token&&endpoint==='browse'?{continuation:token}:payload), context: {client: {clientName: 'WEB_REMIX', clientVersion: version, hl: 'fr', gl: 'FR'}}})});
  if (!response.ok) throw Error(`Catalogue indisponible (HTTP ${response.status}).`);
  const root=await response.json();if(root.error)throw Error('Le catalogue a refusé cette demande.');return root;
}
export async function catalogSearch({query,kind='songs',continuation:token}={}) {
  if(typeof query!=='string'||query.trim().length<2||query.length>200||!Object.hasOwn(filters,kind))throw Error('Recherche invalide : entre 2 et 200 caractères.');
  const root=await call('search',{query:query.trim(),params:filters[kind]},token);
  return {kind,tracks:kind==='songs'?parseSearch(root):[],items:kind==='songs'?[]:parseEntities(root,kind),continuation:continuation(root)};
}
export async function search(query){return (await catalogSearch({query})).tracks;}
export async function browse({id,kind='albums',continuation:token}={}) {
  if(typeof id!=='string'||!/^(?:UC|MPLA|MPRE|VL|PL|RDCL|RDEM)[\w-]{4,160}$/.test(id)||!['albums','artists','playlists'].includes(kind))throw Error('Identifiant de catalogue invalide.');
  const root=await call('browse',{browseId:id.startsWith('PL')?'VL'+id:id},token);
  const header=[...dictionaries('musicDetailHeaderRenderer',root),...dictionaries('musicResponsiveHeaderRenderer',root),...dictionaries('musicImmersiveHeaderRenderer',root),...dictionaries('musicVisualHeaderRenderer',root)].find(h=>text(h.title));
  const playlistShelves=[...dictionaries('musicPlaylistShelfRenderer',root),...dictionaries('musicPlaylistShelfContinuation',root)];
  const content=kind==='playlists'&&playlistShelves.length?playlistShelves:root;
  // A section-list continuation may load recommendations, not more playlist
  // tracks. Only advertise pagination belonging to the actual music shelf.
  const next=kind==='playlists'?continuation(playlistShelves):continuation(root.continuationContents||dictionaries('musicShelfRenderer',root));
  const title=text(header?.title)||'Sélection YouTube Music',cover=artwork(header||{});
  const tracks=parseSearch(content,{allowUnlabelledSongs:true,allowPlaylistVideos:kind==='playlists'}).map(track=>({...track,...(kind==='albums'?{album:track.album||title}:{}),...(!track.artworkURL&&cover&&kind!=='artists'?{artworkURL:cover}:{})}));
  return {id,kind,title,subtitle:text(header?.subtitle),artworkURL:cover,tracks,continuation:next};
}
