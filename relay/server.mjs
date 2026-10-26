import {createServer} from 'node:http';
import {createReadStream} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {pipeline} from 'node:stream/promises';
import {bearerMatches, verifyClientCapability, ticket, verifyTicket, validVideo, parseRange} from './protocol.mjs';
import {YouTubeProvider} from './provider.mjs';

export function makeServer({key, provider = new YouTubeProvider(), now = () => Date.now()} = {}) {
  if (!key || key.length < 24) throw Error('BLUSIC_RELAY_KEY doit contenir au moins 24 caractères');
  let preparing = 0;
  const server = createServer(async (request, response) => {
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('X-Content-Type-Options', 'nosniff');
    const send = (status, payload) => { response.writeHead(status, {'Content-Type':'application/json; charset=utf-8'}); response.end(JSON.stringify(payload)); };
    try {
      const url = new URL(request.url, 'http://localhost');
      if (url.pathname === '/health') { send(200, {ok:true, provider:'youtubei.js', version:'18.3.0', audioProtocol:'SABR', applicationAccessExpires:false}); return; }
      if (!['GET','HEAD'].includes(request.method)) { send(405, {error:'Méthode non autorisée'}); return; }
      const match = /^\/v1\/(streams|audio)\/([A-Za-z0-9_-]{11})$/.exec(url.pathname);
      if (!match || !validVideo(match[2])) { send(404, {error:'Route inconnue'}); return; }
      const [, kind, id] = match;
      const quality=url.searchParams.get('quality')||'standard';
      if(!['standard','high'].includes(quality)){send(400,{error:'Qualité audio inconnue'});return;}
      if (kind === 'streams') {
        const owner = bearerMatches(request.headers.authorization, key);
        if (!owner && !verifyClientCapability(key, request.headers.authorization, now())) { send(401, {error:'Accès au relais manquant, invalide ou expiré'}); return; }
        if (preparing >= 2) { response.setHeader('Retry-After', '3'); send(429, {error:'Relais occupé par deux préparations audio, réessaie dans un instant'}); return; }
        preparing++;
        let file;
        try { file = await provider.prepare(id,quality); } finally { preparing--; }
        const expiry = now() + 20 * 60000;
        send(200, {url:`/v1/audio/${id}?ticket=${ticket(key,id,expiry,quality)}${quality==='high'?'&quality=high':''}`, bitrate:file.bitrate, duration:file.duration, size:file.size, provider:'youtubei.js',requestedQuality:quality});
      } else {
        if (!verifyTicket(key,id,url.searchParams.get('ticket'),now(),quality)) { send(403,{error:'Lien audio expiré, résous à nouveau le titre'}); return; }
        const file = await provider.prepare(id,quality);
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
