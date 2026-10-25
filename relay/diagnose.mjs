import {YouTubeProvider} from './provider.mjs';
import {validVideo} from './protocol.mjs';
const id = process.argv[2];
if (!validVideo(id || '')) throw Error('Indique un identifiant vidéo de 11 caractères');
const provider = new YouTubeProvider();
const start = performance.now();
try {
  const file = await provider.prepare(id);
  console.log(JSON.stringify({id,complete:true,bytes:file.size,client:file.client,bitrate:file.bitrate,duration:file.duration,seconds:(performance.now()-start)/1000}));
} catch (error) {
  console.log(JSON.stringify({id,complete:false,error:error.message,seconds:(performance.now()-start)/1000}));
  process.exitCode = 1;
} finally { await provider.close(); }
