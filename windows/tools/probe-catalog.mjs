import {catalogSearch,browse} from '../core/catalog.mjs';
import {readFile,mkdir,writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
const query=process.argv[2]||'Damso',results={query};
for(const kind of ['songs','albums','artists','playlists']){
  try{
    const page=await catalogSearch({query,kind});results[kind]={tracks:page.tracks.length,items:page.items.length,hasMore:!!page.continuation};
    if(kind==='songs'&&page.continuation){const more=await catalogSearch({query,kind,continuation:page.continuation});results[kind].nextPage=more.tracks.length;}
    const item=page.items[0];if(item){const detail=await browse(item);results[kind].opened={title:detail.title,tracks:detail.tracks.length,hasMore:!!detail.continuation};}
  }catch(error){results[kind]={error:error.message};}
}
try{
  const config=JSON.parse(await readFile(resolve('assets/relay-config.json'),'utf8'));
  const health=await fetch(config.url+'/health',{signal:AbortSignal.timeout(60000)});results.relay={configured:true,host:new URL(config.url).hostname,healthHTTP:health.status,expiresAt:config.expiresAt};
  const authorization=await fetch(config.url+'/v1/streams/RFzfXv9wzfo?quality=high',{headers:{Authorization:`Bearer ${config.applicationAccess}`},signal:AbortSignal.timeout(60000)});
  results.relay.audioHTTP=authorization.status;results.relay.accessRejected=authorization.status===401;
}catch(error){results.relay={error:String(error.message).replace(/https?:\/\/\S+/g,'[source]')};}
await mkdir(resolve('test-output'),{recursive:true});await writeFile(resolve('test-output/catalog-live.json'),JSON.stringify(results,null,2));console.log(JSON.stringify(results,null,2));
