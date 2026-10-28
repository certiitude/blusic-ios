import {app, BrowserWindow, ipcMain, dialog, protocol, safeStorage, clipboard, net} from 'electron';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {join, dirname, extname, basename, resolve} from 'node:path';
import {mkdir, readFile, writeFile, rename, copyFile, stat, rm, readdir} from 'node:fs/promises';
import {createReadStream} from 'node:fs';
import {Readable} from 'node:stream';
import {randomBytes, randomUUID} from 'node:crypto';
import {Worker} from 'node:worker_threads';
import {parseFile} from 'music-metadata';
import QRCode from 'qrcode';
import {LibraryStore, clone, validateLibrary, mergeLibraries, swiftNow, defaultSettings} from './core/library.mjs';
import {SyncServer} from './core/sync.mjs';
import {search} from './core/catalog.mjs';

const root = dirname(fileURLToPath(import.meta.url));
protocol.registerSchemesAsPrivileged([{scheme: 'soryn-media', privileges: {standard: true, secure: true, stream: true, supportFetchAPI: true}}]);
app.setName('Soryn');
const smokeIndex = process.argv.indexOf('--test-data');
if (smokeIndex >= 0) app.setPath('userData', resolve(process.argv[smokeIndex + 1]));
if (!app.requestSingleInstanceLock()) app.quit();
app.on('second-instance', () => { if (win) { if (win.isMinimized()) win.restore(); win.focus(); } });
let win, store, sync, downloads = {}, activeWork, playbackID;
const files = new Map();
const audioDirectory = () => join(app.getPath('userData'), 'Audio');
const downloadDirectory = () => join(app.getPath('userData'), 'Downloads');
const safeName = name => typeof name === 'string' && name.length > 0 && basename(name) === name && !/[\\/:]/.test(name);
const emit = () => { if (win && !win.isDestroyed()) win.webContents.send('library-changed'); };
const manifest = () => join(downloadDirectory(), 'manifest.json');
async function saveDownloads() { await writeFile(manifest() + '.tmp', JSON.stringify(downloads)); await rename(manifest() + '.tmp', manifest()); }
const mediaURL = track => `soryn-media://track/${track.id}`;
function localPath(track) {
  if (track.source === 'bundled' && ['bleu-nuit.wav', 'apres-la-pluie.wav', 'orbite.wav', 'dernier-metro.wav'].includes(track.location)) return join(root, 'assets/audio', track.location);
  if (track.source === 'local' && safeName(track.location)) return join(audioDirectory(), track.location);
  const entry = downloads[track.id];
  if (entry && safeName(entry.filename)) return join(downloadDirectory(), entry.filename);
  return files.get(track.id);
}
async function state() {
  const data = clone(store.data), available = [];
  for (const t of data.tracks) { const path = localPath(t); if (path && await stat(path).catch(() => null)) available.push(t.id); }
  const artwork = Object.fromEntries(Object.entries(downloads).filter(([,e]) => safeName(e.artwork)).map(([id,e])=>[id,pathToFileURL(join(downloadDirectory(),e.artwork)).href]));
  return {library: data, downloads: Object.keys(downloads), artwork, available, syncActive: !!sync.server, version: app.getVersion()};
}
async function prepare(track) {
  const path = localPath(track);
  if (path && await stat(path).catch(() => null)) return {url: mediaURL(track), duration: track.duration, offline: true};
  if (!['invidious', 'youtube'].includes(track.source) || !/^[\w-]{11}$/.test(track.location)) throw Error('Fichier absent sur ce PC. Importe-le ici ou retrouve le titre dans Explorer.');
  if (activeWork) throw Error('Une préparation est déjà en cours. Annule-la avant de recommencer.');
  const worker = new Worker(new URL('./core/audio-worker.mjs', import.meta.url), {workerData: {videoID: track.location, duration: track.duration}});
  const work = {worker}; activeWork = work;
  const output = join(app.getPath('userData'), 'Cache', track.id + '.m4a');
  try {
    const result = await new Promise((resolve, reject) => {
      const timer = setTimeout(() => { worker.terminate(); reject(Error('Préparation trop lente. Réessaie ou annule.')); }, 65000);
      work.cancel = () => { clearTimeout(timer); worker.terminate(); reject(Error('Préparation annulée.')); };
      worker.once('message', result => { clearTimeout(timer); result.error ? reject(Error(result.error)) : resolve(result); });
      worker.once('error', error => { clearTimeout(timer); reject(error); });
      worker.once('exit', code => { clearTimeout(timer); if (code !== 0) reject(Error('Préparation interrompue.')); });
    });
    await copyFile(result.path, output + '.tmp'); await rename(output + '.tmp', output);
    files.set(track.id, output); worker.postMessage('copied');
    for (const [id, path] of files) {
      if (files.size <= 8) break;
      if (id !== playbackID && id !== track.id) { files.delete(id); await rm(path,{force:true}).catch(()=>{}); }
    }
    return {url: mediaURL(track), duration: result.duration, bitrate: result.bitrate, offline: false};
  } finally { if (activeWork === work) activeWork = null; setTimeout(() => worker.terminate(), 2000).unref(); }
}

