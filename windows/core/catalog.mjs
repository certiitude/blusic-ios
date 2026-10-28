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
export function parseSearch(root) {
  if (root.error) throw Error('Le catalogue a refusé la recherche.');
  const seen = new Set();
  return dictionaries('musicResponsiveListItemRenderer', root).flatMap(row => {
    const types = values('musicVideoType', row);
    if (!types.includes('MUSIC_VIDEO_TYPE_ATV') || types.includes('MUSIC_VIDEO_TYPE_OMV') || row.musicItemRendererDisplayPolicy === 'MUSIC_ITEM_RENDERER_DISPLAY_POLICY_GREY_OUT') return [];
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
    const durationText = runs.find(r => /^\d{1,3}:\d{2}(?::\d{2})?$/.test(r.text))?.text;
    const thumbs = dictionaries('musicThumbnailRenderer', row).flatMap(x => dictionaries('thumbnail', x)).flatMap(t => t.thumbnails || []).sort((a, b) => b.width - a.width);
    const cover = (thumbs.find(t => t.width <= 640) || thumbs[0])?.url;
    return [{id: randomUUID().toUpperCase(), title, artist: [...new Set(artists)].join(', '), album: albums[0] || '', duration: durationText?.split(':').reduce((a, b) => a * 60 + Number(b), 0) || 0,
      source: 'invidious', location: id, artwork: 'cover-night', ...(cover?.startsWith('https://') ? {artworkURL: cover} : {}), addedAt: swiftNow(), isExplicit: values('iconType', row).includes('MUSIC_EXPLICIT_BADGE'), musicCatalog: 'youtube-music', ...(artistID ? {artistID} : {})}];
  });
}
export async function search(query) {
  if (typeof query !== 'string' || query.length < 2 || query.length > 200) throw Error('Entre entre 2 et 200 caractères.');
  const version = '1.20261021.01.00';
  const response = await fetch('https://music.youtube.com/youtubei/v1/search?prettyPrint=false', {method: 'POST', signal: AbortSignal.timeout(15000),
    headers: {'Content-Type': 'application/json', Origin: 'https://music.youtube.com', 'X-YouTube-Client-Name': '67', 'X-YouTube-Client-Version': version},
    body: JSON.stringify({query, params: 'EgWKAQIIAWoMEA4QChADEAQQCRAF', context: {client: {clientName: 'WEB_REMIX', clientVersion: version, hl: 'fr', gl: 'FR'}}})});
  if (!response.ok) throw Error(`Catalogue indisponible (HTTP ${response.status}).`);
  return parseSearch(await response.json());
}
