import {Innertube,Platform,Constants} from 'youtubei.js';
import {SabrStream} from 'googlevideo/sabr-stream';
import {buildSabrFormat,EnabledTrackTypes} from 'googlevideo/utils';
import {BotGuardClient} from 'bgutils-js/botguard';
import {WebPoMinter} from 'bgutils-js/webpo';
import {getHeaders,buildURL,USER_AGENT,parseLooseJSON} from 'bgutils-js/utils';
import {VideoPlaybackAbrRequest} from 'googlevideo/protos';

// This WebKit document is a resolver, never a video/audio player. Only the
// prepared AAC bytes are passed back to AVAudioEngine/AVPlayer on the iPhone.
const pending=new Map();let sequence=0,currentStream,currentController,contextPromise,contextExpiry=0,contextCleanup,activeJob;
const post=data=>window.webkit.messageHandlers.blusicResolver.postMessage(data);
const encode=data=>{let result='';const bytes=new Uint8Array(data);for(let i=0;i<bytes.length;i+=16384)result+=String.fromCharCode(...bytes.subarray(i,i+16384));return btoa(result);};
const decode=data=>Uint8Array.from(atob(data),c=>c.charCodeAt(0));
function call(action,data={}){const request=++sequence;return new Promise((resolve,reject)=>{pending.set(request,{resolve,reject});post({action,request,job:activeJob,...data});});}
window.__blusicReply=(request,result)=>{const p=pending.get(request);if(!p)return;pending.delete(request);result.error?p.reject(Error(result.error)):p.resolve(result);};
async function nativeFetch(input,init={}){
  const request=new Request(input,init),headers={};request.headers.forEach((value,key)=>headers[key]=value);
  // URLSession is outside the browser network stack: preserve the automatic
  // browser headers that are not present in Request.headers itself.
  headers['user-agent'] ||= navigator.userAgent;
  headers.origin ||= 'https://www.youtube.com';
  headers.referer ||= 'https://www.youtube.com/';
  const body=['GET','HEAD'].includes(request.method)?null:encode(await request.arrayBuffer());
  if(body && new URL(request.url).hostname.endsWith('.googlevideo.com')){
    try{const parsed=VideoPlaybackAbrRequest.decode(decode(body));post({action:'diagnostic',phase:'request-proof',bytes:parsed.streamerContext?.poToken?.length||0});}catch{}
  }
  const result=await call('fetch',{url:request.url,method:request.method,headers,body});
  const stream=result.stream;
  const payload=stream ? new ReadableStream({
    async pull(controller){try{const part=await call('readFetch',{stream});if(part.done)controller.close();else controller.enqueue(decode(part.body));}catch(error){controller.error(error);}},
    cancel(){return call('closeFetch',{stream}).catch(()=>{});}
  }) : decode(result.body);
  const response=new Response([204,205,304].includes(result.status)?null:payload,{status:result.status,headers:result.headers});
  Object.defineProperty(response,'url',{value:result.url});return response;
}
Platform.shim.eval=async data=>new Function(data.output)();
async function context(){
  if(contextPromise && (!contextExpiry || contextExpiry>Date.now()))return contextPromise;
  if(contextCleanup)await contextCleanup();
  contextPromise=(async()=>{
    const yt=await Innertube.create({lang:'fr',location:'FR',user_agent:USER_AGENT,generate_session_locally:false,retrieve_player:true,fetch:nativeFetch});
    const page=await nativeFetch('https://www.youtube.com/',{headers:{'User-Agent':USER_AGENT}});
    if(!page.ok)throw Error(`Page YouTube HTTP ${page.status}`);
    const html=await page.text(),configuration=html.match(/ytcfg\.set\((\{.+?\})\);/s)?.[1];
    window.yt={config_:configuration?JSON.parse(configuration):{INNERTUBE_CONTEXT:yt.session.context}};
    const raw=html.match(/window\.ytAtN\(\s*({[\s\S]*?})\s*\)/)?.[1];
    let challenge=raw?parseLooseJSON(raw).R?.bgChallenge:undefined;
    if(!challenge){const result=await yt.getAttestationChallenge('ENGAGEMENT_TYPE_UNBOUND');const c=result.bg_challenge;if(c)challenge={program:c.program,globalName:c.global_name,interpreterUrl:{privateDoNotAccessOrElseTrustedResourceUrlWrappedValue:c.interpreter_url?.private_do_not_access_or_else_trusted_resource_url_wrapped_value},interpreterJavascript:{privateDoNotAccessOrElseSafeScriptWrappedValue:c.interpreter_javascript?.private_do_not_access_or_else_safe_script_wrapped_value}};}
    if(!challenge?.program)throw Error('Attestation d’origine indisponible');
    let interpreter=challenge.interpreterJavascript?.privateDoNotAccessOrElseSafeScriptWrappedValue;
    if(!interpreter){
      const address=challenge.interpreterUrl?.privateDoNotAccessOrElseTrustedResourceUrlWrappedValue;
      if(!address)throw Error('Interpréteur d’attestation absent');
      const url=new URL(address,'https://www.youtube.com');
      if(url.protocol!=='https:'||!['www.google.com','www.gstatic.com','www.youtube.com'].includes(url.hostname))throw Error('Interpréteur d’attestation non reconnu');
      const source=await nativeFetch(url.href);if(!source.ok)throw Error(`Attestation HTTP ${source.status}`);interpreter=await source.text();
    }
    new Function(interpreter)();
    const client=await BotGuardClient.create({program:challenge.program,globalName:challenge.globalName,globalObject:window});
    const output=[],snapshot=await client.snapshot({webPoSignalOutput:output},10000);
    const response=await nativeFetch(buildURL('GenerateIT',true),{method:'POST',headers:{...getHeaders(),'user-agent':USER_AGENT},body:JSON.stringify(['O43z0dpjhgX20SCx4KAo',snapshot])});
    if(!response.ok)throw Error(`Attestation refusée HTTP ${response.status}`);
    const [integrityToken,estimatedTtlSecs,mintRefreshThreshold,websafeFallbackToken]=await response.json();
    const minter=await WebPoMinter.create({integrityToken,estimatedTtlSecs,mintRefreshThreshold,websafeFallbackToken},output);
    contextExpiry=Date.now()+Math.min(Math.max(60,Number(estimatedTtlSecs)||3600)*1000,45*60000);
    contextCleanup=()=>client.shutdown().catch(()=>{});
    return {yt,minter};
  })();
  try{return await contextPromise;}catch(error){contextPromise=undefined;throw error;}
}
window.__blusicResolve=async(id,job)=>{
  if(!/^[A-Za-z0-9_-]{11}$/.test(id))return post({action:'failed',job,error:'Identifiant invalide'});
  activeJob=job;
  let stream;
  try{
    const {yt,minter}=await context();
    const proof=await minter.mint(id);
    post({action:'diagnostic',job,phase:'content-proof',bytes:proof.length});
    const info=await yt.getBasicInfo(id,{client:'WEB',po_token:encode(proof).replaceAll('+','-').replaceAll('/','_').replaceAll('=','')});
    if(info.playability_status?.status!=='OK')throw Error(info.playability_status?.reason||'Titre indisponible');
    const config=info.player_config?.media_common_config?.media_ustreamer_request_config?.video_playback_ustreamer_config;
    const source=info.streaming_data?.server_abr_streaming_url;
    if(!config||!source)throw Error('Flux audio SABR indisponible');
    currentController=new AbortController();
    stream=new SabrStream({videoId:id,serverAbrStreamingUrl:await yt.session.player.decipher(source),videoPlaybackUstreamerConfig:config,
      formats:info.streaming_data.adaptive_formats.map(buildSabrFormat),poToken:encode(proof),fetchFunction:nativeFetch,
      clientInfo:{clientName:Number(Constants.CLIENT_NAME_IDS[yt.session.context.client.clientName]),clientVersion:yt.session.context.client.clientVersion},callbacks:{onMintPoToken:()=>minter.mint(id)}});
    currentStream=stream;
    stream.on('streamProtectionStatusUpdate',state=>post({action:'diagnostic',job,phase:'stream-protection',status:state.status}));
    stream.on('error',()=>stream.abort());
    const result=stream.start({enabledTrackTypes:EnabledTrackTypes.AUDIO_ONLY,maxRetries:1,stallDetectionMs:8000,isPostLiveDvr:false,
      audioPreferences:{container:'mp4',preferredAudioCodec:'aac',dynamicRangeCompression:false,voiceBoost:false}});
    const expected=Number(result.selectedFormats.audioFormat.contentLength);if(!Number.isSafeInteger(expected)||expected<=0||expected>25000000)throw Error('Taille audio invalide');
    await call('beginAudio',{job,expected});let bytes=0;
    for await(const piece of result.audioStream){if(currentController.signal.aborted)throw Error('Annulé');bytes+=piece.byteLength;if(bytes>expected)throw Error('Audio hors limites');await call('appendAudio',{job,body:encode(piece)});}
    if(bytes!==expected)throw Error('Fichier audio incomplet');
    post({action:'finished',job,expected,bitrate:Number(result.selectedFormats.audioFormat.bitrate)||0,duration:info.basic_info.duration||0});
  }catch(error){post({action:'failed',job,error:String(error.message).replace(/https?:\/\/\S+/g,'[source]').slice(0,600)});}
  finally{if(stream)await stream.abort();currentStream=undefined;}
};
window.__blusicCancel=()=>{currentController?.abort();currentStream?.abort();for(const p of pending.values())p.reject(Error('Annulé'));pending.clear();};
post({action:'ready'});
