import {randomUUID} from 'node:crypto';
import {mkdir, readFile, writeFile, rename, copyFile} from 'node:fs/promises';
import {join} from 'node:path';

export const swiftNow = () => Date.now() / 1000 - 978307200;
export const clone = value => structuredClone(value);
export const defaultSettings = () => ({accent: 'blue', appearance: 'dark', haptics: true, animateArtwork: true, compactRows: false, artworkRadius: 18,
  playbackRate: 1, pitch: 0, equalizer: Array(10).fill(0), equalizerEnabled: false, lyricsOffset: 0, volume: 0.8, restoreQueue: true});
export function seed() {
  const titles = ['Bleu nuit', 'Après la pluie', 'Orbite', 'Dernier métro'];
  const names = ['bleu-nuit', 'apres-la-pluie', 'orbite', 'dernier-metro'];
  const covers = ['night', 'rain', 'orbit', 'metro'];
  const tracks = titles.map((title, i) => ({id: `50B93537-ED39-4BEA-AB00-00000000000${i}`, title, artist: 'Soryn Studio', album: 'Premières ondes', duration: 48,
    source: 'bundled', location: names[i] + '.wav', artwork: 'cover-' + covers[i], addedAt: swiftNow(), isExplicit: false}));
  return {version: 1, tracks, playlists: [{id: '50B93537-ED39-4BEA-AB00-000000000010', name: 'Premières ondes', detail: 'Quatre instrumentaux originaux, créés pour ce projet.',
    trackIDs: tracks.map(t => t.id), createdAt: swiftNow(), symbol: 'waveform'}], favorites: [], history: [], followedArtists: [], queue: [], settings: defaultSettings()};
}
const sources = new Set(['bundled', 'local', 'remote', 'youtube', 'invidious', 'catalogReference', 'unresolved']);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
export function validateLibrary(value) {
  if (!value || value.version !== 1) throw Error('Version de bibliothèque non prise en charge.');
  for (const key of ['tracks', 'playlists', 'favorites', 'history']) {
    if (!Array.isArray(value[key]) || value[key].length > 50000) throw Error('Bibliothèque invalide ou trop volumineuse.');
  }
  const ids = new Set();
  for (const t of value.tracks) {
    if (!uuid.test(t.id) || ids.has(t.id) || typeof t.title !== 'string' || typeof t.artist !== 'string' || !sources.has(t.source) || typeof t.location !== 'string' ||
        !Number.isFinite(t.duration) || t.duration < 0 || t.title.length > 2000 || t.location.length > 4096) throw Error('Titre invalide.');
    ids.add(t.id);
  }
  const playlists = new Set();
  for (const p of value.playlists) {
    if (!uuid.test(p.id) || playlists.has(p.id) || typeof p.name !== 'string' || p.name.length > 2000 || !Array.isArray(p.trackIDs) || p.trackIDs.length > 50000 || !p.trackIDs.every(id => uuid.test(id))) throw Error('Playlist invalide.');
    playlists.add(p.id);
  }
  if (!value.favorites.every(id => uuid.test(id))) throw Error('Favoris invalides.');
  for (const e of value.history) if (!uuid.test(e.id) || !uuid.test(e.trackID) || !Number.isFinite(e.date) || !Number.isFinite(e.seconds) || e.seconds < 0) throw Error('Historique invalide.');
  if (value.followedArtists !== undefined && (!Array.isArray(value.followedArtists) || value.followedArtists.length > 10000 || !value.followedArtists.every(a => typeof a.id === 'string' && typeof a.name === 'string'))) throw Error('Artistes invalides.');
  return clone(value);
}

