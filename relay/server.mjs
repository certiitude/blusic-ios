import {createServer} from 'node:http';
import {createReadStream} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {pipeline} from 'node:stream/promises';
import {bearerMatches, ticket, verifyTicket, validVideo, parseRange} from './protocol.mjs';
import {YouTubeProvider} from './provider.mjs';

export function makeServer({key, provider = new YouTubeProvider(), now = () => Date.now()} = {}) {
  if (!key || key.length < 24) throw Error('BLUSIC_RELAY_KEY doit contenir au moins 24 caractères');
  let preparing = 0;
  const limits = new Map();
  const server = createServer(async (request, response) => {
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    const send = (status, payload) => { response.writeHead(status, {'Content-Type':'application/json; charset=utf-8'}); response.end(JSON.stringify(payload)); };
    try {
      const url = new URL(request.url, 'http://localhost');
      if (url.pathname === '/health') { send(200, {ok:true, provider:'youtubei.js', version:'18.3.0'}); return; }
      if (!['GET','HEAD'].includes(request.method)) { send(405, {error:'Méthode non autorisée'}); return; }
      const match = /^\/v1\/(streams|audio)\/([A-Za-z0-9_-]{11})$/.exec(url.pathname);
      if (!match || !validVideo(match[2])) { send(404, {error:'Route inconnue'}); return; }
      const [, kind, id] = match;
      if (kind === 'streams') {
        if (!bearerMatches(request.headers.authorization, key)) { send(401, {error:'Clé du relais manquante ou invalide'}); return; }
        const ip = request.socket.remoteAddress;
        const window = Math.floor(now() / 60000);
        const entry = limits.get(ip) || {window, count:0};
        if (entry.window !== window) { entry.window = window; entry.count = 0; }
        entry.count++; limits.set(ip, entry);
        if (limits.size > 1000) limits.clear();
        if (entry.count > 30 || preparing >= 2) { send(429, {error:'Relais occupé, réessaie dans un instant'}); return; }
        preparing++;
        let file;
        try { file = await provider.prepare(id); } finally { preparing--; }
        const expiry = now() + 20 * 60000;
        send(200, {url:`/v1/audio/${id}?ticket=${ticket(key,id,expiry)}`, bitrate:file.bitrate, duration:file.duration, size:file.size, provider:'youtubei.js'});
      } else {
        if (!verifyTicket(key,id,url.searchParams.get('ticket'),now())) { send(403,{error:'Lien audio expiré, résous à nouveau le titre'}); return; }
        const file = await provider.prepare(id);
        const range = parseRange(request.headers.range, file.size);
        if (!range) { response.writeHead(416, {'Content-Range':`bytes */${file.size}`}); response.end(); return; }
        const headers = {'Content-Type':'audio/mp4', 'Accept-Ranges':'bytes', 'Content-Length':range.end-range.start+1};
        if (range.partial) headers['Content-Range'] = `bytes ${range.start}-${range.end}/${file.size}`;
        response.writeHead(range.partial ? 206 : 200, headers);
        if (request.method === 'HEAD') response.end();
        else await pipeline(createReadStream(file.path, {start:range.start,end:range.end}), response);
      }
    } catch (error) {
      if (!response.headersSent) send(502, {error:String(error.message).replace(/https?:\/\/\S+/g, '[upstream]').slice(0,800)});
      else response.destroy();
    }
  });
  server.requestTimeout = 65000;
  return server;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const provider = new YouTubeProvider({clients:(process.env.YOUTUBEI_CLIENTS || 'IOS,ANDROID_VR').split(',')});
  const server = makeServer({key:process.env.BLUSIC_RELAY_KEY, provider});
  server.listen(Number(process.env.PORT || 10000), '0.0.0.0', () => console.log('Blusic youtubei.js relay ready'));
  process.on('SIGTERM', () => server.close(async () => { await provider.close(); process.exit(0); }));
}
