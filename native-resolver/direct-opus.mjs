import {Innertube} from 'youtubei.js';
import {preferredOpus} from './opus-caf.mjs';

export async function fetchPublicOpus(id,{fetchFunction=fetch,signal}={}){
  if(!/^[\w-]{11}$/.test(id))throw Error('Identifiant musical invalide');
  const yt=await Innertube.create({lang:'fr',location:'FR',generate_session_locally:true,retrieve_player:false,fetch:fetchFunction});
  const info=await yt.getBasicInfo(id,{client:'ANDROID'});
  if(info.playability_status?.status!=='OK')throw Error('Opus direct indisponible');
  const f=preferredOpus(info.streaming_data?.adaptive_formats)[0];if(!f?.url)throw Error('URL Opus directe indisponible ; SABR requis');
  return {data:await downloadOpusRanges(f,{fetchFunction,signal}),sourceDuration:info.basic_info.duration||0};
}
export async function downloadOpusRanges(f,{fetchFunction=fetch,signal}={}){
  if(!preferredOpus([f]).length)throw Error('Format Opus 251 invalide');
  const address=new URL(f.url);if(address.protocol!=='https:'||!address.hostname.endsWith('.googlevideo.com')||address.username||address.password||address.port&&address.port!=='443')throw Error('Hôte Opus inattendu');
  const expected=Number(f.content_length),data=new Uint8Array(expected);let offset=0;
  while(offset<expected){
    signal?.throwIfAborted();const end=Math.min(offset+262143,expected-1),url=new URL(address);url.searchParams.set('range',`${offset}-${end}`);
    const response=await fetchFunction(url,{headers:{Range:`bytes=${offset}-${end}`},signal});
    if(![200,206].includes(response.status))throw Error(`Opus direct HTTP ${response.status}`);
    const reader=response.body.getReader();let received=0;
    try{while(true){signal?.throwIfAborted();const {value,done}=await reader.read();if(done)break;received+=value.length;if(received>end-offset+1)throw Error('Plage Opus ignorée');data.set(value,offset+received-value.length);}}finally{await reader.cancel();}
    if(received!==end-offset+1)throw Error('Plage Opus incomplète');
    const range=response.headers.get('Content-Range');if(range&&range!==`bytes ${offset}-${end}/${expected}`)throw Error('Plage Opus incohérente');
    offset+=received;
  }
  return data;
}
