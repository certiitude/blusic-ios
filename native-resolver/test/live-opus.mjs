// Optional real-network diagnostic. Not part of deterministic/offline tests.
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import {writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {SabrAudioSource} from '../../relay/sabr.mjs';
import {preferredOpus,remuxOpusToCAF} from '../opus-caf.mjs';
const require=createRequire(new URL('../package.json',import.meta.url));
const {SabrStream}=await import(pathToFileURL(require.resolve('googlevideo/sabr-stream')));
const {buildSabrFormat,EnabledTrackTypes}=await import(pathToFileURL(require.resolve('googlevideo/utils')));
const {Constants}=await import(pathToFileURL(require.resolve('youtubei.js')));
const id=process.argv[2]||'RFzfXv9wzfo',source=new SabrAudioSource();let stream;
try{
  const {yt,origin}=await source.session(),proof=await origin.mint(id),po_token=Buffer.from(proof).toString('base64url');
  const info=await yt.getBasicInfo(id,{client:'WEB',po_token});
  if(info.playability_status?.status!=='OK')throw Error(info.playability_status?.reason||'Not playable');
  const formats=preferredOpus(info.streaming_data?.adaptive_formats);
  if(!formats.length)throw Error('No public original Opus 251');
  const config=info.player_config?.media_common_config?.media_ustreamer_request_config?.video_playback_ustreamer_config;
  stream=new SabrStream({videoId:id,serverAbrStreamingUrl:await yt.session.player.decipher(info.streaming_data.server_abr_streaming_url),videoPlaybackUstreamerConfig:config,
    formats:formats.map(buildSabrFormat),poToken:po_token,fetchFunction:(url,init={})=>fetch(url,{...init,signal:AbortSignal.timeout(15000)}),
    clientInfo:{clientName:Number(Constants.CLIENT_NAME_IDS[yt.session.context.client.clientName]),clientVersion:yt.session.context.client.clientVersion},callbacks:{onMintPoToken:()=>origin.mint(id)}});
  let failure;stream.on('error',e=>{failure=e;stream.abort();});
  const timer=setTimeout(()=>stream.abort(),45000);
  const output=stream.start({enabledTrackTypes:EnabledTrackTypes.AUDIO_ONLY,maxRetries:1,stallDetectionMs:8000,isPostLiveDvr:false,audioPreferences:{container:'webm',preferredAudioCodec:'opus',dynamicRangeCompression:false,voiceBoost:false}});
  const parts=[];let bytes=0;
  try{for await(const piece of output.audioStream){bytes+=piece.length;if(bytes>25_000_000)throw Error('File too large');parts.push(Buffer.from(piece));}}finally{clearTimeout(timer);}
  if(failure)throw failure;
  if(bytes!==Number(output.selectedFormats.audioFormat.contentLength))throw Error('Incomplete Opus file');
  const webm=Buffer.concat(parts),result=remuxOpusToCAF(webm);
  if(result.duration<info.basic_info.duration-Math.max(2,info.basic_info.duration*.02))throw Error('Incomplete song duration');
  const base=join(process.env.LOCALAPPDATA,'Temp/opencode','soryn-live-opus-'+id);
  await writeFile(base+'.webm',webm);await writeFile(base+'.caf',result.data);
  console.log(JSON.stringify({videoID:id,fullFile:true,codec:'opus',source:'WEB/SABR',bytes,duration:result.duration,measuredAudioBitrate:result.bitrate,packets:result.packets}));
}catch(error){console.error(JSON.stringify({videoID:id,fullFile:false,error:String(error.message).replace(/https?:\/\/\S+/g,'[source]').slice(0,350)}));process.exitCode=1;}
finally{await stream?.abort();await source.close();}
