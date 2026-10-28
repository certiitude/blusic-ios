// Live network diagnostic: success means a complete AAC was parsed, not just a URL.
import {Worker} from 'node:worker_threads';
import {writeFile, mkdir} from 'node:fs/promises';
import {resolve} from 'node:path';
const started=Date.now();
const worker=new Worker(new URL('../core/audio-worker.mjs',import.meta.url),{workerData:{videoID:process.argv[2]||'RFzfXv9wzfo',duration:0}});
const result=await new Promise(resolve=>{
  const timer=setTimeout(()=>{worker.terminate();resolve({error:'65-second deadline exceeded'});},65000);
  worker.once('message',value=>{clearTimeout(timer);resolve(value);});worker.once('error',error=>{clearTimeout(timer);resolve({error:error.message});});
});
worker.postMessage('copied');
await worker.terminate();
delete result.path;
result.seconds=(Date.now()-started)/1000;
await mkdir(resolve('test-output'),{recursive:true});await writeFile(resolve('test-output/live-audio.json'),JSON.stringify(result,null,2));
console.log(JSON.stringify(result,null,2));
if(result.error)process.exitCode=1;
