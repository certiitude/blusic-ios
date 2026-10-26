import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {makeServer} from './server.mjs';
import {parseRange, ticket, verifyTicket, clientCapability, verifyClientCapability, applicationAccess} from './protocol.mjs';
const key = 'test-key-not-a-real-secret-123456789';
test('application access has no expiry and cannot act as the master signing key', () => {
  const access = applicationAccess(key);
  assert.equal(verifyClientCapability(key,`Bearer ${access}`,Date.now()+50*365*86400000),true);
  assert.equal(verifyClientCapability(key,`Bearer ${access.slice(0,-1)}x`),false);
  assert.equal(verifyTicket(key,'abcdefghijk',ticket(access,'abcdefghijk',Date.now()+10000)),false);
  assert.equal(access.includes(key),false);
  const android=applicationAccess(key,'android');
  assert.equal(verifyClientCapability(key,`Bearer ${android}`,Date.now()+50*365*86400000),true);
  assert.notEqual(android,access);
  assert.equal(verifyClientCapability(key,`Bearer ${android.replace('app.android.','app.ios.')}`),false);
});
test('IPA capabilities expire and cannot forge media tickets', () => {
  const now = Date.now(), expiry = now + 86400000;
  const capability = clientCapability(key, expiry);
  assert.equal(verifyClientCapability(key,`Bearer ${capability}`,now),true);
  assert.equal(verifyClientCapability(key,`Bearer ${capability}`,expiry+1),false);
  assert.equal(verifyClientCapability(key,`Bearer ${capability.slice(0,-1)}x`,now),false);
  assert.equal(verifyTicket(key,'abcdefghijk',ticket(capability,'abcdefghijk',now+10000),now),false);
  assert.equal(capability.includes(key),false);
});
test('tickets bind video and expire; byte ranges keep exact boundaries', () => {
  const now = 100000, value = ticket(key,'abcdefghijk',now+1000);
  assert.equal(verifyTicket(key,'abcdefghijk',value,now),true);
  assert.equal(verifyTicket(key,'bbbbbbbbbbb',value,now),false);
  assert.equal(verifyTicket(key,'abcdefghijk',value,now+2000),false);
  assert.deepEqual(parseRange('bytes=10-19',100),{start:10,end:19,partial:true});
  assert.deepEqual(parseRange('bytes=-10',100),{start:90,end:99,partial:true});
  assert.equal(parseRange('bytes=100-200',100),null);
  assert.equal(parseRange('bytes=5-2',100),null);
});
test('authenticated resolver serves exact media ranges; never arbitrary upstream URLs', async () => {
  const dir = await mkdtemp(join(tmpdir(),'blusic-test-'));
  const path = join(dir,'fixture.m4a'); const audio = Buffer.from('0000ftypM4A fixture bytes for protocol test');
  await writeFile(path,audio);
  let calls = 0;
  const provider = {prepare: async () => { calls++; return {path,size:audio.length,bitrate:128000,duration:48}; }};
  const server = makeServer({key,provider});
  await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
  const base = `http://127.0.0.1:${server.address().port}`;
  try {
    assert.equal((await fetch(base+'/v1/streams/abcdefghijk')).status,401);
    assert.equal(calls,0);
    const result = await fetch(base+'/v1/streams/abcdefghijk',{headers:{Authorization:`Bearer ${key}`}});
    assert.equal(result.status,200); const body = await result.json();
    assert.equal(body.bitrate,128000);
    const configuredClient = await fetch(base+'/v1/streams/abcdefghijk',{headers:{Authorization:`Bearer ${clientCapability(key,Date.now()+86400000)}`}});
    assert.equal(configuredClient.status,200);
    for (let i=0;i<32;i++) {
      const request = await fetch(base+'/v1/streams/abcdefghijk',{headers:{Authorization:`Bearer ${applicationAccess(key)}`}});
      assert.equal(request.status,200,'No artificial per-minute listening quota for the application');
      await request.arrayBuffer();
    }
    const part = await fetch(base+body.url,{headers:{Range:'bytes=4-11'}});
    assert.equal(part.status,206); assert.equal(part.headers.get('Content-Range'),`bytes 4-11/${audio.length}`);
    assert.deepEqual(Buffer.from(await part.arrayBuffer()),audio.subarray(4,12));
    assert.equal((await fetch(base+'/v1/audio/abcdefghijk?ticket=invalid')).status,403);
    assert.equal((await fetch(base+'/v1/streams/https://example.org',{headers:{Authorization:`Bearer ${key}`}})).status,404);
  } finally { await new Promise(resolve=>server.close(resolve)); await rm(dir,{recursive:true,force:true}); }
});
test('upstream refusal stays a 502 instead of fake playable audio', async () => {
  const server = makeServer({key,provider:{prepare:async()=>{throw Error('upstream HTTP 403');}}});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  try {
    const response = await fetch(`http://127.0.0.1:${server.address().port}/v1/streams/abcdefghijk`,{headers:{Authorization:`Bearer ${key}`}});
    assert.equal(response.status,502); assert.match((await response.json()).error,/403/);
  } finally { await new Promise(resolve=>server.close(resolve)); }
});
test('high quality reaches the provider and stays bound to its media ticket',async()=>{
  const dir=await mkdtemp(join(tmpdir(),'blusic-quality-test-'));
  const path=join(dir,'fixture.m4a'),audio=Buffer.from('0000ftypM4A quality protocol fixture');
  await writeFile(path,audio);
  const qualities=[];
  const provider={prepare:async(id,quality)=>{qualities.push(quality);return {path,size:audio.length,bitrate:quality==='high'?256000:131000,duration:48};}};
  const server=makeServer({key,provider});await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const base=`http://127.0.0.1:${server.address().port}`,headers={Authorization:`Bearer ${applicationAccess(key)}`};
  try{
    const response=await fetch(base+'/v1/streams/abcdefghijk?quality=high',{headers});
    assert.equal(response.status,200);
    const payload=await response.json();assert.equal(payload.bitrate,256000);assert.equal(payload.requestedQuality,'high');
    assert.equal(new URL(payload.url,base).searchParams.get('quality'),'high');
    const media=await fetch(base+payload.url);assert.equal(media.status,200);assert.deepEqual(Buffer.from(await media.arrayBuffer()),audio);
    const tampered=new URL(payload.url,base);tampered.searchParams.delete('quality');
    assert.equal((await fetch(tampered)).status,403,'A high-quality ticket must not serve another variant');
    assert.deepEqual(qualities,['high','high']);
    assert.equal((await fetch(base+'/v1/streams/abcdefghijk?quality=lossless',{headers})).status,400);
  }finally{await new Promise(resolve=>server.close(resolve));await rm(dir,{recursive:true,force:true});}
});
