import {Innertube, Platform} from 'youtubei.js';
import vm from 'node:vm';
import {mkdtemp, mkdir, rm, stat} from 'node:fs/promises';
import {createWriteStream} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {pipeline} from 'node:stream/promises';
import {Readable, Transform} from 'node:stream';

// youtubei.js's extracted public player transform, isolated from Node globals.
// No account cookies, PO token generation, or challenge-solving service.
Platform.shim.eval = async data => vm.runInNewContext(`(() => { ${data.output} })()`, Object.create(null), {timeout: 1500});

export class YouTubeProvider {
  constructor({clients = ['IOS', 'ANDROID_VR'], maxFileBytes = 25_000_000} = {}) {
    this.clients = clients.filter(c => ['IOS', 'ANDROID_VR', 'ANDROID', 'WEB'].includes(c));
    this.maxFileBytes = maxFileBytes;
    this.cache = new Map();
    this.pending = new Map();
  }
  async prepare(id) {
    const cached = this.cache.get(id);
    if (cached && cached.expiry > Date.now()) return cached;
    if (this.pending.has(id)) return this.pending.get(id);
    const work = this.download(id);
    this.pending.set(id, work);
    try { return await work; } finally { this.pending.delete(id); }
  }
  async download(id) {
    if (!this.root) this.root = await mkdtemp(join(tmpdir(), 'blusic-relay-'));
    const errors = [];
    for (const client of this.clients) {
      const directory = await mkdtemp(join(this.root, 'track-'));
      const path = join(directory, 'audio.m4a');
      try {
        const signal = AbortSignal.timeout(25_000);
        const yt = await Innertube.create({lang: 'fr', location: 'FR', generate_session_locally: true, retrieve_player: true,
          fetch: (input, init = {}) => fetch(input, {...init, signal: AbortSignal.any([signal, AbortSignal.timeout(10_000), ...(init.signal ? [init.signal] : [])])})});
        const info = await yt.getBasicInfo(id, {client});
        if (info.playability_status?.status !== 'OK') throw Error(info.playability_status?.reason || 'Titre non accessible sans connexion');
        const formats = (info.streaming_data?.adaptive_formats || []).filter(f => f.has_audio && !f.has_video && f.mime_type?.startsWith('audio/mp4') && !f.drm_families?.length)
          .sort((a,b) => b.bitrate - a.bitrate);
        const format = formats.find(f => f.content_length > 0 && f.content_length <= this.maxFileBytes);
        if (!format) throw Error('Aucun AAC public avec taille vérifiable');
        const stream = await info.download({itag: format.itag, type: 'audio'});
        let bytes = 0; let head = Buffer.alloc(0);
        const guard = new Transform({transform: (chunk, _, done) => {
          bytes += chunk.length;
          if (head.length < 64) head = Buffer.concat([head, Buffer.from(chunk).subarray(0, 64 - head.length)]);
          if (bytes > this.maxFileBytes || bytes > format.content_length) done(Error('Fichier audio trop volumineux'));
          else done(null, chunk);
        }});
        await pipeline(Readable.fromWeb(stream), guard, createWriteStream(path, {flags: 'wx'}), {signal});
        const size = (await stat(path)).size;
        if (size !== format.content_length || !head.includes(Buffer.from('ftyp'))) throw Error('Fichier audio incomplet ou non M4A');
        const entry = {path, directory, size, bitrate: format.bitrate, duration: info.basic_info.duration || 0, client, expiry: Date.now() + 10 * 60_000};
        this.cache.set(id, entry);
        await this.prune();
        return entry;
      } catch (error) {
        await rm(directory, {recursive: true, force: true});
        // Keep only a bounded diagnostic; never return signed media URLs.
        errors.push(`${client}: ${String(error.message).replace(/https?:\/\/\S+/g, '[upstream]').slice(0,250)}`);
      }
    }
    throw Error('youtubei.js n’a pas obtenu un fichier audio complet. ' + errors.join(' · '));
  }
  async prune() {
    for (const [id, entry] of this.cache) {
      if (entry.expiry <= Date.now() || this.cache.size > 5) { this.cache.delete(id); await rm(entry.directory, {recursive:true, force:true}); }
    }
  }
  async close() { if (this.root) await rm(this.root, {recursive: true, force: true}); }
}