app.whenReady().then(async () => {
await Promise.all(['Audio', 'Downloads', 'Cache'].map(name => mkdir(join(app.getPath('userData'), name), {recursive: true})));
// Only scratch files created by this app are discarded; never touch imported audio.
for (const name of await readdir(join(app.getPath('userData'),'Cache'))) {
  if (/^[0-9a-f-]{36}\.m4a(?:\.tmp)?$/i.test(name)) await rm(join(app.getPath('userData'),'Cache',name),{force:true}).catch(()=>{});
}
store = new LibraryStore(app.getPath('userData'));
try { await store.load(); }
catch (error) { dialog.showErrorBox('Soryn · bibliothèque protégée', error.message); app.quit(); }
if (store.data) {
  try { downloads = JSON.parse(await readFile(manifest(), 'utf8')); }
  catch (e) { if (e.code !== 'ENOENT') dialog.showErrorBox('Soryn · téléchargements', 'Index illisible, fichiers conservés. ' + e.message); }
  for (const [id,entry] of Object.entries(downloads)) {
    const info = safeName(entry.filename) ? await stat(join(downloadDirectory(),entry.filename)).catch(()=>null) : null;
    if (!info || info.size !== entry.size || !(entry.duration > 0)) delete downloads[id];
  }
  sync = new SyncServer(store, emit);
  protocol.handle('soryn-media', async request => {
    const url = new URL(request.url), id = url.pathname.slice(1), track = store.data.tracks.find(t => t.id === id);
    const path = url.hostname === 'track' && track ? localPath(track) : null;
    if (!path) return new Response('Absent', {status: 404});
    const info = await stat(path).catch(() => null);
    if (!info) return new Response('Absent', {status: 404});
    const range = request.headers.get('Range'), match = range?.match(/^bytes=(\d+)-(\d*)$/);
    const start = match ? Number(match[1]) : 0, end = match?.[2] ? Math.min(Number(match[2]), info.size - 1) : info.size - 1;
    if (start > end || start >= info.size) return new Response(null, {status: 416, headers: {'Content-Range': `bytes */${info.size}`}});
    const types = {'.wav': 'audio/wav', '.mp3': 'audio/mpeg', '.m4a': 'audio/mp4', '.aac': 'audio/aac', '.flac': 'audio/flac', '.ogg': 'audio/ogg', '.aiff': 'audio/aiff'};
    return new Response(Readable.toWeb(createReadStream(path, {start, end})), {status: match ? 206 : 200,
      headers: {'Content-Type': types[extname(path).toLowerCase()] || 'application/octet-stream', 'Accept-Ranges': 'bytes', 'Content-Length': String(end - start + 1),
        ...(match ? {'Content-Range': `bytes ${start}-${end}/${info.size}`} : {})}});
  });

  ipcMain.handle('soryn', async (event, action, input) => {
    if (event.sender !== win?.webContents || event.senderFrame !== win.webContents.mainFrame) throw Error('Origine refusée.');
    switch (action) {
      case 'state': return state();
      case 'search': return search(input);
      case 'save-track': {
        validateLibrary({...store.data, tracks: [input]});
        const track = store.add(input); await store.save(); emit(); return clone(track);
      }
      case 'play': {
        validateLibrary({...store.data, tracks: [input]});
        const track = store.add(input); playbackID = track.id; await store.save(); emit();
        return {...await prepare(track), track};
      }
      case 'cancel': activeWork?.cancel?.(); return;
      case 'favorite': {
        validateLibrary({...store.data, tracks: [input]});
        const t = store.add(input);
        await store.update(s => { s.favorites = s.favorites.includes(t.id) ? s.favorites.filter(id => id !== t.id) : [...s.favorites, t.id]; }); emit(); return state();
      }
      case 'playlist-create': {
        if (typeof input !== 'string' || !input.trim() || input.length > 200) throw Error('Nom invalide.');
        const p = {id: randomUUID().toUpperCase(), name: input.trim(), detail: 'Ta sélection, ton univers.', trackIDs: [], createdAt: swiftNow(), symbol: 'music.note.list'};
        await store.update(s => s.playlists.push(p)); emit(); return p;
      }
      case 'playlist-add': {
        validateLibrary({...store.data, tracks: [input.track]});
        const t = store.add(input.track), p = store.data.playlists.find(p => p.id === input.playlistID);
        if (!p) throw Error('Playlist introuvable.');
        if (!p.trackIDs.includes(t.id)) p.trackIDs.push(t.id);
        await store.save(); emit(); return;
      }
      case 'playlist-remove-track': {
        const p = store.data.playlists.find(p => p.id === input.playlistID);
        if (p) await store.update(() => { p.trackIDs = p.trackIDs.filter(id => id !== input.trackID); }); emit(); return;
      }
      case 'playlist-delete': await store.update(s => { s.playlists = s.playlists.filter(p => p.id !== input); }); emit(); return;
      case 'record': {
        if (!store.data.tracks.some(t => t.id === input.trackID) || !Number.isFinite(input.seconds) || input.seconds <= 0 || input.seconds > 60 || !/^[\w-]{36}$/.test(input.id)) throw Error('Session invalide.');
        await store.update(s => { const e = s.history.find(e => e.id === input.id); if (e) e.seconds += input.seconds; else s.history.push({id: input.id, trackID: input.trackID, date: swiftNow(), seconds: input.seconds}); }); return;
      }
      case 'settings': {
        const volume = Number(input.volume), rate = Number(input.playbackRate);
        if (!Number.isFinite(volume) || volume < 0 || volume > 1 || !Number.isFinite(rate) || rate < 0.5 || rate > 2) throw Error('Réglage invalide.');
        await store.update(s => { s.settings.volume = volume; s.settings.playbackRate = rate; }); return;
      }
      case 'import-audio': {
        const selection = await dialog.showOpenDialog(win, {title: 'Importer ta musique dans Soryn', properties: ['openFile', 'multiSelections'], filters: [{name: 'Audio', extensions: ['mp3', 'm4a', 'aac', 'wav', 'flac', 'ogg', 'aiff']}]});
        const errors = []; let count = 0;
        for (const path of selection.filePaths) {
          let destination;
          try {
            if ((await stat(path)).size > 500_000_000) throw Error('Fichier de plus de 500 Mo.');
            const meta = await parseFile(path, {duration: true});
            if (!(meta.format.duration > 0)) throw Error('Durée audio invalide.');
            const filename = randomUUID().toUpperCase() + extname(path).toLowerCase(); destination = join(audioDirectory(), filename);
            await copyFile(path, destination);
            store.add({id: randomUUID().toUpperCase(), title: meta.common.title || basename(path, extname(path)), artist: meta.common.artist || 'Artiste inconnu', album: meta.common.album || 'Fichiers importés',
              duration: meta.format.duration, source: 'local', location: filename, artwork: 'cover-night', addedAt: swiftNow(), isExplicit: false}); count++;
          } catch (e) { if (destination) await rm(destination, {force: true}); errors.push(basename(path) + ' : ' + e.message); }
        }
        await store.save(); emit(); return {count, errors};
      }
      case 'backup-export': {
        const pick = await dialog.showSaveDialog(win, {defaultPath: 'Soryn-bibliotheque.json', filters: [{name: 'Bibliothèque JSON (sans fichiers audio)', extensions: ['json']}]});
        if (!pick.canceled) { const data = clone(store.data); data.settings = {...defaultSettings(), volume: data.settings.volume ?? 0.8, playbackRate: data.settings.playbackRate ?? 1}; await writeFile(pick.filePath, JSON.stringify(data, null, 2)); } return;
      }
      case 'backup-import': {
        const pick = await dialog.showOpenDialog(win, {properties: ['openFile'], filters: [{name: 'Sauvegarde Blusic / Soryn', extensions: ['json']}]});
        if (pick.canceled) return;
        if ((await stat(pick.filePaths[0])).size > 12_000_000) throw Error('Sauvegarde trop volumineuse.');
        const incoming = validateLibrary(JSON.parse(await readFile(pick.filePaths[0], 'utf8')));
        incoming.tracks = incoming.tracks.map(t => t.source === 'local' ? {...t, source: 'unresolved', location: '', artworkURL: undefined} : t);
        await store.update(s => Object.assign(s, mergeLibraries(null, s, incoming))); emit(); return;
      }
      case 'download': {
        const t = store.data.tracks.find(t => t.id === input);
        if (!t) throw Error('Titre introuvable.');
        const audio = await prepare(t), source = localPath(t);
        if (t.source === 'bundled' || t.source === 'local' || downloads[t.id]) return {alreadyLocal: true};
        const filename = t.id + '.m4a', destination = join(downloadDirectory(), filename);
        await copyFile(source, destination + '.tmp'); await rename(destination + '.tmp', destination);
        downloads[t.id] = {filename, duration: audio.duration, size: (await stat(destination)).size};
        try {
          if (/^https:\/\//i.test(t.artworkURL || '')) {
            const response = await fetch(t.artworkURL,{signal:AbortSignal.timeout(6000)});
            if (response.ok && /^image\//i.test(response.headers.get('Content-Type') || '')) {
              const chunks=[];let length=0;
              for await (const chunk of response.body) { length+=chunk.length; if(length>3_000_000)throw Error('Pochette trop volumineuse');chunks.push(chunk); }
              const cover=t.id+'.cover';await writeFile(join(downloadDirectory(),cover),Buffer.concat(chunks));downloads[t.id].artwork=cover;
            }
          }
        } catch { /* Audio remains downloadable even when artwork is unavailable. */ }
        await saveDownloads(); emit(); return;
      }
      case 'download-remove': {
        const entry = downloads[input]; if (entry && safeName(entry.filename)) { await rm(join(downloadDirectory(), entry.filename), {force: true}); if (safeName(entry.artwork)) await rm(join(downloadDirectory(),entry.artwork),{force:true}); delete downloads[input]; await saveDownloads(); emit(); } return;
      }
      case 'sync-start': {
        if (!sync.server) {
          if (!await safeStorage.isAsyncEncryptionAvailable()) throw Error('Le chiffrement Windows des clés est indisponible.');
          const keyFile = join(app.getPath('userData'), 'pairing.dat'); let key;
          try { key = Buffer.from(await safeStorage.decryptStringAsync(await readFile(keyFile)), 'base64'); }
          catch (e) { if (e.code !== 'ENOENT') throw Error('Clé Windows illisible : réinitialise l’appairage.'); key = randomBytes(32); await writeFile(keyFile, await safeStorage.encryptStringAsync(key.toString('base64'))); }
          let port = 48763;
          try { port = JSON.parse(await readFile(join(app.getPath('userData'), 'sync-port.json'), 'utf8')).port || port; } catch {}
          await sync.start(key, port);
        }
        const info = sync.info(); return {...info, qr: info.pairing[0] ? await QRCode.toDataURL(info.pairing[0], {margin: 2, width: 250, color: {dark: '#0B0E0F', light: '#F6F8FF'}}) : null};
      }
      case 'sync-stop': await sync.stop(); emit(); return;
      case 'sync-reset': await sync.stop(); await rm(join(app.getPath('userData'), 'pairing.dat'), {force: true}); await rm(join(app.getPath('userData'), 'sync-baselines.json'), {force: true}); return;
      case 'copy-pairing': if (sync.server) clipboard.writeText(sync.info().pairing[Number(input) || 0] || ''); return;
      case 'minimize': win.minimize(); return;
      case 'maximize': win.isMaximized() ? win.unmaximize() : win.maximize(); return;
      case 'close': win.close(); return;
      default: throw Error('Commande inconnue.');
    }
  });
  win = new BrowserWindow({width: 1440, height: 960, minWidth: 980, minHeight: 680, title: 'Soryn', backgroundColor: '#0B0E0F', icon: join(root, 'assets/soryn.ico'),
    frame: false, show: false, webPreferences: {preload: join(root, 'preload.cjs'), contextIsolation: true, sandbox: true, nodeIntegration: false, webSecurity: true}});
  win.webContents.setWindowOpenHandler(() => ({action: 'deny'}));
  win.webContents.on('will-navigate', e => e.preventDefault());
  win.webContents.session.setPermissionRequestHandler((_web, _permission, callback) => callback(false));
  await win.loadFile(join(root, 'ui/index.html'));
  win.show();
}
}).catch(error => { dialog.showErrorBox('Soryn · démarrage impossible', error.message); app.quit(); });
app.on('window-all-closed', () => app.quit());
app.on('before-quit', () => { activeWork?.cancel?.(); sync?.stop().catch(() => {}); });
