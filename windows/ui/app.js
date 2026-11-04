import {selectTracks, recentTracks} from './library-view.mjs';
const $ = selector => document.querySelector(selector);
const icons = {
  home:'<path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-7H9v7H4a1 1 0 0 1-1-1Z"/>',
  search:'<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
  library:'<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 7v10m4-8v8m4-11v11"/>',
  heart:'<path d="M20.8 4.7a5.5 5.5 0 0 0-7.8 0L12 5.8l-1.1-1.1a5.5 5.5 0 0 0-7.8 7.8L12 21l8.8-8.5a5.5 5.5 0 0 0 0-7.8Z"/>',
  download:'<path d="M12 3v12m-4-4 4 4 4-4M4 16v5h16v-5"/>',
  plus:'<path d="M12 5v14M5 12h14"/>',
  playlist:'<rect x="4" y="3" width="16" height="18" rx="2"/><path d="M8 7h8m-8 4h8m-8 4h5"/>',
  sync:'<path d="M20 8a8.5 8.5 0 0 0-15-3L2 8m0-5v5h5m-3 8a8.5 8.5 0 0 0 15 3l3-3m0 5v-5h-5"/>',
  settings:'<path d="M4 7h16M4 17h16"/><circle cx="9" cy="7" r="3" fill="currentColor"/><circle cx="15" cy="17" r="3" fill="currentColor"/>',
  left:'<path d="m14 6-6 6 6 6"/>', right:'<path d="m10 6 6 6-6 6"/>',
  desktop:'<rect x="3" y="3" width="18" height="13" rx="2"/><path d="M8 21h8m-4-5v5"/>',
  phone:'<rect x="6" y="2" width="12" height="20" rx="3"/><path d="M10 18h4M10 5h4"/>',
  wave:'<path d="M3 10v4m4-8v12m5-16v20m5-16v12m4-8v4"/>',
  play:'<path d="m8 4 13 8-13 8Z" fill="currentColor" stroke="none"/>',
  pause:'<path d="M7 5v14m10-14v14" stroke-width="3.5"/>',
  previous:'<path d="M5 5v14m14-14L8 12l11 7Z" fill="currentColor"/>',
  next:'<path d="M19 5v14M5 5l11 7-11 7Z" fill="currentColor"/>',
  shuffle:'<path d="M3 6h3c5 0 7 12 12 12h3m-4-4 4 4-4 4M3 18h3c1 0 2-1 3-3m6-6c1-2 2-3 4-3h2m-4-4 4 4-4 4"/>',
  repeat:'<path d="M3 11V8a3 3 0 0 1 3-3h14l-4-4m5 12v3a3 3 0 0 1-3 3H4l4 4M20 5l-4 4M4 19l4-4"/>',
  lyrics:'<rect x="3" y="4" width="18" height="16" rx="3"/><path d="M7 9h10m-10 4h10m-10 3h6"/>',
  queue:'<path d="M3 5h17M3 10h17M3 15h10m4 0 5 3-5 3Z"/>',
  volume:'<path d="m11 3-6 5H1v8h4l6 5Zm5 5a6 6 0 0 1 0 8m3-11a10 10 0 0 1 0 14"/>',
  more:'<circle cx="5" cy="12" r="1" fill="currentColor"/><circle cx="12" cy="12" r="1" fill="currentColor"/><circle cx="19" cy="12" r="1" fill="currentColor"/>',
  check:'<path d="m5 12 4 4L19 6"/>', clock:'<circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 2"/>',
  folder:'<path d="M3 5h6l2 3h10v12H3Z"/>', trash:'<path d="M3 6h18M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7m4-7v7"/>',
  grid:'<rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/>',
  list:'<path d="M9 5h12M9 12h12M9 19h12M3 5h1m-1 7h1m-1 7h1"/>',
  arrow:'<path d="M5 12h14m-5-5 5 5-5 5"/>',
  person:'<circle cx="12" cy="8" r="4"/><path d="M4 22v-2a8 8 0 0 1 16 0v2"/>',
};
const icon = name => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[name] || icons.wave}</svg>`;
function hydrate(scope = document) { scope.querySelectorAll('[data-icon]').forEach(node => { node.innerHTML = icon(node.dataset.icon); }); }
const escape = text => String(text ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const clock = seconds => `${Math.floor(Math.max(0, seconds || 0) / 60)}:${String(Math.floor(Math.max(0, seconds || 0) % 60)).padStart(2, '0')}`;
const art = track => data?.artwork?.[track?.id] || (/^https:\/\//i.test(track?.artworkURL || '') ? track.artworkURL : `../assets/${['cover-night','cover-rain','cover-orbit','cover-metro'].includes(track?.artwork) ? track.artwork : 'cover-night'}.png`);
const api = (action, input) => window.soryn.call(action, input);
let data, view = 'home', selectedPlaylist, searchResults = [], query = '', searching = false, searchGeneration = 0;
let searchKind='songs',catalogItems=[],searchContinuation=null,catalogPage=null,catalogBusy=false,catalogError='';
let queue = [], current, loading = false, playGeneration = 0, shuffle = false, repeat = false, toastTimer, downloadBusy = false, downloadCancelled = false;
let sessionID, listened = 0, lastTick = 0, navigation = ['home'], navIndex = 0, syncInfo;
const preferences = {
  get(key, fallback) { try { return localStorage.getItem(`soryn.ui.${key}`) || fallback; } catch { return fallback; } },
  set(key, value) { try { localStorage.setItem(`soryn.ui.${key}`, value); } catch { /* Optional presentation preferences. */ } }
};
let collectionQuery = '', collectionSort = preferences.get('sort', 'default'), collectionLayout = preferences.get('layout', 'list'), homeFilter = 'all';
if (!['default','title','artist','recent','duration'].includes(collectionSort)) collectionSort = 'default';
if (!['list','grid'].includes(collectionLayout)) collectionLayout = 'list';
const audio = $('#audio');
const find = id => data.library.tracks.find(t => t.id === id) || searchResults.find(t => t.id === id) || catalogPage?.tracks?.find(t=>t.id===id) || queue.find(t => t.id === id);
const isLiked = track => track && data.library.favorites.some(id => id === track.id || data.library.tracks.some(t => t.id === id && t.source === track.source && t.location === track.location));

function toast(message, error = false, cancel = false) {
  clearTimeout(toastTimer); const node = $('#toast'); node.hidden = false; node.classList.toggle('error', error); node.replaceChildren(document.createTextNode(message));
  if (cancel) { const b = document.createElement('button'); b.textContent = 'Annuler'; b.onclick = () => cancelPreparation(); node.append(b); }
  else toastTimer = setTimeout(() => { node.hidden = true; }, error ? 12000 : 4500);
}
async function run(action, input, success) {
  try { const result = await api(action, input); if (success) toast(success); return result; }
  catch (error) { toast(error.message.replace(/^Error invoking remote method '[^']+': Error: /, ''), true); throw error; }
}
function header(eyebrow, title, detail = '', action = '') { return `<div class="page-heading"><div><span class="eyebrow">${escape(eyebrow)}</span><h1>${escape(title)}</h1>${detail ? `<p>${escape(detail)}</p>` : ''}</div>${action}</div>`; }
function empty(title, detail, action = '', symbol = 'wave') { return `<div class="empty-state"><i>${icon(symbol)}</i><h2>${escape(title)}</h2><p>${escape(detail)}</p>${action}</div>`; }
function table(tracks) {
  if (!tracks.length) return empty('La place pour tes envies.', 'Ajoute des morceaux depuis Explorer, importe tes fichiers ou synchronise ta bibliothèque iPhone.', '<button class="secondary-button" data-view="explore">Explorer la musique</button>');
  return `<table class="track-table"><thead><tr><th scope="col">#</th><th scope="col">Titre</th><th scope="col" class="album-column">Album</th><th scope="col" class="duration-column"><span class="sr-only">Durée</span>${icon('clock')}</th><th scope="col"><span class="sr-only">Actions</span></th></tr></thead><tbody>${tracks.map((t, index) => `<tr data-track-row="${escape(t.id)}" class="${current?.id === t.id ? 'playing-row' : ''}"><td class="track-number"><span>${index + 1}</span><i>${icon(current?.id === t.id && !audio.paused ? 'wave' : 'play')}</i></td><td><button class="track-cell" data-play="${escape(t.id)}" aria-label="Écouter ${escape(t.title)}"><img src="${escape(art(t))}" alt="" loading="lazy"><div><strong>${escape(t.title)}${t.isExplicit ? '<span class="explicit-badge" title="Contenu explicite">E</span>' : ''}</strong><small>${data.available.includes(t.id) ? `<i class="offline-indicator" title="Disponible hors ligne">${icon('check')}</i>` : ''}${escape(t.artist || 'Artiste inconnu')}</small></div></button></td><td class="album-column">${escape(t.album || '—')}</td><td class="duration-column">${clock(t.duration)}</td><td class="track-actions"><button class="icon-button ${isLiked(t) ? 'liked' : ''}" data-like="${escape(t.id)}" aria-label="${isLiked(t) ? 'Retirer des favoris' : 'Ajouter aux favoris'}" aria-pressed="${isLiked(t)}" title="Favoris">${icon('heart')}</button><button class="icon-button" data-menu="${escape(t.id)}" aria-label="Options pour ${escape(t.title)}" title="Plus d’options">${icon('more')}</button></td></tr>`).join('')}</tbody></table>`;
}
function cards(tracks) { return `<div class="album-grid">${tracks.map(t => `<article class="music-card"><button class="album-card" data-play="${escape(t.id)}" aria-label="Écouter ${escape(t.title)}"><div class="album-cover"><img src="${escape(art(t))}" alt="" loading="lazy"><span class="cover-play">${icon('play')}</span></div><h3>${escape(t.title)}</h3><p>${escape(t.artist || 'Artiste inconnu')}</p></button><button class="card-menu icon-button" data-menu="${escape(t.id)}" aria-label="Options pour ${escape(t.title)}">${icon('more')}</button></article>`).join('')}</div>`; }
function mosaic(tracks, className = '') {
  const covers = [...new Set(tracks.map(art))].slice(0, 4);
  return covers.length ? `<span class="artwork-mosaic ${covers.length < 4 ? 'single-artwork' : ''} ${className}">${(covers.length < 4 ? covers.slice(0,1) : covers).map(src => `<img src="${escape(src)}" alt="" loading="lazy">`).join('')}</span>` : `<span class="artwork-mosaic empty-artwork ${className}">${icon('playlist')}</span>`;
}
function playlistCards() {
  return `<div class="playlist-grid">${data.library.playlists.map(p => {
    const tracks = p.trackIDs.map(find).filter(Boolean);
    return `<button class="playlist-card" data-view="playlist:${escape(p.id)}">${mosaic(tracks)}<strong>${escape(p.name)}</strong><span>Playlist · ${tracks.length} titre${tracks.length > 1 ? 's' : ''}</span><i class="playlist-arrow">${icon('arrow')}</i></button>`;
  }).join('')}<button class="playlist-card create-playlist-card" data-create-playlist>${icon('plus')}<strong>Une nouvelle sélection</strong><span>Créer une playlist</span></button></div>`;
}
function collectionToolbar() {
  return `<div class="collection-toolbar"><label class="collection-search">${icon('search')}<input id="collection-search" value="${escape(collectionQuery)}" placeholder="Rechercher dans cette sélection" aria-label="Rechercher dans cette sélection" autocomplete="off"></label><span id="filtered-count" class="filtered-count"></span><label class="sort-control"><span class="sr-only">Trier les titres</span><select id="collection-sort" aria-label="Trier les titres">${[['default','Ordre de la sélection'],['recent','Ajouts récents'],['title','Titre'],['artist','Artiste'],['duration','Durée']].map(([value,label])=>`<option value="${value}" ${value===collectionSort?'selected':''}>${label}</option>`).join('')}</select></label><div class="layout-switch" role="group" aria-label="Présentation de la bibliothèque"><button class="icon-button" data-layout="list" aria-label="Vue liste" aria-pressed="${collectionLayout==='list'}" title="Liste">${icon('list')}</button><button class="icon-button" data-layout="grid" aria-label="Vue grille" aria-pressed="${collectionLayout==='grid'}" title="Grille">${icon('grid')}</button></div></div>`;
}
function catalogTabs() {return `<div class="catalog-tabs" role="group" aria-label="Catégories YouTube Music">${[['songs','Titres'],['albums','Albums'],['artists','Artistes'],['playlists','Playlists']].map(([kind,label])=>`<button data-catalog-kind="${kind}" aria-pressed="${searchKind===kind}">${label}</button>`).join('')}</div>`;}
function catalogCards(){return `<div class="catalog-grid">${catalogItems.map(item=>`<button class="catalog-card ${item.kind==='artists'?'artist-card':''}" data-catalog-id="${escape(item.id)}"><img src="${escape(item.artworkURL||'../assets/logo.png')}" alt="" loading="lazy"><strong>${escape(item.title)}</strong><span>${escape(item.subtitle||({albums:'Album',artists:'Artiste',playlists:'Playlist'}[item.kind]))}</span></button>`).join('')}</div>`;}
function paginationButton(continuation,action,busy){return continuation?`<div class="load-more"><button class="secondary-button" id="${action}" ${busy?'disabled':''}>${busy?'<span class="spinner"></span> Chargement…':'Charger plus de résultats'}</button></div>`:'';}
function visibleTracks() { return selectTracks(viewTracks(), {query: collectionQuery, sort: collectionSort}); }
function updateCollectionResults() {
  const target = $('#track-results'); if (!target) return;
  const tracks = visibleTracks();
  $('#filtered-count').textContent = `${tracks.length} titre${tracks.length > 1 ? 's' : ''}`;
  target.innerHTML = !tracks.length && collectionQuery.trim() ? empty('Aucun titre trouvé', 'Essaie un autre titre, artiste ou album. Ta bibliothèque n’a pas été modifiée.', '<button class="secondary-button" data-clear-filter>Effacer la recherche</button>', 'search') : collectionLayout === 'grid' && tracks.length ? cards(tracks) : table(tracks);
  document.querySelectorAll('[data-layout]').forEach(b => b.setAttribute('aria-pressed', String(b.dataset.layout === collectionLayout)));
}
function originalNote() { return `<p class="original-note">${icon('wave')}Les quatre instrumentaux Soryn Studio sont des créations originales du projet.</p>`; }
function go(next, push = true) {
  if (next !== (view === 'playlist' ? 'playlist:' + selectedPlaylist : view)) collectionQuery = '';
  if (next.startsWith('playlist:')) { selectedPlaylist = next.slice(9); view = 'playlist'; } else view = next;
  if (push && navigation[navIndex] !== next) { navigation = navigation.slice(0, navIndex + 1); navigation.push(next); navIndex++; }
  $('#content').scrollTop = 0; render();
}
function viewTracks() {
  const tracks = data.library.tracks;
  if (view === 'favorites') return tracks.filter(t => data.library.favorites.includes(t.id));
  if (view === 'downloads') return tracks.filter(t => data.available.includes(t.id));
  if (view === 'explore') return searchResults;
  if (view === 'catalog') return catalogPage?.tracks||[];
  if (view === 'playlist') return (data.library.playlists.find(p => p.id === selectedPlaylist)?.trackIDs || []).map(find).filter(Boolean);
  return tracks;
}
function render() {
  if (!data) return;
  document.querySelectorAll('.sidebar [data-view]:not(.brand)').forEach(b => { const active = b.dataset.view === (view === 'playlist' ? 'playlist:' + selectedPlaylist : view==='catalog'?'explore':view); b.classList.toggle('active', active); if(active)b.setAttribute('aria-current','page');else b.removeAttribute('aria-current'); });
  document.body.dataset.view = view;
  $('#favorite-count').textContent = data.library.favorites.length;
  $('#account-label').textContent=data.account?.signedIn?data.account.account.displayName:'Compte facultatif';
  $('#sync-dot').classList.toggle('on', data.syncActive);
  $('#back').disabled = navIndex === 0; $('#forward').disabled = navIndex >= navigation.length - 1;
  $('#playlist-navigation').innerHTML = data.library.playlists.map(p => `<button class="playlist-link ${view==='playlist'&&selectedPlaylist===p.id?'active':''}" data-view="playlist:${escape(p.id)}" ${view==='playlist'&&selectedPlaylist===p.id?'aria-current="page"':''}>${mosaic(p.trackIDs.map(find).filter(Boolean))}<span><strong>${escape(p.name)}</strong><small>Playlist · ${p.trackIDs.length} titre${p.trackIDs.length>1?'s':''}</small></span></button>`).join('');
  const main = $('#content'), tracks = viewTracks();
  switch (view) {
    case 'home': {
      const recent = recentTracks(data.library, 6), originals = data.library.tracks.filter(t => t.source === 'bundled').slice(0,6);
      const favorites = data.library.tracks.filter(t => data.library.favorites.includes(t.id)).slice(0,6);
      const featured = recent[0] || favorites[0] || data.library.tracks[0];
      const selection = recent.length ? recent : favorites.length ? favorites : originals.length ? originals : data.library.tracks.slice(0,6);
      main.innerHTML = `<div class="home-heading"><div><span class="eyebrow">TON ESPACE MUSICAL</span><h1>À écouter, maintenant<span>.</span></h1></div><span class="home-date">${escape(new Date().toLocaleDateString('fr-FR',{weekday:'long',day:'numeric',month:'long'}))}</span></div><div class="home-tabs" role="group" aria-label="Filtrer l’accueil">${[['all','Tout'],['music','Musique'],['playlists','Playlists']].map(([value,label])=>`<button data-home-filter="${value}" aria-pressed="${homeFilter===value}">${label}</button>`).join('')}</div>
        ${homeFilter !== 'playlists' && featured ? `<section class="hero"><img class="hero-backdrop" src="${escape(art(featured))}" alt=""><div class="hero-copy"><span class="eyebrow">${featured.source==='bundled'?'LES ORIGINAUX SORYN':recent.length?'REPRENDRE LE FIL':'DANS TA BIBLIOTHÈQUE'}</span><h2>${escape(featured.title)}</h2><p class="hero-artist">${escape(featured.artist)}</p><p class="hero-detail">${escape(featured.album || 'Ta prochaine parenthèse musicale.')} <span>·</span> ${clock(featured.duration)}</p><div class="hero-actions"><button id="hero-play" data-featured-id="${escape(featured.id)}" class="primary-button"><i>${icon('play')}</i>Écouter</button><button class="hero-favorite icon-button ${isLiked(featured)?'liked':''}" data-like="${escape(featured.id)}" aria-label="${isLiked(featured)?'Retirer des favoris':'Ajouter aux favoris'}" aria-pressed="${isLiked(featured)}">${icon('heart')}</button></div></div><img class="hero-artwork" src="${escape(art(featured))}" alt="Pochette de ${escape(featured.title)}"><span class="hero-watermark">soryn.</span></section>` : ''}
        ${homeFilter==='all'?`<div class="collection-shortcuts"><button data-view="favorites" class="collection-shortcut"><span class="shortcut-art favorite-art">${icon('heart')}</span><span><strong>Tes coups de cœur</strong><small>${data.library.favorites.length} titre${data.library.favorites.length>1?'s':''} à retrouver</small></span><i>${icon('right')}</i></button><button data-view="downloads" class="collection-shortcut"><span class="shortcut-art download-art">${icon('download')}</span><span><strong>Sans connexion</strong><small>${data.available.length} titre${data.available.length>1?'s':''} sur ce PC</small></span><i>${icon('right')}</i></button></div>`:''}
        ${homeFilter!=='playlists'?`<div class="section-header"><div><h2>${recent.length?'Écoutés récemment':favorites.length?'Toujours les bons morceaux':'Les originaux Soryn'}</h2><p>${recent.length?'Là où tu avais laissé la musique.':favorites.length?'Une sélection qui te ressemble.':'Quatre instrumentaux. Un premier voyage.'}</p></div><button class="text-button" data-view="${recent.length||!favorites.length?'library':'favorites'}">Tout voir ${icon('right')}</button></div>${selection.length?cards(selection):empty('Tout commence avec un morceau.', 'Importe tes fichiers ou retrouve un titre dans Explorer.', '<button class="secondary-button" data-view="explore">Explorer</button>')}`:''}
        ${homeFilter!=='music'?`<div class="section-header"><div><h2>Fait par toi. Pour toi.</h2><p>Tes playlists, à portée d’écoute.</p></div><button class="text-button" data-create-playlist>${icon('plus')}Créer</button></div>${playlistCards()}`:''}${originals.length&&homeFilter!=='playlists'?originalNote():''}`;
      break;
    }
    case 'explore':
      main.innerHTML = header('DÉCOUVRIR', query?`Résultats pour « ${query} »`:'Trouve ton prochain morceau.', 'Catalogue YouTube Music · lecteur audio Soryn') + catalogTabs() + (searching&&!searchResults.length&&!catalogItems.length ? `<div class="search-loading" role="status"><span class="spinner"></span><p>À la recherche de ta prochaine écoute…</p></div>` : query ? (searchKind==='songs'?collectionToolbar()+'<div id="track-results"></div>':catalogItems.length?catalogCards():empty('Aucun résultat pour cette recherche.', 'Essaie un autre nom ou une autre catégorie.', '', 'search'))+paginationButton(searchContinuation,'catalog-more',searching) : `<div class="explore-intro"><span class="explore-symbol">${icon('search')}</span><h2>Une envie, un artiste, un titre.</h2><p>Explore les titres, albums, artistes et playlists publics de YouTube Music. Ta musique reste dans le lecteur Soryn.</p><button class="primary-button" data-focus-search>Rechercher de la musique ${icon('arrow')}</button></div><div class="explore-local"><span>${icon('folder')}</span><div><h3>Ta musique a aussi sa place ici.</h3><p>MP3, M4A, WAV, FLAC… Ajoute tes fichiers à ta bibliothèque.</p></div><button class="secondary-button" data-import-audio>Importer des fichiers</button></div>`);
      break;
    case 'catalog': {
      const page=catalogPage||{tracks:[],title:'YouTube Music'};
      main.innerHTML=`<section class="collection-heading">${page.artworkURL?`<img class="collection-art ${page.kind==='artists'?'artist-portrait':''}" src="${escape(page.artworkURL)}" alt="">`:mosaic(page.tracks,'collection-art')}<div><span class="eyebrow">YOUTUBE MUSIC · ${page.kind==='artists'?'ARTISTE':page.kind==='playlists'?'PLAYLIST':'ALBUM'}</span><h1>${escape(page.title)}</h1><p class="collection-description">${escape(page.subtitle||'Catalogue public YouTube Music')}</p><p class="collection-meta">${page.tracks.length} titre${page.tracks.length>1?'s':''} chargé${page.tracks.length>1?'s':''}</p></div></section><div class="collection-actions"><button class="round-play" id="play-selection" aria-label="Tout écouter" ${page.tracks.length?'':'disabled'}>${icon('play')}</button><button class="icon-button" data-shuffle-selection aria-label="Lecture aléatoire" ${page.tracks.length?'':'disabled'}>${icon('shuffle')}</button><button id="catalog-save" class="secondary-button" ${page.tracks.length?'':'disabled'}>${icon('plus')}Ajouter ${page.tracks.length} titres à une playlist</button></div>${catalogBusy&&!page.tracks.length?'<div class="search-loading"><span class="spinner"></span>Chargement du catalogue…</div>':catalogError?`<div class="notice" role="status">${escape(catalogError)} <button class="secondary-button" id="catalog-retry">Réessayer</button></div>`:collectionToolbar()+'<div id="track-results"></div>'+paginationButton(page.continuation,'catalog-browse-more',catalogBusy)}<p class="notice">Lecture via youtubei.js sur ce PC, Invidious ou le relais préconfiguré. Seuls les fichiers audio complets et validés sont lus. La présence d’un titre au catalogue ne garantit pas sa disponibilité audio.${page.continuation?' Charge les pages suivantes pour ajouter les autres titres de cette sélection.':''}</p>`;
      break;
    }
    case 'library': case 'favorites': case 'downloads': case 'playlist': {
      const playlist = view === 'playlist' ? data.library.playlists.find(p => p.id === selectedPlaylist) : null;
      const title = playlist?.name || ({library:'Ta bibliothèque', favorites:'Tes coups de cœur', downloads:'Sans connexion.'}[view] || 'Playlist supprimée');
      const cover = view==='favorites'?`<div class="collection-art favorite-art">${icon('heart')}</div>`:view==='downloads'?`<div class="collection-art download-art">${icon('download')}</div>`:mosaic(tracks,'collection-art');
      main.innerHTML = `<section class="collection-heading ${view==='favorites'?'favorites-heading':''}">${cover}<div><span class="eyebrow">${view==='playlist'?'PLAYLIST':view==='favorites'?'LES MORCEAUX QUI RESTENT':view==='downloads'?'DISPONIBLE HORS LIGNE':'TA MUSIQUE, AU MÊME ENDROIT'}</span><h1>${escape(title)}</h1>${playlist?.detail?`<p class="collection-description">${escape(playlist.detail)}</p>`:''}<p class="collection-meta"><strong>Soryn</strong><span>·</span>${tracks.length} titre${tracks.length>1?'s':''}<span>·</span>${Math.max(0,Math.round(tracks.reduce((sum,t)=>sum+t.duration,0)/60))} min</p></div></section><div class="collection-actions"><button class="round-play" id="play-selection" aria-label="Tout écouter" title="Tout écouter" ${tracks.length?'':'disabled'}>${icon('play')}</button><button class="icon-button" data-shuffle-selection aria-label="Écouter cette sélection en aléatoire" title="Lecture aléatoire" ${tracks.length?'':'disabled'}>${icon('shuffle')}</button>${view==='playlist'&&playlist?`<button id="download-selection" class="secondary-button" ${downloadBusy?'disabled':''}>${icon('download')}${downloadBusy?'Téléchargement…':'Télécharger'}</button><button id="delete-playlist" class="icon-button" aria-label="Supprimer la playlist" title="Supprimer la playlist">${icon('trash')}</button>`:''}${view==='library'?'<button class="secondary-button" data-import-audio>'+icon('plus')+'Importer des fichiers</button>':''}<span class="collection-action-note">${view==='downloads'?'Ta musique, même sans réseau.':view==='favorites'?'Un peu de toi dans chaque morceau.':''}</span></div>${collectionToolbar()}<div id="track-results"></div>${view==='downloads'?'<p class="notice">Les téléchargements terminés restent sur ce PC, séparés du cache. Retirer un téléchargement ne supprime ni le titre ni tes playlists.</p>':''}`;
      break;
    }
    case 'sync': renderSync(); return;
    case 'account': renderAccount();return;
    case 'settings':
      main.innerHTML = header('À TON IMAGE', 'L’essentiel. Et toi.', 'Soryn pour Windows · ' + data.version) + `<section class="surface"><h2>Ton écoute</h2><div class="setting-row"><span>Vitesse de lecture<small>Vitesse et tonalité liées, comme un vinyle.</small></span><select id="rate" aria-label="Vitesse de lecture">${[0.5,0.75,1,1.25,1.5,2].map(n=>`<option value="${n}" ${audio.playbackRate === n ? 'selected' : ''}>${n}×</option>`).join('')}</select></div><div class="setting-row"><span>Qualité audio<small>Meilleur AAC réellement disponible. Pas de réencodage.</small></span><span>AAC · automatique</span></div><p class="notice">La lecture utilise la sortie audio Windows. Certains titres peuvent être refusés par YouTube ; aucune disponibilité universelle ni qualité 256 kbit/s n’est promise. Les sources en ligne sont préparées et vérifiées avant lecture.</p></section><section class="surface"><h2>Ta bibliothèque, en sécurité</h2><p>Les fichiers importés sont copiés dans le dossier de l’application. La sauvegarde JSON contient les références, playlists, favoris et l’historique, pas les fichiers audio.</p><button class="secondary-button" id="export-backup">Exporter la bibliothèque</button> <button class="secondary-button" id="import-backup">Importer une sauvegarde</button><p class="notice">Les sauvegardes Blusic existantes sont compatibles. L’import fusionne les données sans effacer la bibliothèque actuelle.</p></section><section class="surface"><h2>Pas de compte. Pas de distraction.</h2><p>Aucune publicité ajoutée, aucun outil de mesure d’audience. Tes données restent sur tes appareils. Explorer contacte YouTube Music ; la préparation audio contacte YouTube / Google. La synchronisation iPhone est locale et chiffrée, activée uniquement à ta demande.</p><p>Identité Soryn fournie par le créateur. Quatre instrumentaux originaux du projet. Moteur de bureau Electron, youtubei.js et SABR embarqués ; licences tierces incluses dans le paquet.</p></section>`;
      break;
  }
  if(view==='settings')$('#content').insertAdjacentHTML('beforeend',`<section class="surface"><h2>Sources audio préconfigurées</h2><div class="setting-row"><span>youtubei.js / SABR sur ce PC<small>Résolution embarquée, sans serveur personnel.</small></span><span>Activé</span></div><div class="setting-row"><span>Relais youtubei.js<small>${escape(data.audioSources?.relayHost||'Aucune configuration de build')}</small></span><span>${data.audioSources?.relayConfigured?'Préconfiguré':'Indisponible'}</span></div><div class="setting-row"><span>Invidious<small>${escape(data.audioSources?.invidious?.join(' · ')||'')}</small></span><span>Secours automatique</span></div><p class="notice">Aucune clé à saisir. L’accès application du relais n’expire pas ; aucune clé maître ou d’administration n’est embarquée. Les accès sont essayés en parallèle ; le premier fichier AAC complet et décodable est retenu. La disponibilité des instances et les refus du fournisseur restent indépendants de Soryn.</p></section>`);
  updateCollectionResults(); updateLikes(); updateCurrentRows();
}
function renderSync() {
  $('#content').innerHTML = header('ENSEMBLE, SANS CLOUD', 'Ton univers. Deux écrans.', 'Retrouve tes playlists et tes favoris sur ton iPhone et ton PC.') + `<section class="surface"><h2>${data.syncActive ? 'Prêt à retrouver ton iPhone' : 'Un lien entre tes appareils'}</h2><p>Active le partage uniquement sur un réseau privé de confiance. Aucun compte, aucun abonnement. Les échanges sont chiffrés AES-GCM ; la clé reste sur tes appareils.</p>${!data.syncActive ? '<button id="start-sync" class="primary-button">Activer la synchronisation locale</button>' : `<div class="pair-layout"><div><p class="sync-label">Synchronisation locale active</p><label class="eyebrow" for="sync-address">ADRESSE DE CE PC</label><select id="sync-address" class="address-select">${(syncInfo?.addresses || []).map((a,i)=>`<option value="${i}">${escape(a)}</option>`).join('')}</select><button id="copy-pairing" class="secondary-button">Copier le lien d’appairage</button><p class="notice">Ce lien contient la clé privée d’association. Ne le publie pas et ne le partage qu’avec ton propre iPhone.</p></div>${syncInfo?.qr ? `<img class="pair-qr" src="${syncInfo.qr}" alt="QR du lien d’appairage — à scanner puis copier sur iPhone">` : '<p>Aucune adresse Wi-Fi privée détectée.</p>'}</div><div class="pill-row"><button id="stop-sync" class="pill">Désactiver le partage</button><button id="reset-sync" class="pill">Révoquer les associations</button></div>`}</section><section class="surface"><h2>Une seule fois, pour les associer.</h2><div class="step"><span class="step-number">1</span><p><strong>Sur le PC</strong><br>Active le partage et copie le lien d’appairage. Si Windows le demande, autorise Soryn sur le réseau privé uniquement.</p></div><div class="step"><span class="step-number">2</span><p><strong>Sur l’iPhone · Soryn 1.11 ou ultérieur</strong><br>Réglages → Synchroniser avec Windows → colle le lien → Associer ce PC. Les deux appareils doivent être sur le même Wi-Fi.</p></div><div class="step"><span class="step-number">3</span><p><strong>Continue d’écouter.</strong><br>La bibliothèque se synchronise toutes les 15 secondes lorsque l’app iPhone est ouverte et le partage PC activé.</p></div></section><p class="notice">Partagés : références des titres, playlists, favoris, artistes suivis, paroles enregistrées et historique. Non transférés : fichiers personnels, octets téléchargés, clés d’accès, réglages audio et lecture en cours. Chaque appareil télécharge sa propre copie pour le hors-ligne. L’iPhone fonctionne PC éteint. Pas de synchronisation Internet ni de télécommande de lecture dans cette version.</p>`;
}
function renderAccount(){
  const account=data.account||{signedIn:false,status:'Sans compte · bibliothèque locale'},name=account.account?.displayName;
  $('#content').innerHTML=header('UNIQUEMENT SI TU VEUX SYNCHRONISER',account.signedIn?`Ton espace, ${name}.`:'Ta musique. Avec ou sans compte.','La connexion n’est jamais nécessaire pour écouter, importer ou télécharger.')+`<section class="surface account-surface"><span class="account-portrait">${icon('person')}</span><div><h2>${account.signedIn?escape(name):'Un compte pour retrouver tes sélections.'}</h2><p>${account.signedIn?'Bibliothèque partagée avec tes appareils connectés au même compte.':'Un pseudo et un mot de passe pour synchroniser tes playlists, favoris et références de titres entre iPhone et PC, même sur des réseaux différents.'}</p><p class="account-status" role="status">${escape(account.status)}</p>${account.lastSync?`<p>Dernier échange : ${escape(new Date(account.lastSync).toLocaleTimeString('fr-FR'))}</p>`:''}<div class="account-actions">${account.signedIn?`<button id="account-sync" class="primary-button" ${account.busy?'disabled':''}>${account.busy?'<span class="spinner"></span>':' '+icon('sync')}Synchroniser maintenant</button><button id="account-logout" class="secondary-button" ${account.busy?'disabled':''}>Se déconnecter</button>`:'<button id="account-login" class="primary-button">Se connecter</button><button id="account-register" class="secondary-button">Créer un compte</button>'}</div></div></section><section class="surface"><h2>Le choix reste le tien.</h2><p>Sans connexion, ta bibliothèque reste sur cet appareil et toutes les fonctions d’écoute restent accessibles. Tu peux aussi utiliser <button class="inline-link" data-view="sync">la synchronisation sur le même Wi-Fi</button>, sans compte.</p><p>Se connecter fusionne la bibliothèque locale avec celle du compte : aucun remplacement automatique ni suppression des fichiers personnels. Les fichiers audio et téléchargements ne sont pas transférés ; importe ou télécharge chaque copie sur l’autre appareil.</p><p>Les échanges par compte utilisent HTTPS. Les mots de passe sont hachés côté serveur ; seul un jeton de session est protégé par Windows sur ce PC. Le serveur conserve les métadonnées de bibliothèque : ce n’est pas un chiffrement de bout en bout.</p><p class="notice">La synchronisation Internet nécessite le service de comptes et une base PostgreSQL persistante. Si le service n’est pas encore configuré ou s’il est indisponible, l’écoute et la bibliothèque locales continuent de fonctionner. Sans adresse e-mail, il n’y a pas de récupération automatique de mot de passe : conserve-le dans ton gestionnaire de mots de passe.</p>${account.signedIn?'<button id="account-delete" class="secondary-button danger-button">Supprimer mon compte et ses données serveur</button>':''}</section>`;
}
function accountDialog(kind){
  const registering=kind==='register';
  modal(registering?'Créer ton compte Soryn':'Retrouver ta bibliothèque',`<p>Facultatif : la connexion sert uniquement à synchroniser. Ta bibliothèque locale sera fusionnée avec celle du compte.</p><label class="auth-label" for="account-username">Pseudo</label><input id="account-username" autocomplete="username" minlength="3" maxlength="24" placeholder="Ton pseudo" aria-label="Pseudo"><label class="auth-label" for="account-password">Mot de passe</label><input id="account-password" type="password" autocomplete="${registering?'new-password':'current-password'}" minlength="12" maxlength="128" placeholder="12 caractères minimum" aria-label="Mot de passe">${registering?'<p class="notice">Utilise un mot de passe unique. Sans e-mail, aucun lien de réinitialisation ne peut être envoyé.</p>':''}`,[{label:registering?'Créer et synchroniser':'Se connecter et synchroniser',primary:true,submit:true,onClick:async()=>{
    const username=$('#account-username').value,password=$('#account-password').value,button=$('#modal-actions button');
    if(!/^[a-zA-Z0-9_][a-zA-Z0-9_.-]{2,23}$/.test(username)||password.length<12||password.length>128){toast('Pseudo : 3 à 24 caractères. Mot de passe : 12 à 128 caractères.',true);return;}
    button.disabled=true;button.textContent='Connexion…';
    try{await run('account-'+kind,{username,password});closeModal();await refresh();}catch{}finally{const input=$('#account-password');if(input)input.value='';button.disabled=false;button.textContent=registering?'Créer et synchroniser':'Se connecter et synchroniser';}
  }}]);
}
async function refresh() {
  const scroll = $('#content').scrollTop;
  data = await api('state'); render(); $('#content').scrollTop = scroll; renderQueue(); updateLikes();
}
function updateCurrentRows() {
  document.body.classList.toggle('is-playing', !audio.paused);
  document.querySelectorAll('[data-track-row]').forEach(row => {
    row.classList.toggle('playing-row', row.dataset.trackRow === current?.id);
    row.querySelector('.track-number i').innerHTML = icon(row.dataset.trackRow === current?.id && !audio.paused ? 'wave' : 'play');
  });
}
function setPanel(open, save = true) {
  document.body.classList.toggle('hide-panel', !open);
  $('#queue-toggle').setAttribute('aria-expanded', String(open));
  $('#queue-toggle').setAttribute('aria-pressed', String(open));
  $('#now-panel').inert = !open;
  if (save) preferences.set('panel', open ? 'open' : 'closed');
}
function updateLikes() {
  const liked = isLiked(current);
  for (const id of ['now-like','player-like']) { $('#' + id).classList.toggle('liked', !!liked); $('#' + id).setAttribute('aria-pressed', String(!!liked)); }
}
function renderQueue() {
  const index = current ? queue.findIndex(t => t.id === current.id) : -1;
  const next = index >= 0 ? queue.slice(index + 1) : queue;
  $('#queue-count').textContent = `${next.length} titre${next.length > 1 ? 's' : ''}`;
  $('#queue-list').innerHTML = next.length ? next.slice(0,30).map(t=>`<button class="queue-item" data-queue-play="${escape(t.id)}"><img src="${escape(art(t))}" alt=""><div><strong>${escape(t.title)}</strong><small>${escape(t.artist)}</small></div><span>${clock(t.duration)}</span></button>`).join('') : '<p class="muted">Un peu de silence avant la suite.</p>';
}
function updateTransport() {
  $('#play').innerHTML = loading ? '<span class="spinner"></span>' : icon(audio.paused ? 'play' : 'pause');
  $('#play').setAttribute('aria-label', loading ? 'Annuler la préparation' : audio.paused ? 'Lecture' : 'Pause');
  updateCurrentRows();
}
async function flushListening() {
  if (current && sessionID && listened > 0) { const seconds = Math.min(60, listened); listened = 0; await api('record', {id: sessionID, trackID: current.id, seconds}).catch(() => {}); }
}
async function play(track, selection) {
  if (!track) return;
  const generation = ++playGeneration;
  if (loading) await api('cancel');
  await flushListening(); audio.pause(); audio.removeAttribute('src'); audio.load();
  current = track; if (selection) queue = selection;
  if (!queue.some(t => t.id === track.id)) queue.push(track);
  sessionID = crypto.randomUUID().toUpperCase(); listened = 0; lastTick = 0; loading = true;
  $('#player-title').textContent = $('#now-title').textContent = track.title;
  $('#player-artist').textContent = 'Préparation audio…'; $('#now-artist').textContent = track.artist;
  $('#player-art').src = $('#now-art').src = art(track);
  $('#ambient-art').src = art(track);
  document.body.classList.add('has-track');
  $('#elapsed').textContent = '0:00'; $('#duration').textContent = clock(track.duration); $('#seek').value = 0; paintRange($('#seek'));
  updateTransport(); updateLikes(); renderQueue();
  try {
    if (!data.available.includes(track.id)) toast('Préparation du fichier audio complet…', false, true);
    const result = await api('play', track);
    if (generation !== playGeneration) return;
    current = result.track; queue = queue.map(t => t.location === track.location && t.source === track.source ? current : t);
    audio.src = result.url; audio.preservesPitch = false;
    audio.playbackRate = data.library.settings.playbackRate || 1;
    await audio.play();
    $('#audio-quality').textContent = result.offline ? 'FICHIER LOCAL · HORS LIGNE' : `AAC · ${Math.round(result.bitrate / 1000)} KBIT/S`;
    $('#audio-quality').title=result.offline?'Fichier disponible sur ce PC':result.source||'Audio en ligne';
    $('#player-artist').textContent = current.artist; $('#toast').hidden = true;
    if ('mediaSession' in navigator) navigator.mediaSession.metadata = new MediaMetadata({title: current.title, artist: current.artist, album: current.album, artwork: [{src: art(current)}]});
  } catch (error) {
    if (generation !== playGeneration) return;
    $('#player-artist').textContent = 'Lecture indisponible · réessaie';
    toast(error.message.replace(/^Error invoking remote method '[^']+': Error: /,''), true);
  } finally { if (generation === playGeneration) { loading = false; updateTransport(); renderQueue(); } }
}
async function cancelPreparation() { if(downloadBusy)downloadCancelled=true; playGeneration++; await api('cancel'); loading = false; updateTransport(); toast('Préparation annulée.'); }
function toggle() {
  if (loading) return cancelPreparation();
  if (!current) return play(data.library.tracks[0], data.library.tracks);
  if (!audio.src) return play(current);
  if (audio.paused) audio.play().catch(e=>toast(e.message,true)); else audio.pause();
}
function next(previous = false) {
  if (!queue.length) return;
  let index = queue.findIndex(t=>t.id === current?.id);
  if (previous && audio.currentTime > 3) { audio.currentTime = 0; return; }
  const choices = queue.filter(t=>t.id !== current?.id);
  if (shuffle && !previous && choices.length) return play(choices[Math.floor(Math.random()*choices.length)]);
  index += previous ? -1 : 1;
  if (index >= queue.length) { if (!repeat) { audio.pause(); return; } index = 0; }
  if (index < 0) index = repeat ? queue.length - 1 : 0;
  play(queue[index]);
}
function modal(title, content, actions = []) {
  $('#modal').classList.remove('lyrics-dialog');
  $('#modal-content').innerHTML = `<h2>${escape(title)}</h2>${content}`;
  $('#modal-actions').replaceChildren();
  for (const action of actions) { const button = document.createElement('button'); button.type = action.submit ? 'submit' : 'button'; button.className = action.primary ? 'primary-button' : 'secondary-button'; button.textContent = action.label; button.onclick = async e => { e.preventDefault(); await action.onClick(); }; $('#modal-actions').append(button); }
  $('#modal').showModal();
  $('#modal input')?.focus();
}
function closeModal() { $('#modal').close(); }
function createPlaylist() {
  modal('Une nouvelle parenthèse.', '<p>Donne un nom à ta playlist.</p><input id="playlist-name" placeholder="Nuits bleues, matin calme…" maxlength="200" aria-label="Nom de la playlist">', [{label:'Créer la playlist', primary:true, submit:true, onClick:async()=>{
    const name = $('#playlist-name').value.trim(); if (!name) return;
    const p = await run('playlist-create',name); closeModal(); await refresh(); go('playlist:'+p.id);
  }}]);
}
function addToPlaylist(track) {
  closeModal();
  modal('Garder ce morceau.', `<p>${escape(track.title)}</p>${data.library.playlists.map(p=>`<button type="button" class="modal-playlist" data-add-to="${escape(p.id)}">${icon('playlist')}${escape(p.name)}</button>`).join('') || '<p>Crée d’abord une playlist avec le bouton + de la barre latérale.</p>'}`);
  $('#modal-content').querySelectorAll('[data-add-to]').forEach(button => { button.onclick = async () => { await run('playlist-add', {playlistID:button.dataset.addTo,track}, 'Ajouté à ta sélection.'); closeModal(); await refresh(); }; });
}
function trackMenu(track) {
  const downloaded = data.downloads.includes(track.id), local = data.available.includes(track.id);
  modal(track.title, `<p>${escape(track.artist)}</p>`, [
    {label:'Ajouter à une playlist', onClick:()=>addToPlaylist(track)},
    ...(!local || downloaded ? [{label:downloaded ? 'Retirer le téléchargement' : 'Télécharger', primary:true, onClick:async()=>{
      closeModal(); if(downloaded) { await run('download-remove',track.id,'Téléchargement retiré. Titre conservé.'); await refresh(); }
      else { const saved = await run('save-track',track); await download([saved]); }
    }}] : []),
    ...(view === 'playlist' ? [{label:'Retirer de cette playlist', onClick:async()=>{await run('playlist-remove-track',{playlistID:selectedPlaylist,trackID:track.id});closeModal();await refresh();}}] : [])
  ]);
}
async function download(tracks) {
  if (downloadBusy) return toast('Un téléchargement est déjà en cours.');
  downloadBusy = true; downloadCancelled = false; let done = 0, failures = [];
  for (const t of [...new Map(tracks.map(t=>[t.id,t])).values()]) {
    if(downloadCancelled)break;
    toast(`Téléchargement : ${t.title}…`,false,true);
    try { await api('download',t.id); done++; } catch(e) { failures.push(`${t.title} : ${e.message}`); }
  }
  downloadBusy = false; await refresh();
  toast(`${done} titre(s) disponible(s) hors ligne.${failures.length ? ' '+failures.length+' échec(s) : '+failures.join(' · ') : ''}`,!!failures.length);
}

document.addEventListener('click', async event => {
  const kind=event.target.closest('[data-catalog-kind]');if(kind){searchKind=kind.dataset.catalogKind;collectionQuery='';if(query)await searchCatalog();else render();return;}
  const entity=event.target.closest('[data-catalog-id]');if(entity){const item=catalogItems.find(e=>e.id===entity.dataset.catalogId);if(item)await openCatalog(item);return;}
  const tab = event.target.closest('[data-home-filter]'); if(tab) { homeFilter = tab.dataset.homeFilter; render(); return; }
  const layout = event.target.closest('[data-layout]'); if(layout) { collectionLayout = layout.dataset.layout; preferences.set('layout',collectionLayout); updateCollectionResults(); updateCurrentRows(); return; }
  if(event.target.closest('[data-create-playlist]')) { createPlaylist(); return; }
  if(event.target.closest('[data-import-audio]')) { await importAudio(); return; }
  if(event.target.closest('[data-focus-search]')) { $('#search').focus(); return; }
  if(event.target.closest('[data-clear-filter]')) { collectionQuery='';$('#collection-search').value='';updateCollectionResults();$('#collection-search').focus();return; }
  if(event.target.closest('[data-shuffle-selection]')) { const tracks=visibleTracks(); if(tracks.length){shuffle=true;$('#shuffle').setAttribute('aria-pressed','true');play(tracks[Math.floor(Math.random()*tracks.length)],tracks);}return; }
  const nav = event.target.closest('button[data-view], a[data-view]'); if(nav) {event.preventDefault();go(nav.dataset.view);return;}
  const playButton = event.target.closest('[data-play]'); if(playButton) {play(find(playButton.dataset.play),view==='home'?data.library.tracks:visibleTracks());return;}
  const like = event.target.closest('[data-like]'); if(like) {await run('favorite',find(like.dataset.like));await refresh();return;}
  const menu = event.target.closest('[data-menu]'); if(menu) {trackMenu(find(menu.dataset.menu));return;}
  const queued = event.target.closest('[data-queue-play]'); if(queued) {play(find(queued.dataset.queuePlay));return;}
  switch(event.target.closest('button')?.id) {
    case 'hero-play':play(find($('#hero-play').dataset.featuredId),data.library.tracks);break;
    case 'play-selection':play(visibleTracks()[0],visibleTracks());break;
    case 'download-selection':download(viewTracks());break;
    case 'delete-playlist':modal('Supprimer cette playlist ?', '<p>Les morceaux et les fichiers audio seront conservés.</p>',[{label:'Supprimer',primary:true,onClick:async()=>{await run('playlist-delete',selectedPlaylist);closeModal();await refresh();go('library');}}]);break;
    case 'start-sync':try {syncInfo=await run('sync-start');data.syncActive=true;render();}catch{}break;
    case 'copy-pairing':await run('copy-pairing',Number($('#sync-address').value),'Lien d’appairage copié. Garde-le privé.');break;
    case 'stop-sync':await run('sync-stop');syncInfo=null;await refresh();break;
    case 'reset-sync':modal('Révoquer les associations ?', '<p>Les anciens liens ne fonctionneront plus. Tu pourras associer à nouveau ton iPhone. Aucune musique ne sera supprimée.</p>',[{label:'Révoquer',primary:true,onClick:async()=>{await run('sync-reset');closeModal();syncInfo=null;await refresh();}}]);break;
    case 'export-backup':await run('backup-export',undefined,'Export terminé si un emplacement a été choisi.');break;
    case 'import-backup':await run('backup-import');await refresh();break;
    case 'account-login':accountDialog('login');break;
    case 'account-register':accountDialog('register');break;
    case 'account-sync':await run('account-sync');await refresh();break;
    case 'account-logout':await run('account-logout');await refresh();break;
    case 'account-delete':modal('Supprimer le compte ?', '<p>Les données synchronisées seront effacées du serveur et toutes les sessions révoquées. Tes fichiers et ta bibliothèque sur ce PC seront conservés.</p><input id="delete-account-password" type="password" autocomplete="current-password" aria-label="Confirmer avec le mot de passe" placeholder="Ton mot de passe">',[{label:'Supprimer le compte',primary:true,onClick:async()=>{try{await run('account-delete',{password:$('#delete-account-password').value});closeModal();await refresh();}finally{if($('#delete-account-password'))$('#delete-account-password').value='';}}}]);break;
    case 'catalog-more':await searchCatalog(true);break;
    case 'catalog-browse-more':await openCatalog(catalogPage,true);break;
    case 'catalog-retry':await openCatalog(catalogPage);break;
    case 'catalog-save':if(catalogPage?.tracks.length){const p=await run('catalog-save',{name:catalogPage.title,tracks:catalogPage.tracks},'Sélection ajoutée à ta bibliothèque.');await refresh();go('playlist:'+p.id);}break;
  }
});
async function searchCatalog(more=false) {
  const generation=++searchGeneration,kind=searchKind;
  if(!more){searchResults=[];catalogItems=[];searchContinuation=null;}
  searching=true;if(view!=='explore')go('explore');else render();
  try {
    const page=await run('catalog-search',{query,kind,continuation:more?searchContinuation:undefined});
    if(generation!==searchGeneration)return;
    const known=new Set(searchResults.map(t=>t.location));searchResults.push(...page.tracks.filter(t=>!known.has(t.location)));
    const ids=new Set(catalogItems.map(e=>e.id));catalogItems.push(...page.items.filter(e=>!ids.has(e.id)));searchContinuation=page.continuation;
  }catch{if(generation===searchGeneration)searchContinuation=null;}
  finally{if(generation===searchGeneration){searching=false;if(view==='explore')render();}}
}
async function openCatalog(item,more=false) {
  if(catalogBusy)return;catalogBusy=true;catalogError='';
  if(!more){catalogPage={...item,tracks:[]};collectionQuery='';go('catalog');}else render();
  const id=item.id;
  try{
    const result=await run('catalog-browse',{id,kind:item.kind,continuation:more?item.continuation:undefined});
    if(catalogPage.id!==id)return;
    const known=new Set(catalogPage.tracks.map(t=>t.location));catalogPage={...catalogPage,...result,title:result.title==='Sélection YouTube Music'?item.title:result.title,artworkURL:result.artworkURL||item.artworkURL,tracks:[...catalogPage.tracks,...result.tracks.filter(t=>!known.has(t.location))]};
  }catch(error){catalogError=error.message;}
  finally{catalogBusy=false;if(view==='catalog')render();}
}
$('#search-form').onsubmit = async event => {
  event.preventDefault(); const value = $('#search').value.trim(); if(value.length<2)return;
  query=value;await searchCatalog();
};
$('#new-playlist').onclick=createPlaylist;
async function importAudio() { try{const result=await run('import-audio');toast(`${result.count} fichier(s) importé(s). ${result.errors.join(' · ')}`,!!result.errors.length);await refresh();}catch{} }
$('#import-button').onclick=importAudio;
$('#back').onclick=()=>{if(navIndex>0)go(navigation[--navIndex],false);};
$('#forward').onclick=()=>{if(navIndex<navigation.length-1)go(navigation[++navIndex],false);};
$('#play').onclick=toggle;$('#previous').onclick=()=>next(true);$('#next').onclick=()=>next();
$('#shuffle').onclick=()=>{shuffle=!shuffle;$('#shuffle').setAttribute('aria-pressed',String(shuffle));};
$('#repeat').onclick=()=>{repeat=!repeat;$('#repeat').setAttribute('aria-pressed',String(repeat));};
$('#queue-toggle').onclick=()=>setPanel(document.body.classList.contains('hide-panel'));
$('#panel-close').onclick=()=>{setPanel(false);$('#queue-toggle').focus();};
for(const id of ['now-like','player-like'])$('#'+id).onclick=async()=>{if(current){await run('favorite',current);await refresh();}};
function paintRange(node) { node.style.setProperty('--progress',`${(Number(node.value)-Number(node.min))/(Number(node.max)-Number(node.min))*100}%`); }
$('#seek').oninput=()=>{paintRange($('#seek'));if(Number.isFinite(audio.duration)&&audio.duration>0)audio.currentTime=audio.duration*Number($('#seek').value)/100;};
$('#volume').oninput=()=>{audio.volume=Number($('#volume').value);paintRange($('#volume'));};
$('#volume').onchange=()=>api('settings',{volume:audio.volume,playbackRate:audio.playbackRate});
document.addEventListener('input',event=>{if(event.target.id==='collection-search'){collectionQuery=event.target.value;updateCollectionResults();updateCurrentRows();}});
document.addEventListener('change',event=>{
  if(event.target.id==='rate'){audio.playbackRate=Number(event.target.value);audio.preservesPitch=false;api('settings',{volume:audio.volume,playbackRate:audio.playbackRate});}
  if(event.target.id==='collection-sort'){collectionSort=event.target.value;preferences.set('sort',collectionSort);updateCollectionResults();updateCurrentRows();}
});
$('#lyrics').onclick=()=>{modal(current?.title || 'Les paroles',`<span class="eyebrow">${escape(current?.artist || 'SORYN')}</span><p class="lyrics-content">${escape(current?.lyrics || (current?.source==='bundled' ? 'Un instrumental.\nJuste les notes.' : 'Aucune parole enregistrée pour ce titre.\nLes paroles sauvegardées sur l’iPhone peuvent être synchronisées.'))}</p><p class="lyrics-note">Paroles enregistrées · affichage non synchronisé</p>`);$('#modal').classList.add('lyrics-dialog');};
$('#modal-close').onclick=closeModal;$('#modal-form').onsubmit=event=>event.preventDefault();
for(const action of ['minimize','maximize','close'])$('#'+action).onclick=()=>api(action);
audio.onplay=()=>{lastTick=performance.now();updateTransport();};audio.onpause=()=>{lastTick=0;updateTransport();flushListening();};
audio.onended=()=>{flushListening();next();};
audio.onerror=()=>{if(audio.getAttribute('src'))toast('Le décodeur Windows ne peut pas lire ce fichier, ou le fichier est incomplet.',true);updateTransport();};
audio.ontimeupdate=()=>{
  const duration=audio.duration;
  $('#elapsed').textContent=clock(audio.currentTime);if(Number.isFinite(duration)){$('#duration').textContent=clock(duration);$('#seek').value=duration?audio.currentTime/duration*100:0;paintRange($('#seek'));}
  const now=performance.now();if(!audio.paused&&lastTick){listened+=Math.min(2,(now-lastTick)/1000);if(listened>=15)flushListening();}lastTick=audio.paused?0:now;
};
document.addEventListener('keydown',event=>{
  const typing=['INPUT','TEXTAREA','SELECT'].includes(event.target.tagName);
  if(event.ctrlKey&&event.key.toLowerCase()==='k'){event.preventDefault();$('#search').focus();}
  if(event.code==='Space'&&!typing&&!$('#modal').open){event.preventDefault();toggle();}
  if(event.altKey&&event.key==='ArrowRight'){event.preventDefault();next();}
  if(event.altKey&&event.key==='ArrowLeft'){event.preventDefault();next(true);}
  if(event.key==='Escape'&&!$('#modal').open&&!document.body.classList.contains('hide-panel'))setPanel(false);
});
if('mediaSession'in navigator){navigator.mediaSession.setActionHandler('play',()=>audio.play());navigator.mediaSession.setActionHandler('pause',()=>audio.pause());navigator.mediaSession.setActionHandler('nexttrack',()=>next());navigator.mediaSession.setActionHandler('previoustrack',()=>next(true));navigator.mediaSession.setActionHandler('seekto',event=>{if(event.seekTime!=null)audio.currentTime=event.seekTime;});}
document.addEventListener('error',event=>{if(event.target.tagName==='IMG'&&!event.target.dataset.fallback){event.target.dataset.fallback='true';event.target.src='../assets/cover-night.png';}},true);
window.addEventListener('unhandledrejection',event=>{toast(event.reason?.message||'Une action a échoué.',true);});
hydrate();
setPanel(preferences.get('panel','closed')==='open',false);
try {await refresh();audio.volume=data.library.settings.volume??0.8;$('#volume').value=audio.volume;paintRange($('#volume'));paintRange($('#seek'));audio.playbackRate=data.library.settings.playbackRate||1;}
catch(error){toast('Impossible d’ouvrir la bibliothèque : '+error.message,true);}
window.soryn.onChange(()=>refresh().catch(error=>toast(error.message,true)));
