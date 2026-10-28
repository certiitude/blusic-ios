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
};
const icon = name => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${icons[name] || icons.wave}</svg>`;
function hydrate(scope = document) { scope.querySelectorAll('[data-icon]').forEach(node => { node.innerHTML = icon(node.dataset.icon); }); }
const escape = text => String(text ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const clock = seconds => `${Math.floor(Math.max(0, seconds || 0) / 60)}:${String(Math.floor(Math.max(0, seconds || 0) % 60)).padStart(2, '0')}`;
const art = track => data?.artwork?.[track?.id] || (/^https:\/\//i.test(track?.artworkURL || '') ? track.artworkURL : `../assets/${['cover-night','cover-rain','cover-orbit','cover-metro'].includes(track?.artwork) ? track.artwork : 'cover-night'}.png`);
const api = (action, input) => window.soryn.call(action, input);
let data, view = 'home', selectedPlaylist, searchResults = [], query = '', searching = false, searchGeneration = 0;
let queue = [], current, loading = false, playGeneration = 0, shuffle = false, repeat = false, toastTimer, downloadBusy = false, downloadCancelled = false;
let sessionID, listened = 0, lastTick = 0, navigation = ['home'], navIndex = 0, syncInfo;
const audio = $('#audio');
const find = id => data.library.tracks.find(t => t.id === id) || searchResults.find(t => t.id === id) || queue.find(t => t.id === id);
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
  return `<table class="track-table"><thead><tr><th>#</th><th>TITRE</th><th class="album-column">ALBUM</th><th>${icon('clock')}</th><th></th></tr></thead><tbody>${tracks.map((t, index) => `<tr class="${current?.id === t.id ? 'playing-row' : ''}"><td>${current?.id === t.id && !audio.paused ? icon('wave') : String(index + 1).padStart(2,'0')}</td><td><button class="track-cell" data-play="${escape(t.id)}"><img src="${escape(art(t))}" alt="" loading="lazy"><div><strong>${escape(t.title)}</strong><small>${escape(t.artist || 'Artiste inconnu')}${data.available.includes(t.id) ? ' · Hors ligne' : ''}</small></div></button></td><td class="album-column">${escape(t.album || '—')}</td><td>${clock(t.duration)}</td><td><button class="icon-button ${isLiked(t) ? 'liked' : ''}" data-like="${escape(t.id)}" aria-label="${isLiked(t) ? 'Retirer des favoris' : 'Ajouter aux favoris'}">${icon('heart')}</button><button class="icon-button" data-menu="${escape(t.id)}" aria-label="Options pour ${escape(t.title)}">${icon('more')}</button></td></tr>`).join('')}</tbody></table>`;
}
function cards(tracks) { return `<div class="album-grid">${tracks.map(t => `<button class="album-card" data-play="${escape(t.id)}"><div class="album-cover"><img src="${escape(art(t))}" alt="" loading="lazy"><span class="cover-play">${icon('play')}</span></div><h3>${escape(t.title)}</h3><p>${escape(t.artist)} · ${clock(t.duration)}</p></button>`).join('')}</div>`; }
function originalNote() { return `<p class="original-note">${icon('wave')}Les quatre instrumentaux Soryn Studio sont des créations originales du projet.</p>`; }
function go(next, push = true) {
  if (next.startsWith('playlist:')) { selectedPlaylist = next.slice(9); view = 'playlist'; } else view = next;
  if (push && navigation[navIndex] !== next) { navigation = navigation.slice(0, navIndex + 1); navigation.push(next); navIndex++; }
  $('#content').scrollTop = 0; render();
}
function viewTracks() {
  const tracks = data.library.tracks;
  if (view === 'favorites') return tracks.filter(t => data.library.favorites.includes(t.id));
  if (view === 'downloads') return tracks.filter(t => data.available.includes(t.id));
  if (view === 'explore') return searchResults;
  if (view === 'playlist') return (data.library.playlists.find(p => p.id === selectedPlaylist)?.trackIDs || []).map(find).filter(Boolean);
  return tracks;
}
function render() {
  if (!data) return;
  document.querySelectorAll('#navigation [data-view]').forEach(b => { b.classList.toggle('active', b.dataset.view === view); b.setAttribute('aria-current', b.dataset.view === view ? 'page' : 'false'); });
  $('#sync-dot').classList.toggle('on', data.syncActive);
  $('#back').disabled = navIndex === 0; $('#forward').disabled = navIndex >= navigation.length - 1;
  $('#playlist-navigation').innerHTML = data.library.playlists.map(p => `<button class="playlist-link" data-view="playlist:${escape(p.id)}"><i>${icon('playlist')}</i><span>${escape(p.name)}</span></button>`).join('');
  const main = $('#content'), tracks = viewTracks();
  switch (view) {
    case 'home': {
      const originals = data.library.tracks.filter(t => t.source === 'bundled').slice(0,4), recentIDs = [...new Set([...data.library.history].reverse().map(e => e.trackID))];
      const favorites = data.library.tracks.filter(t => data.library.favorites.includes(t.id)).slice(0,4);
      main.innerHTML = `<p class="greeting">BIENVENUE DANS TON UNIVERS</p><div class="hero"><div class="hero-copy"><span class="eyebrow">UNE PAUSE. UNE ÉMOTION. UN MORCEAU.</span><h1>Écoutez<br>le <em>moment.</em></h1><p>Un peu moins de bruit.<br>Une expérience musicale plus proche de vous.</p><button id="hero-play" class="primary-button"><i>${icon('play')}</i>Écouter maintenant</button></div><img class="hero-ghost" src="../assets/mascot.png" alt=""><span class="hero-bottom">LA MUSIQUE. RIEN D’AUTRE.</span></div>
        <div class="section-header"><div><h2>${favorites.length ? 'Tes coups de cœur' : 'Premières ondes'}</h2><p>${favorites.length ? 'Les morceaux qui restent.' : 'Quatre escales. Ton premier voyage.'}</p></div><button class="text-button" data-view="${favorites.length ? 'favorites' : 'library'}">Tout voir ${'↗'}</button></div>${cards(favorites.length ? favorites : originals)}
        <div class="section-header"><h2>À portée d’écoute</h2><span class="eyebrow">TON ESPACE, SIMPLEMENT</span></div><div class="quick-grid">${(recentIDs.length ? recentIDs.map(find).filter(Boolean).slice(0,4) : originals).map(t => `<button class="quick-card" data-play="${escape(t.id)}"><img src="${escape(art(t))}" alt=""><div><strong>${escape(t.title)}</strong><small>${escape(t.artist)}</small></div><i>${icon('play')}</i></button>`).join('')}</div>${originalNote()}`;
      break;
    }
    case 'explore':
      main.innerHTML = header('DÉCOUVRIR', 'Une envie de musique ?', 'Recherche de chansons sur YouTube Music · sans connexion au compte Google') + `<div class="pill-row"><span class="pill active">Chansons</span><span class="pill">Audio AAC disponible selon la source</span></div>` + (searching ? `<p class="search-status"><span class="spinner"></span> À la recherche de « ${escape(query)} »…</p>` : query ? `<p class="search-status">${searchResults.length} résultat${searchResults.length > 1 ? 's' : ''} pour « ${escape(query)} »</p>${table(searchResults)}` : empty('Suis ton intuition.', 'Un titre que tu connais par cœur, un artiste à découvrir. Commence par la recherche en haut de l’écran.', '', 'search'));
      break;
    case 'library': case 'favorites': case 'downloads': case 'playlist': {
      const playlist = view === 'playlist' ? data.library.playlists.find(p => p.id === selectedPlaylist) : null;
      const title = playlist?.name || ({library:'Ta bibliothèque', favorites:'Tes coups de cœur', downloads:'Toujours avec toi.'}[view] || 'Playlist supprimée');
      const action = tracks.length ? `<button class="primary-button" id="play-selection"><i>${icon('play')}</i>Tout écouter</button>` : '';
      main.innerHTML = header(view === 'downloads' ? 'HORS LIGNE' : view === 'playlist' ? 'TA SÉLECTION' : 'TON UNIVERS', title, `${tracks.length} titre${tracks.length > 1 ? 's' : ''} · ${clock(tracks.reduce((a,t) => a + t.duration,0))}`, action) + (view === 'playlist' && playlist ? `<div class="pill-row"><button id="download-selection" class="pill">${downloadBusy ? 'Téléchargement en cours…' : 'Télécharger cette sélection'}</button><button id="delete-playlist" class="pill">Supprimer la playlist</button></div>` : '') + table(tracks) + (view === 'downloads' ? '<p class="notice">Fichiers personnels, instrumentaux embarqués et téléchargements terminés. Les téléchargements restent sur ce PC, séparés du cache temporaire ; retirer un téléchargement ne supprime ni le titre ni tes playlists.</p>' : '');
      break;
    }
    case 'sync': renderSync(); return;
    case 'settings':
      main.innerHTML = header('À TON IMAGE', 'L’essentiel. Et toi.', 'Soryn pour Windows · ' + data.version) + `<section class="surface"><h2>Ton écoute</h2><div class="setting-row"><span>Vitesse de lecture<small>Vitesse et tonalité liées, comme un vinyle.</small></span><select id="rate" aria-label="Vitesse de lecture">${[0.5,0.75,1,1.25,1.5,2].map(n=>`<option value="${n}" ${audio.playbackRate === n ? 'selected' : ''}>${n}×</option>`).join('')}</select></div><div class="setting-row"><span>Qualité audio<small>Meilleur AAC réellement disponible. Pas de réencodage.</small></span><span>AAC · automatique</span></div><p class="notice">La lecture utilise la sortie audio Windows. Certains titres peuvent être refusés par YouTube ; aucune disponibilité universelle ni qualité 256 kbit/s n’est promise. Les sources en ligne sont préparées et vérifiées avant lecture.</p></section><section class="surface"><h2>Ta bibliothèque, en sécurité</h2><p>Les fichiers importés sont copiés dans le dossier de l’application. La sauvegarde JSON contient les références, playlists, favoris et l’historique, pas les fichiers audio.</p><button class="secondary-button" id="export-backup">Exporter la bibliothèque</button> <button class="secondary-button" id="import-backup">Importer une sauvegarde</button><p class="notice">Les sauvegardes Blusic existantes sont compatibles. L’import fusionne les données sans effacer la bibliothèque actuelle.</p></section><section class="surface"><h2>Pas de compte. Pas de distraction.</h2><p>Aucune publicité ajoutée, aucun outil de mesure d’audience. Tes données restent sur tes appareils. Explorer contacte YouTube Music ; la préparation audio contacte YouTube / Google. La synchronisation iPhone est locale et chiffrée, activée uniquement à ta demande.</p><p>Identité Soryn fournie par le créateur. Quatre instrumentaux originaux du projet. Moteur de bureau Electron, youtubei.js et SABR embarqués ; licences tierces incluses dans le paquet.</p></section>`;
      break;
  }
  updateLikes();
}
function renderSync() {
  $('#content').innerHTML = header('ENSEMBLE, SANS CLOUD', 'Ton univers. Deux écrans.', 'Retrouve tes playlists et tes favoris sur ton iPhone et ton PC.') + `<section class="surface"><h2>${data.syncActive ? 'Prêt à retrouver ton iPhone' : 'Un lien entre tes appareils'}</h2><p>Active le partage uniquement sur un réseau privé de confiance. Aucun compte, aucun abonnement. Les échanges sont chiffrés AES-GCM ; la clé reste sur tes appareils.</p>${!data.syncActive ? '<button id="start-sync" class="primary-button">Activer la synchronisation locale</button>' : `<div class="pair-layout"><div><p class="sync-label">Synchronisation locale active</p><label class="eyebrow" for="sync-address">ADRESSE DE CE PC</label><select id="sync-address" class="address-select">${(syncInfo?.addresses || []).map((a,i)=>`<option value="${i}">${escape(a)}</option>`).join('')}</select><button id="copy-pairing" class="secondary-button">Copier le lien d’appairage</button><p class="notice">Ce lien contient la clé privée d’association. Ne le publie pas et ne le partage qu’avec ton propre iPhone.</p></div>${syncInfo?.qr ? `<img class="pair-qr" src="${syncInfo.qr}" alt="QR du lien d’appairage — à scanner puis copier sur iPhone">` : '<p>Aucune adresse Wi-Fi privée détectée.</p>'}</div><div class="pill-row"><button id="stop-sync" class="pill">Désactiver le partage</button><button id="reset-sync" class="pill">Révoquer les associations</button></div>`}</section><section class="surface"><h2>Une seule fois, pour les associer.</h2><div class="step"><span class="step-number">1</span><p><strong>Sur le PC</strong><br>Active le partage et copie le lien d’appairage. Si Windows le demande, autorise Soryn sur le réseau privé uniquement.</p></div><div class="step"><span class="step-number">2</span><p><strong>Sur l’iPhone · Soryn 1.11 ou ultérieur</strong><br>Réglages → Synchroniser avec Windows → colle le lien → Associer ce PC. Les deux appareils doivent être sur le même Wi-Fi.</p></div><div class="step"><span class="step-number">3</span><p><strong>Continue d’écouter.</strong><br>La bibliothèque se synchronise toutes les 15 secondes lorsque l’app iPhone est ouverte et le partage PC activé.</p></div></section><p class="notice">Partagés : références des titres, playlists, favoris, artistes suivis, paroles enregistrées et historique. Non transférés : fichiers personnels, octets téléchargés, clés d’accès, réglages audio et lecture en cours. Chaque appareil télécharge sa propre copie pour le hors-ligne. L’iPhone fonctionne PC éteint. Pas de synchronisation Internet ni de télécommande de lecture dans cette version.</p>`;
}
async function refresh() {
  data = await api('state'); render(); renderQueue(); updateLikes();
}
function updateLikes() {
  const liked = isLiked(current);
  for (const id of ['now-like','player-like']) { $('#' + id).classList.toggle('liked', !!liked); $('#' + id).setAttribute('aria-pressed', String(!!liked)); }
}
function renderQueue() {
  $('#queue-count').textContent = `${queue.length} titre${queue.length > 1 ? 's' : ''}`;
  const index = current ? queue.findIndex(t => t.id === current.id) : -1;
  const next = index >= 0 ? queue.slice(index + 1) : queue;
  $('#queue-list').innerHTML = next.length ? next.slice(0,30).map(t=>`<button class="queue-item" data-queue-play="${escape(t.id)}"><img src="${escape(art(t))}" alt=""><div><strong>${escape(t.title)}</strong><small>${escape(t.artist)}</small></div><span>${clock(t.duration)}</span></button>`).join('') : '<p class="muted">Un peu de silence avant la suite.</p>';
}
function updateTransport() {
  $('#play').innerHTML = loading ? '<span class="spinner"></span>' : icon(audio.paused ? 'play' : 'pause');
  $('#play').setAttribute('aria-label', loading ? 'Annuler la préparation' : audio.paused ? 'Lecture' : 'Pause');
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
  $('#elapsed').textContent = '0:00'; $('#duration').textContent = clock(track.duration); $('#seek').value = 0;
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
  const nav = event.target.closest('[data-view]'); if(nav) {event.preventDefault();go(nav.dataset.view);return;}
  const playButton = event.target.closest('[data-play]'); if(playButton) {play(find(playButton.dataset.play),viewTracks());return;}
  const like = event.target.closest('[data-like]'); if(like) {await run('favorite',find(like.dataset.like));await refresh();return;}
  const menu = event.target.closest('[data-menu]'); if(menu) {trackMenu(find(menu.dataset.menu));return;}
  const queued = event.target.closest('[data-queue-play]'); if(queued) {play(find(queued.dataset.queuePlay));return;}
  switch(event.target.closest('button')?.id) {
    case 'hero-play':play(data.library.tracks.find(t=>data.library.favorites.includes(t.id)) || data.library.tracks[0],data.library.tracks);break;
    case 'play-selection':play(viewTracks()[0],viewTracks());break;
    case 'download-selection':download(viewTracks());break;
    case 'delete-playlist':modal('Supprimer cette playlist ?', '<p>Les morceaux et les fichiers audio seront conservés.</p>',[{label:'Supprimer',primary:true,onClick:async()=>{await run('playlist-delete',selectedPlaylist);closeModal();await refresh();go('library');}}]);break;
    case 'start-sync':try {syncInfo=await run('sync-start');data.syncActive=true;render();}catch{}break;
    case 'copy-pairing':await run('copy-pairing',Number($('#sync-address').value),'Lien d’appairage copié. Garde-le privé.');break;
    case 'stop-sync':await run('sync-stop');syncInfo=null;await refresh();break;
    case 'reset-sync':modal('Révoquer les associations ?', '<p>Les anciens liens ne fonctionneront plus. Tu pourras associer à nouveau ton iPhone. Aucune musique ne sera supprimée.</p>',[{label:'Révoquer',primary:true,onClick:async()=>{await run('sync-reset');closeModal();syncInfo=null;await refresh();}}]);break;
    case 'export-backup':await run('backup-export',undefined,'Export terminé si un emplacement a été choisi.');break;
    case 'import-backup':await run('backup-import');await refresh();break;
  }
});
$('#search-form').onsubmit = async event => {
  event.preventDefault(); const value = $('#search').value.trim(); if(value.length<2)return;
  query=value; searching=true; const generation=++searchGeneration;go('explore');
  try {const results=await run('search',query);if(generation===searchGeneration)searchResults=results;}
  catch{if(generation===searchGeneration)searchResults=[];}
  finally{if(generation===searchGeneration){searching=false;render();}}
};
$('#new-playlist').onclick=createPlaylist;
$('#import-button').onclick=async()=>{try{const result=await run('import-audio');toast(`${result.count} fichier(s) importé(s). ${result.errors.join(' · ')}`,!!result.errors.length);await refresh();}catch{}};
$('#back').onclick=()=>{if(navIndex>0)go(navigation[--navIndex],false);};
$('#forward').onclick=()=>{if(navIndex<navigation.length-1)go(navigation[++navIndex],false);};
$('#play').onclick=toggle;$('#previous').onclick=()=>next(true);$('#next').onclick=()=>next();
$('#shuffle').onclick=()=>{shuffle=!shuffle;$('#shuffle').setAttribute('aria-pressed',String(shuffle));};
$('#repeat').onclick=()=>{repeat=!repeat;$('#repeat').setAttribute('aria-pressed',String(repeat));};
$('#queue-toggle').onclick=()=>document.body.classList.toggle('hide-panel');
for(const id of ['now-like','player-like'])$('#'+id).onclick=async()=>{if(current){await run('favorite',current);await refresh();}};
$('#seek').oninput=()=>{if(Number.isFinite(audio.duration)&&audio.duration>0)audio.currentTime=audio.duration*Number($('#seek').value)/100;};
$('#volume').oninput=()=>{audio.volume=Number($('#volume').value);};
$('#volume').onchange=()=>api('settings',{volume:audio.volume,playbackRate:audio.playbackRate});
document.addEventListener('change',event=>{if(event.target.id==='rate'){audio.playbackRate=Number(event.target.value);audio.preservesPitch=false;api('settings',{volume:audio.volume,playbackRate:audio.playbackRate});}});
$('#lyrics').onclick=()=>modal('Les mots derrière la musique.',`<p>${escape(current?.lyrics || (current?.source==='bundled' ? 'Un instrumental. Juste les notes.' : 'Aucune parole enregistrée pour ce titre. Les paroles sauvegardées sur l’iPhone peuvent être synchronisées.'))}</p>`);
$('#modal-close').onclick=closeModal;$('#modal-form').onsubmit=event=>event.preventDefault();
for(const action of ['minimize','maximize','close'])$('#'+action).onclick=()=>api(action);
audio.onplay=()=>{lastTick=performance.now();updateTransport();};audio.onpause=()=>{lastTick=0;updateTransport();flushListening();};
audio.onended=()=>{flushListening();next();};
audio.onerror=()=>{if(audio.getAttribute('src'))toast('Le décodeur Windows ne peut pas lire ce fichier, ou le fichier est incomplet.',true);updateTransport();};
audio.ontimeupdate=()=>{
  const duration=audio.duration;
  $('#elapsed').textContent=clock(audio.currentTime);if(Number.isFinite(duration)){$('#duration').textContent=clock(duration);$('#seek').value=duration?audio.currentTime/duration*100:0;}
  const now=performance.now();if(!audio.paused&&lastTick){listened+=Math.min(2,(now-lastTick)/1000);if(listened>=15)flushListening();}lastTick=audio.paused?0:now;
};
document.addEventListener('keydown',event=>{
  const typing=['INPUT','TEXTAREA','SELECT'].includes(event.target.tagName);
  if(event.ctrlKey&&event.key.toLowerCase()==='k'){event.preventDefault();$('#search').focus();}
  if(event.code==='Space'&&!typing&&!$('#modal').open){event.preventDefault();toggle();}
  if(event.altKey&&event.key==='ArrowRight'){event.preventDefault();next();}
  if(event.altKey&&event.key==='ArrowLeft'){event.preventDefault();next(true);}
});
if('mediaSession'in navigator){navigator.mediaSession.setActionHandler('play',()=>audio.play());navigator.mediaSession.setActionHandler('pause',()=>audio.pause());navigator.mediaSession.setActionHandler('nexttrack',()=>next());navigator.mediaSession.setActionHandler('previoustrack',()=>next(true));navigator.mediaSession.setActionHandler('seekto',event=>{if(event.seekTime!=null)audio.currentTime=event.seekTime;});}
document.addEventListener('error',event=>{if(event.target.tagName==='IMG'&&!event.target.dataset.fallback){event.target.dataset.fallback='true';event.target.src='../assets/cover-night.png';}},true);
window.addEventListener('unhandledrejection',event=>{toast(event.reason?.message||'Une action a échoué.',true);});
hydrate();
try {await refresh();audio.volume=data.library.settings.volume??0.8;$('#volume').value=audio.volume;audio.playbackRate=data.library.settings.playbackRate||1;}
catch(error){toast('Impossible d’ouvrir la bibliothèque : '+error.message,true);}
window.soryn.onChange(()=>refresh().catch(error=>toast(error.message,true)));
