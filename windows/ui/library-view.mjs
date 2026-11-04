// Pure view-model helpers: filtering and sorting never mutate the library.
export const normalise = value => String(value || '').normalize('NFD').replace(/\p{Diacritic}/gu, '').toLocaleLowerCase('fr');
export function selectTracks(tracks, {query = '', sort = 'default'} = {}) {
  const terms = normalise(query).trim().split(/\s+/).filter(Boolean);
  const result = tracks.filter(t => {
    const haystack = normalise(`${t.title} ${t.artist} ${t.album || ''}`);
    return terms.every(term => haystack.includes(term));
  });
  const compare = (a, b) => String(a || '').localeCompare(String(b || ''), 'fr', {sensitivity: 'base', numeric: true});
  if (sort === 'title') result.sort((a, b) => compare(a.title, b.title));
  if (sort === 'artist') result.sort((a, b) => compare(a.artist, b.artist) || compare(a.title, b.title));
  if (sort === 'recent') result.sort((a, b) => (b.addedAt || 0) - (a.addedAt || 0));
  if (sort === 'duration') result.sort((a, b) => (a.duration || 0) - (b.duration || 0));
  return result;
}
export function recentTracks(library, limit = 6) {
  const byID = new Map(library.tracks.map(t => [t.id, t]));
  const seen = new Set(), result = [];
  for (const event of [...library.history].reverse()) {
    if (!seen.has(event.trackID) && byID.has(event.trackID)) {
      seen.add(event.trackID); result.push(byID.get(event.trackID));
      if (result.length >= limit) break;
    }
  }
  return result;
}
