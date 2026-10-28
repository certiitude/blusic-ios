const {contextBridge, ipcRenderer} = require('electron');
const allowed = new Set(['state', 'search', 'save-track', 'play', 'cancel', 'favorite', 'playlist-create', 'playlist-add', 'playlist-remove-track', 'playlist-delete', 'record', 'settings', 'import-audio', 'backup-export', 'backup-import', 'download', 'download-remove', 'sync-start', 'sync-stop', 'sync-reset', 'copy-pairing', 'minimize', 'maximize', 'close']);
contextBridge.exposeInMainWorld('soryn', {
  call(action, data) { if (!allowed.has(action)) return Promise.reject(Error('Commande refusée.')); return ipcRenderer.invoke('soryn', action, data); },
  onChange(callback) { const listener = () => callback(); ipcRenderer.on('library-changed', listener); return () => ipcRenderer.removeListener('library-changed', listener); }
});
