// Reports advertised audio formats only; does not claim that a format plays.
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import vm from 'node:vm';
const require=createRequire(process.argv[2]+'/package.json');
const {Innertube,Platform}=await import(pathToFileURL(require.resolve('youtubei.js')).href);
Platform.shim.eval=async data=>vm.runInNewContext(`(() => { ${data.output} })()`,Object.create(null),{timeout:1500});
const yt=await Innertube.create({lang:'fr',location:'FR',generate_session_locally:false});
const args=process.argv.slice(3),client=args.find(value=>value.startsWith('--client='))?.slice(9)||'WEB';
if(!['WEB','YTMUSIC','IOS','YTMUSIC_ANDROID'].includes(client))throw Error('Unsupported diagnostic client');
for(const id of args.filter(value=>!value.startsWith('--'))){
  try{
    const info=await yt.getBasicInfo(id,{client});
    console.log(JSON.stringify({id,client,status:info.playability_status?.status,formats:(info.streaming_data?.adaptive_formats||[])
      .filter(f=>f.has_audio&&!f.has_video).map(f=>({itag:f.itag,mime:f.mime_type,bitrate:f.bitrate,averageBitrate:f.average_bitrate,
        quality:f.audio_quality,sampleRate:f.audio_sample_rate,channels:f.audio_channels,bytes:f.content_length,drm:!!f.drm_families?.length}))}));
  }catch(error){console.log(JSON.stringify({id,error:String(error.message).replace(/https?:\/\/\S+/g,'[source]')}));process.exitCode=1;}
}