// Local paths, relay access and playback preferences never leave their device.
export function sharedSnapshot(snapshot) {
  const data = validateLibrary(snapshot);
  data.settings = {}; data.queue = []; delete data.currentTrackID;
  data.tracks = data.tracks.map(t => {
    const track = clone(t);
    if (track.source === 'local') { track.source = 'unresolved'; track.location = ''; }
    if (!/^https:\/\//i.test(track.artworkURL || '')) delete track.artworkURL;
    delete track.originInstance;
    return track;
  });
  data.followedArtists = (data.followedArtists || []).map(artist => {
    if (!/^https:\/\//i.test(artist.artworkURL || '')) delete artist.artworkURL;
    return artist;
  });
  return data;
}
const equal = (a, b) => JSON.stringify(a) === JSON.stringify(b);
export function mergeSet(base = [], local = [], remote = []) {
  const b = new Set(base), l = new Set(local), r = new Set(remote);
  return [...new Set([...local, ...remote])].filter(id => b.has(id) ? l.has(id) && r.has(id) : l.has(id) || r.has(id));
}
function mergeEntities(base, local, remote, combine) {
  const b = new Map(base.map(x => [x.id, x])), l = new Map(local.map(x => [x.id, x])), r = new Map(remote.map(x => [x.id, x]));
  const result = [];
  for (const id of new Set([...l.keys(), ...r.keys()])) {
    const before = b.get(id), left = l.get(id), right = r.get(id);
    if (!left || !right) {
      const remaining = left || right;
      // A deletion propagates, unless the other device edited this entity.
      if (!before || !equal(before, remaining)) result.push(clone(remaining));
    } else if (equal(before, left)) result.push(clone(right));
    else if (equal(before, right)) result.push(clone(left));
    else result.push(combine(before, left, right));
  }
  return result;
}
function fields(base = {}, local, remote) {
  const result = clone(local);
  for (const k of Object.keys(remote)) if (equal(base[k], local[k])) result[k] = clone(remote[k]);
  return result;
}
export function mergeLibraries(base, local, remote) {
  const empty = {tracks: [], playlists: [], favorites: [], history: [], followedArtists: []};
  base ||= empty;
  const result = clone(local);
  result.tracks = mergeEntities(base.tracks, local.tracks, remote.tracks, (b, l, r) => fields(b, l, r));
  result.playlists = mergeEntities(base.playlists, local.playlists, remote.playlists, (b, l, r) => ({...fields(b, l, r), trackIDs: mergeSet(b?.trackIDs, l.trackIDs, r.trackIDs)}));
  result.favorites = mergeSet(base.favorites, local.favorites, remote.favorites);
  // A listening session can be observed on two devices; never double-count it.
  const events = new Map(local.history.map(x => [x.id, clone(x)]));
  for (const event of remote.history) if (!events.has(event.id) || event.seconds > events.get(event.id).seconds) events.set(event.id, clone(event));
  result.history = [...events.values()].sort((a, b) => a.date - b.date);
  result.followedArtists = mergeEntities(base.followedArtists || [], local.followedArtists || [], remote.followedArtists || [], (b, l, r) => fields(b, l, r));
  // Canonicalise independently added online/bundled titles and remap references.
  const seen = new Map(), aliases = new Map();
  result.tracks = result.tracks.filter(t => {
    if (!['bundled', 'invidious', 'youtube'].includes(t.source) || !t.location) return true;
    const key = `${t.source === 'youtube' ? 'invidious' : t.source}|${t.location}`;
    if (seen.has(key)) { aliases.set(t.id, seen.get(key)); return false; }
    seen.set(key, t.id); return true;
  });
  const remap = id => aliases.get(id) || id, known = new Set(result.tracks.map(t => t.id));
  result.playlists.forEach(p => { p.trackIDs = [...new Set(p.trackIDs.map(remap))].filter(id => known.has(id)); });
  result.favorites = [...new Set(result.favorites.map(remap))].filter(id => known.has(id));
  result.history.forEach(e => { e.trackID = remap(e.trackID); });
  result.queue = [...new Set((result.queue || []).map(remap))].filter(id => known.has(id));
  result.currentTrackID = result.currentTrackID ? remap(result.currentTrackID) : undefined;
  return result;
}

export class LibraryStore {
  constructor(directory) { this.directory = directory; this.pending = Promise.resolve(); }
  async load() {
    await mkdir(this.directory, {recursive: true});
    try { this.data = validateLibrary(JSON.parse(await readFile(join(this.directory, 'library.json'), 'utf8'))); }
    catch (error) { if (error.code !== 'ENOENT') throw Error('Bibliothèque illisible : fichier conservé pour récupération. ' + error.message); this.data = seed(); await this.save(); }
    return clone(this.data);
  }
  save() {
    const text = JSON.stringify(this.data), path = join(this.directory, 'library.json');
    this.pending = this.pending.catch(() => {}).then(async () => {
      try { await copyFile(path, path + '.bak'); } catch (e) { if (e.code !== 'ENOENT') throw e; }
      await writeFile(path + '.tmp', text); await rename(path + '.tmp', path);
    });
    return this.pending;
  }
  async update(fn) { fn(this.data); await this.save(); return clone(this.data); }
  add(track) {
    const existing = this.data.tracks.find(t => t.id === track.id || t.source === track.source && t.location && t.location === track.location);
    if (existing) return existing;
    this.data.tracks.push({...track, id: track.id || randomUUID().toUpperCase()});
    return this.data.tracks.at(-1);
  }
}
