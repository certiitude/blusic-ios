import {parentPort, workerData} from 'node:worker_threads';
import {parseFile} from 'music-metadata';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {prepareRelay,prepareInvidious,DEFAULT_INVIDIOUS} from './online-audio.mjs';
import {YouTubeProvider} from '../vendor/provider.mjs';
const provider = new YouTubeProvider({maxFileBytes: 100_000_000});
const directory=await mkdtemp(join(tmpdir(),'soryn-online-')),controllers=[],workers=[];
try {
  const local=(async()=>{
    const entry=await provider.prepare(workerData.videoID,'high'),metadata=await parseFile(entry.path,{duration:true});
    if(!(metadata.format.duration>0)||workerData.duration>0&&metadata.format.duration<workerData.duration-Math.max(2,workerData.duration*.02))throw Error('Fichier audio incomplet : durée invalide.');
    return {path:entry.path,duration:metadata.format.duration,bitrate:entry.bitrate,size:entry.size,source:'youtubei.js sur ce PC'};
  })();
  workers.push(local);
  if(workerData.relay){const controller=new AbortController();controllers.push(controller);workers.push(prepareRelay(workerData.videoID,workerData.relay,join(directory,'relay.m4a'),workerData.duration,{signal:AbortSignal.any([controller.signal,AbortSignal.timeout(55000)])}));}
  const invController=new AbortController();controllers.push(invController);
  workers.push(prepareInvidious(workerData.videoID,workerData.instances||DEFAULT_INVIDIOUS,join(directory,'invidious.m4a'),workerData.duration,{signal:AbortSignal.any([invController.signal,AbortSignal.timeout(35000)]),discover:true}));
  let result;
  try{result=await Promise.any(workers);}catch(error){throw Error('Aucune source audio accessible. '+error.errors.map(e=>String(e.message)).join(' · '));}
  // Never interrupt the winner's file before main acknowledges its copy.
  controllers.forEach(c=>c.abort());
  parentPort.postMessage(result);
  // Main copies the validated file before acknowledging and deleting scratch data.
  await new Promise(resolve => parentPort.once('message', resolve));
} catch (error) { parentPort.postMessage({error: String(error.message).replace(/https?:\/\/\S+/g, '[source]').slice(0, 800)}); }
finally { controllers.forEach(c=>c.abort());await provider.close();await Promise.allSettled(workers);await rm(directory,{recursive:true,force:true}); }
