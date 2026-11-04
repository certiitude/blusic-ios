import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm,stat} from 'node:fs/promises';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {relayConfiguration,publicMediaURL,downloadVerifiedAudio,prepareRelay,prepareInvidious,discoverInvidious} from '../core/online-audio.mjs';
const config={url:'https://relay.example.org',applicationAccess:'app.ios.'+'0'.repeat(64),expiresAt:0};
test('bundled relay accepts only non-expiring application access, never an arbitrary master key',()=>{
  assert.equal(relayConfiguration(config).url,config.url);
  for(const patch of [{applicationAccess:'owner-secret-master-key'},{expiresAt:123},{url:'http://relay.example.org'},{url:'https://user:pass@relay.example.org'},{url:'https://relay.example.org/path'}])assert.throws(()=>relayConfiguration({...config,...patch}));
});
test('media locations reject private hosts, insecure URLs and unexpected relay origins',()=>{
  for(const address of ['http://media.example.org/a','https://localhost/audio','https://192.168.1.2/audio','https://[::1]/audio','https://user:pass@media.example.org/a','https://router.local/a'])assert.throws(()=>publicMediaURL(address));
  assert.equal(publicMediaURL('/v1/audio/test',config.url).origin,config.url);
  assert.throws(()=>publicMediaURL('https://other.example.org/audio',config.url));
});
test('download bounds, complete size and duration are enforced before admitting a file',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'soryn-download-test-'));t.after(()=>rm(directory,{recursive:true,force:true}));
  const bytes=Buffer.concat([Buffer.from('\0\0\0\x18ftypM4A '),Buffer.alloc(60)]);
  const response=()=>new Response(bytes,{headers:{'Content-Type':'audio/mp4','Content-Length':String(bytes.length)}});
  const base={url:'https://media.example.org/audio',path:join(directory,'audio.m4a'),expectedSize:bytes.length,expectedDuration:48,fetchFunction:async()=>response(),inspectFile:async()=>({format:{duration:48,bitrate:128000}})};
  const result=await downloadVerifiedAudio(base);assert.equal(result.size,bytes.length);await rm(base.path);
  await assert.rejects(()=>downloadVerifiedAudio({...base,expectedSize:bytes.length+1}),/incomplet/);await assert.rejects(()=>stat(base.path));
  await assert.rejects(()=>downloadVerifiedAudio({...base,inspectFile:async()=>({format:{duration:5}})}),/tronqué/);await assert.rejects(()=>stat(base.path));
  await assert.rejects(()=>downloadVerifiedAudio({...base,fetchFunction:async()=>new Response('<html>refused</html>',{headers:{'Content-Type':'text/html'}})}),/AAC/);
  await assert.rejects(()=>downloadVerifiedAudio({...base,fetchFunction:async()=>new Response(null,{status:403})}),/403/);
  await assert.rejects(()=>downloadVerifiedAudio({...base,fetchFunction:async()=>new Response(null,{status:302,headers:{Location:'https://127.0.0.1/private'}})}),/privée/);
});
test('relay access is sent only to metadata origin, no untrusted signed media destination accepted',async()=>{
  const calls=[];
  await assert.rejects(()=>prepareRelay('RFzfXv9wzfo',config,'unused.m4a',0,{fetchFunction:async(url,init)=>{calls.push({url,init});return Response.json({url:'https://other.example.org/audio',size:50});}}),/Hôte|externe/);
  assert.equal(calls.length,1);assert.equal(calls[0].init.headers.Authorization,`Bearer ${config.applicationAccess}`);assert.equal(calls[0].init.redirect,'error');
});
test('Invidious retries failed API instances and rejects non-AAC formats',async()=>{
  let count=0;
  await assert.rejects(()=>prepareInvidious('RFzfXv9wzfo',['https://first.example.org','https://second.example.org'],'unused.m4a',0,{fetchFunction:async()=>{count++;return count===1?new Response(null,{status:502}):Response.json({adaptiveFormats:[{type:'audio/webm',url:'https://second.example.org/audio'}]});}}),/Aucune instance/);
  assert.equal(count,2);
});
test('Invidious discovery accepts only public HTTPS instances that explicitly advertise their API',async()=>{
  const response=[['safe',{api:true,uri:'https://api.example.org'}],['private',{api:true,uri:'https://127.0.0.1'}],['noAPI',{api:false,uri:'https://no.example.org'}],['http',{api:true,uri:'http://unsafe.example.org'}]];
  assert.deepEqual(await discoverInvidious({fetchFunction:async()=>Response.json(response)}),['https://api.example.org']);
});
