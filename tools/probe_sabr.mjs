// Diagnostic for the current YouTube streaming protocol. No account cookies,
// CAPTCHA solver, proxy rotation, DRM key handling, or signed URL logging.
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import vm from 'node:vm';
import {createHash} from 'node:crypto';
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
const require = createRequire(process.argv[2] + '/package.json');
const load = name => import(pathToFileURL(require.resolve(name)).href);
const {Innertube, Platform, Constants} = await load('youtubei.js');
const {SabrStream} = await load('googlevideo/sabr-stream');
const {buildSabrFormat, EnabledTrackTypes} = await load('googlevideo/utils');
const id = process.argv[3] || 'qMAzmGNeDxc';
Platform.shim.eval = async data => vm.runInNewContext(`(() => { ${data.output} })()`, Object.create(null), {timeout:1500});
const start = performance.now();
let stream;
let origin;
try {
  const yt = await Innertube.create({lang:'fr',location:'FR',generate_session_locally:false,retrieve_player:true,
    fetch:(input,init={}) => fetch(input,{...init,signal:AbortSignal.timeout(10000)})});
  const info = await yt.getBasicInfo(id,{client:'WEB'});
  const response = info;
  const config = response.player_config?.media_common_config?.media_ustreamer_request_config?.video_playback_ustreamer_config;
  const server = response.streaming_data?.server_abr_streaming_url;
  console.log(JSON.stringify({phase:'metadata',id,status:info.playability_status?.status,reason:info.playability_status?.reason,
    hls:!!info.streaming_data?.hls_manifest_url,sabr:!!server,config:!!config}));
  if (info.playability_status?.status !== 'OK' || !server || !config) throw Error('SABR metadata unavailable');
  const url = await yt.session.player.decipher(server);
  if(process.argv.includes('--attest')) {
    const {createOriginMinter}=await import('../relay/origin.mjs');
    origin=await createOriginMinter(yt,load,{forceWaa:process.argv.includes('--waa'),diagnostic:process.argv.includes('--waa')});
    console.log(JSON.stringify({phase:'origin-attestation',created:true}));
  }
  stream = new SabrStream({videoId:id,serverAbrStreamingUrl:url,videoPlaybackUstreamerConfig:config,
    fetchFunction:async(input,init={})=>{
      const response=await fetch(input,{...init,signal:AbortSignal.timeout(6000)});
      console.log(JSON.stringify({phase:'sabr-response',status:response.status,mime:response.headers.get('content-type')}));
      return response;
    },
    formats:info.streaming_data.adaptive_formats.map(buildSabrFormat),
    clientInfo:{clientName:Number(Constants.CLIENT_NAME_IDS[yt.session.context.client.clientName]),clientVersion:yt.session.context.client.clientVersion},
    callbacks:{onMintPoToken:async()=>{
      if(!origin) {stream.abort();throw Error('Provider requested an origin attestation; unauthenticated diagnostic stops here');}
      const proof=await origin.mint(id);
      console.log(JSON.stringify({phase:'content-proof',bytes:proof.length}));
      return proof;
    }}});
  stream.on('error',error=>console.log(JSON.stringify({phase:'sabr-error',error:String(error.message).replace(/https?:\/\/\S+/g,'[source]')})));
  stream.on('streamProtectionStatusUpdate',state=>console.log(JSON.stringify({phase:'stream-protection',status:state.status})));
  const result = stream.start({enabledTrackTypes:EnabledTrackTypes.AUDIO_ONLY,maxRetries:0,stallDetectionMs:5000,isPostLiveDvr:false,
    audioPreferences:{container:'mp4',dynamicRangeCompression:false,voiceBoost:false}});
  const hash=createHash('sha256'); let bytes=0; const pieces=[];
  const timeout=setTimeout(()=>stream.abort(),15000);
  try { for await (const chunk of result.audioStream) { bytes+=chunk.length; hash.update(chunk); if(bytes>8000000) throw Error('Diagnostic capped at 8MB'); if(process.argv.includes('--save')) pieces.push(Buffer.from(chunk)); } }
  finally { clearTimeout(timeout); }
  console.log(JSON.stringify({phase:'audio',id,bytes,expected:result.selectedFormats.audioFormat.contentLength,sha256:hash.digest('hex'),seconds:(performance.now()-start)/1000}));
  if(process.argv.includes('--save')) { const path=join(process.argv[2],`${id}.sabr.m4a`);await writeFile(path,Buffer.concat(pieces));console.log(JSON.stringify({saved:path})); }
} catch(error) {
  console.log(JSON.stringify({id,error:String(error.message).replace(/https?:\/\/\S+/g,'[source]'),seconds:(performance.now()-start)/1000}));
  process.exitCode=1;
} finally { if(stream) stream.abort(); if(origin) await origin.close(); }
