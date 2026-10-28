import test from 'node:test';
import assert from 'node:assert/strict';
import {randomBytes, randomUUID} from 'node:crypto';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {LibraryStore, sharedSnapshot} from '../core/library.mjs';
import {SyncServer, seal, unseal, isPrivate} from '../core/sync.mjs';

test('AES-GCM authenticates content, context and the paired key',()=>{
  const key=randomBytes(32),value={title:'Écoutez le moment.',favorites:['a']},box=seal(value,key);assert.deepEqual(unseal(box,key),value);
  assert.throws(()=>unseal(box,randomBytes(32)));
  const bytes=Buffer.from(box.box,'base64');bytes[13]^=1;assert.throws(()=>unseal({...box,box:bytes.toString('base64')},key));
  assert.notEqual(seal(value,key).box,box.box);
});
test('only private and loopback IPv4 addresses accepted',()=>{
  for(const ip of ['127.0.0.1','10.0.0.3','172.16.0.1','172.31.255.255','192.168.12.2'])assert.equal(isPrivate(ip),true,ip);
  for(const ip of ['8.8.8.8','172.32.0.1','192.169.0.1','999.0.0.1','::1','example.com',''])assert.equal(isPrivate(ip),false,ip);
});
test('real encrypted HTTP exchange, replay rejection, restart baseline and favorite removal',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'soryn-sync-test-'));const store=new LibraryStore(directory);await store.load();let server=new SyncServer(store);const key=randomBytes(32);
  t.after(async()=>{await server.stop();await rm(directory,{recursive:true,force:true});});
  await server.start(key);const deviceID=randomUUID();let snapshot=sharedSnapshot(store.data);
  async function exchange(body){return fetch(`http://127.0.0.1:${server.port}/v1/sync`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});}
  const packet=()=>({protocol:1,deviceID,requestID:randomUUID(),sentAt:Date.now(),snapshot});
  snapshot.favorites=[snapshot.tracks[0].id];let body=seal(packet(),key),response=await exchange(body);assert.equal(response.status,200);
  snapshot=unseal(await response.json(),key).snapshot;assert.equal(store.data.favorites.length,1);
  assert.equal((await exchange(body)).status,409);
  assert.equal((await exchange(seal(packet(),randomBytes(32)))).status,400);
  assert.equal((await exchange(seal({...packet(),sentAt:1},key))).status,409);
  await server.stop();server=new SyncServer(store);await server.start(key);
  snapshot.favorites=[];response=await exchange(seal(packet(),key));assert.equal(response.status,200);assert.equal(store.data.favorites.length,0);
  assert.equal(unseal(await response.json(),key).snapshot.tracks.length,4);
  const fromBrowser=await fetch(`http://127.0.0.1:${server.port}/v1/sync`,{method:'POST',headers:{Origin:'https://attacker.invalid'},body:JSON.stringify(seal(packet(),key))});assert.equal(fromBrowser.status,404);
});
