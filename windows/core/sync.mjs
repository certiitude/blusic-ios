import {createServer} from 'node:http';
import {randomBytes, createCipheriv, createDecipheriv, randomUUID} from 'node:crypto';
import {networkInterfaces} from 'node:os';
import {readFile, writeFile, rename} from 'node:fs/promises';
import {join} from 'node:path';
import {sharedSnapshot, mergeLibraries, validateLibrary, clone} from './library.mjs';

const aad = Buffer.from('soryn-sync-v1');
export function seal(value, key) {
  const nonce = randomBytes(12), cipher = createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(aad);
  const data = Buffer.concat([cipher.update(JSON.stringify(value), 'utf8'), cipher.final()]);
  // CryptoKit combined representation: nonce || ciphertext || authentication tag.
  return {version: 1, box: Buffer.concat([nonce, data, cipher.getAuthTag()]).toString('base64')};
}
export function unseal(value, key) {
  if (value?.version !== 1 || typeof value.box !== 'string') throw Error('Enveloppe invalide');
  const data = Buffer.from(value.box, 'base64');
  if (data.length < 28) throw Error('Enveloppe tronquée');
  const decipher = createDecipheriv('aes-256-gcm', key, data.subarray(0, 12));
  decipher.setAAD(aad); decipher.setAuthTag(data.subarray(-16));
  return JSON.parse(Buffer.concat([decipher.update(data.subarray(12, -16)), decipher.final()]).toString('utf8'));
}
export class SyncServer {
  constructor(store, onChange = () => {}) { this.store = store; this.onChange = onChange; this.seen = new Map(); this.attempts = new Map(); this.serial = Promise.resolve(); }
  async start(key, port = 0) {
    if (this.server) return;
    this.key = key; this.baselines = {}; this.pendingBaselines = {};
    try {
      const saved = JSON.parse(await readFile(join(this.store.directory, 'sync-baselines.json'), 'utf8'));
      this.baselines = saved.baselines || {}; this.pendingBaselines = saved.pending || {};
    } catch (e) { if (e.code !== 'ENOENT') throw e; }
    this.server = createServer((req, res) => this.handle(req, res));
    this.server.headersTimeout = 8000; this.server.requestTimeout = 15000;
    this.server.maxConnections = 8;
    try { await new Promise((resolve, reject) => { this.server.once('error', reject); this.server.listen(port, '0.0.0.0', resolve); }); }
    catch (error) { this.server = null; throw error; }
    this.port = this.server.address().port;
  }
  info() {
    const addresses = Object.values(networkInterfaces()).flat().filter(i => i.family === 'IPv4' && !i.internal && isPrivate(i.address)).map(i => `http://${i.address}:${this.port}`);
    const key = this.key.toString('base64url');
    return {addresses, pairing: addresses.map(address => `soryn://pair?address=${encodeURIComponent(address)}&key=${key}`), active: !!this.server};
  }
  async handle(req, res) {
    res.setHeader('Cache-Control', 'no-store'); res.setHeader('Content-Type', 'application/json');
    const fail = (code, message) => { if (!res.writableEnded) { res.statusCode = code; res.end(JSON.stringify({error: message})); } };
    try {
      const ip = req.socket.remoteAddress?.replace('::ffff:', '');
      if (!isPrivate(ip)) return fail(403, 'Réseau local uniquement');
      if (req.method !== 'POST' || req.url !== '/v1/sync' || req.headers.origin) return fail(404, 'Introuvable');
      const now = Date.now(), previous = this.attempts.get(ip) || {count: 0, at: now};
      if (now - previous.at > 60000) { previous.count = 0; previous.at = now; }
      if (++previous.count > 60) return fail(429, 'Trop de requêtes');
      this.attempts.set(ip, previous);
      let bytes = 0; const parts = [];
      for await (const part of req) { bytes += part.length; if (bytes > 12_000_000) return fail(413, 'Bibliothèque trop volumineuse'); parts.push(part); }
      const packet = unseal(JSON.parse(Buffer.concat(parts).toString()), this.key);
      if (packet.protocol !== 1 || typeof packet.deviceID !== 'string' || !/^[a-zA-Z0-9-]{16,64}$/.test(packet.deviceID) || typeof packet.requestID !== 'string' ||
          !Number.isFinite(packet.sentAt) || Math.abs(now - packet.sentAt) > 120000 || this.seen.has(packet.requestID)) return fail(409, 'Requête périmée ou répétée');
      this.seen.set(packet.requestID, now);
      for (const [id, at] of this.seen) if (now - at > 180000) this.seen.delete(id);
      const incoming = sharedSnapshot(validateLibrary(packet.snapshot));
      // Serialise concurrent exchanges; each peer has its own last common state.
      const exchange = this.serial.catch(() => {}).then(async () => {
        // Advance the common ancestor only after the phone confirms receipt.
        // A lost response must not turn unseen PC additions into phone deletions.
        const pending = this.pendingBaselines[packet.deviceID];
        if (pending && packet.acknowledgedRequestID === pending.requestID) this.baselines[packet.deviceID] = pending.snapshot;
        const before = sharedSnapshot(this.store.data);
        const merged = mergeLibraries(this.baselines[packet.deviceID], before, incoming);
        const locals = new Map(this.store.data.tracks.filter(t => t.source === 'local').map(t => [t.id, t]));
        await this.store.update(s => Object.assign(s, merged, {settings: s.settings, queue: s.queue, currentTrackID: s.currentTrackID,
          tracks: [...merged.tracks.map(t => locals.get(t.id) || t), ...[...locals.values()].filter(t => !merged.tracks.some(m => m.id === t.id))]}));
        this.pendingBaselines[packet.deviceID] = {requestID: packet.requestID, snapshot: sharedSnapshot(merged)};
        const file = join(this.store.directory, 'sync-baselines.json');
        await writeFile(file + '.tmp', JSON.stringify({baselines: this.baselines, pending: this.pendingBaselines})); await rename(file + '.tmp', file);
        this.onChange();
        return {protocol: 1, requestID: packet.requestID, snapshot: sharedSnapshot(merged), syncedAt: Date.now()};
      });
      this.serial = exchange;
      res.end(JSON.stringify(seal(await exchange, this.key)));
    } catch { fail(400, 'Échange refusé : appairage ou données invalides'); }
  }
  async stop() { const server = this.server; this.server = null; if (server) await new Promise(resolve => { server.close(resolve); server.closeAllConnections(); }); }
}
export function isPrivate(ip = '') {
  const parts = ip.split('.').map(Number);
  return parts.length === 4 && parts.every(n => Number.isInteger(n) && n >= 0 && n <= 255) &&
    (parts[0] === 10 || parts[0] === 127 || parts[0] === 192 && parts[1] === 168 || parts[0] === 172 && parts[1] >= 16 && parts[1] <= 31);
}
