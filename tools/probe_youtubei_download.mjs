// Real youtubei.js download diagnostic: no cookies or auth tokens, no challenge solving.
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import vm from 'node:vm';
import {createHash} from 'node:crypto';
const require = createRequire(process.argv[2] + '/package.json');
const {Innertube, Platform} = await import(pathToFileURL(require.resolve('youtubei.js')).href);
Platform.shim.eval = async data => vm.runInNewContext(`(() => { ${data.output} })()`, Object.create(null), {timeout: 1500});
const id = process.argv[3] || 'rdpuziaOHJI';
for (const client of ['ANDROID_VR','IOS','ANDROID','YTMUSIC_ANDROID']) {
  const began = performance.now();
  try {
    const yt = await Innertube.create({lang:'fr', location:'FR', generate_session_locally:true, retrieve_player:true,
      fetch: (input, init = {}) => fetch(input, {...init, signal: AbortSignal.timeout(12000)})});
    const info = await yt.getBasicInfo(id, {client});
    const formats = (info.streaming_data?.adaptive_formats || []).filter(f => f.has_audio && !f.has_video && f.mime_type?.startsWith('audio/mp4') && !f.drm_families?.length);
    formats.sort((a,b) => b.bitrate - a.bitrate);
    if (!formats[0]) { console.log(JSON.stringify({client,id,status:info.playability_status?.status, reason: info.playability_status?.reason, aac:0})); continue; }
    const format = formats[0];
    const source = await info.download({itag:format.itag, type:'audio'});
    let bytes = 0; const hash = createHash('sha256');
    for await (const piece of source) { bytes += piece.length; hash.update(piece); if (bytes > 8000000) throw Error('Diagnostic capped at 8MB'); }
    console.log(JSON.stringify({client,id,bytes,expected:format.content_length,complete:bytes===format.content_length,sha256:hash.digest('hex'),seconds: +( (performance.now()-began)/1000).toFixed(3)}));
  } catch(e) { console.log(JSON.stringify({client,id,error:e.message,seconds:+((performance.now()-began)/1000).toFixed(3)})); }
}
