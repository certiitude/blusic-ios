import {Innertube, Platform, Constants} from 'youtubei.js';
import {SabrStream} from 'googlevideo/sabr-stream';
import {buildSabrFormat, EnabledTrackTypes} from 'googlevideo/utils';
import {createOriginMinter} from './origin.mjs';
import vm from 'node:vm';
import {Readable, Transform} from 'node:stream';
import {pipeline} from 'node:stream/promises';
import {createWriteStream} from 'node:fs';
import {stat} from 'node:fs/promises';

Platform.shim.eval = async data => vm.runInNewContext(`(() => { ${data.output} })()`,Object.create(null),{timeout:1500});
const boundedFetch = async (input,init={}) => {
  const original=new URL(input instanceof Request?input.url:String(input));
  const destination=process.env.BLUSIC_INNERTUBE_HOST;
  if(destination==='youtubei.googleapis.com'&&original.hostname==='www.youtube.com'&&original.pathname.startsWith('/youtubei/v1/')){
    const url=new URL(original);url.hostname=destination;
    input=input instanceof Request?new Request(url,input):url;
  }
  const response=await fetch(input,{...init,signal:AbortSignal.any([AbortSignal.timeout(10000),...(init.signal ? [init.signal] : [])])});
  if(!response.ok)console.log(JSON.stringify({event:'source-http-failure',host:original.hostname,path:original.pathname.slice(0,100),status:response.status}));
  return response;
};

export class SabrAudioSource {
  constructor() { this.context = undefined; this.expires = 0; }
  async session() {
    if(this.context && this.expires>Date.now()) return this.context;
    if(this.context) (await this.context.catch(()=>null))?.origin.close().catch(()=>{});
    const work=(async()=>{
      let yt;
      try{yt=await Innertube.create({lang:'fr',location:'FR',generate_session_locally:false,retrieve_player:true,fetch:boundedFetch});}
      catch(error){
        console.log(JSON.stringify({event:'session-bootstrap-retry',reason:String(error.message).replace(/https?:\/\/\S+/g,'[source]').slice(0,200)}));
        yt=await Innertube.create({lang:'fr',location:'FR',generate_session_locally:true,retrieve_player:true,fetch:boundedFetch});
      }
      let origin;
      try{origin=await createOriginMinter(yt);}
      catch(error){origin=await createOriginMinter(yt,undefined,{skipPage:true});}
      return {yt,origin};
    })();
    this.context=work; this.expires=Date.now()+45*60000;
    try {return await work;} catch(error) {if(this.context===work)this.context=undefined;throw error;}
  }
  async download(id,path,maxFileBytes) {
    const {yt,origin}=await this.session();
    const proof=await origin.mint(id);
    // Bind origin proof to this specific title, not to an unrelated old session.
    const po_token=Buffer.from(proof).toString('base64url');
    const info=await yt.getBasicInfo(id,{client:'WEB',po_token});
    if(info.playability_status?.status!=='OK') throw Error(info.playability_status?.reason || 'Titre indisponible');
    const config=info.player_config?.media_common_config?.media_ustreamer_request_config?.video_playback_ustreamer_config;
    const server=info.streaming_data?.server_abr_streaming_url;
    if(!server || !config) throw Error('Le fournisseur ne propose pas de flux SABR');
    const url=await yt.session.player.decipher(server);
    const controller=new AbortController();
    const timeout=setTimeout(()=>controller.abort(Error('Préparation SABR trop lente')),25000);
    const stream=new SabrStream({videoId:id,serverAbrStreamingUrl:url,videoPlaybackUstreamerConfig:config,
      formats:info.streaming_data.adaptive_formats.map(buildSabrFormat),fetchFunction:boundedFetch,
      poToken:po_token,clientInfo:{clientName:Number(Constants.CLIENT_NAME_IDS[yt.session.context.client.clientName]),clientVersion:yt.session.context.client.clientVersion},
      callbacks:{onMintPoToken:()=>origin.mint(id)}});
    let failure;
    stream.on('error',error=>{failure=error;controller.abort(error);});
    let attestationAccepted=false;
    stream.on('streamProtectionStatusUpdate',state=>{if(state.status===1)attestationAccepted=true;});
    let bytes=0,head=Buffer.alloc(0);
    try {
      const output=stream.start({enabledTrackTypes:EnabledTrackTypes.AUDIO_ONLY,maxRetries:1,stallDetectionMs:8000,isPostLiveDvr:false,
        audioPreferences:{container:'mp4',preferredAudioCodec:'aac',dynamicRangeCompression:false,voiceBoost:false}});
      const expected=Number(output.selectedFormats.audioFormat.contentLength);
      if(!Number.isSafeInteger(expected) || expected<=0 || expected>maxFileBytes) throw Error('Taille AAC absente ou trop importante');
      const guard=new Transform({transform(chunk,_,done){
        bytes+=chunk.length;
        if(head.length<64)head=Buffer.concat([head,Buffer.from(chunk).subarray(0,64-head.length)]);
        done(bytes>maxFileBytes || bytes>expected ? Error('Flux AAC hors limites de taille') : null,chunk);
      }});
      await pipeline(Readable.fromWeb(output.audioStream),guard,createWriteStream(path,{flags:'wx'}),{signal:controller.signal});
      const size=(await stat(path)).size;
      if(size!==expected || !head.includes(Buffer.from('ftyp')))throw Error('Flux SABR incomplet ou non M4A');
      return {path,size,bitrate:Number(output.selectedFormats.audioFormat.bitrate)||0,duration:info.basic_info.duration||0,
        client:'WEB/SABR',attestationAccepted};
    } catch(error) {throw failure || error;}
    finally {clearTimeout(timeout);await stream.abort();}
  }
  async close() {if(this.context)(await this.context.catch(()=>null))?.origin.close().catch(()=>{});this.context=undefined;}
}
