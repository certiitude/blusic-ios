// Reports advertised audio formats only; does not claim that a format plays.
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import vm from 'node:vm';
const require=createRequire(process.argv[2]+'/package.json');
const {Innertube,Platform}=await import(pathToFileURL(require.resolve('youtubei.js')).href);
Platform.shim.eval=async data=>vm.runInNewContext(`(() => { ${data.output} })()`,Object.create(null),{timeout:1500});
const yt=await Innertube.create({lang:'fr',location:'FR',generate_session_locally:false});
for(const id of process.argv.slice(3)){
  try{
    const info=await yt.getBasicInfo(id,{client:'WEB'});
    console.log(JSON.stringify({id,status:info.playability_status?.status,formats:(info.streaming_data?.adaptive_formats||[])
      .filter(f=>f.has_audio&&!f.has_video).map(f=>({itag:f.itag,mime:f.mime_type,bitrate:f.bitrate,averageBitrate:f.average_bitrate,
        quality:f.audio_quality,sampleRate:f.audio_sample_rate,channels:f.audio_channels,bytes:f.content_length,drm:!!f.drm_families?.length}))}));
  }catch(error){console.log(JSON.stringify({id,error:String(error.message).replace(/https?:\/\/\S+/g,'[source]')}));process.exitCode=1;}
}
