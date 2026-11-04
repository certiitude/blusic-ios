import test from 'node:test';
import assert from 'node:assert/strict';
import {PGlite} from '@electric-sql/pglite';
import {createServer} from 'node:http';
import {randomUUID} from 'node:crypto';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {Accounts,accountHandler,hashPassword,verifyPassword,username} from '../accounts.mjs';
import {seed,sharedSnapshot} from '../../windows/core/library.mjs';

test('passwords use salted scrypt, username validation is bounded and case-insensitive',async()=>{
  assert.equal(username('Soryn_Fan'),'soryn_fan');for(const value of ['ab','name with spaces','<script>','a'.repeat(25)])assert.throws(()=>username(value));
  const a=await hashPassword('a unique password 123'),b=await hashPassword('a unique password 123');assert.notEqual(a,b);assert.equal(a.includes('a unique password'),false);assert.equal(await verifyPassword('a unique password 123',a),true);assert.equal(await verifyPassword('wrong password',a),false);await assert.rejects(()=>hashPassword('short'));
});
test('real PostgreSQL storage and HTTP accounts: isolation, authentication, durable sync, no lost responses',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'soryn-account-db-'));let pg=new PGlite(directory);await pg.waitReady;
  const db=()=>({query:(...args)=>pg.query(...args),transaction:fn=>pg.transaction(fn)});let accounts=new Accounts(db());await accounts.init();
  const server=createServer(accountHandler(accounts,{allowHTTP:true}));await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  t.after(async()=>{await new Promise(resolve=>{server.close(resolve);server.closeAllConnections();});await pg.close();await rm(directory,{recursive:true,force:true});});
  const call=async(path,input={},token)=>{const r=await fetch(`http://127.0.0.1:${server.address().port}/v1/accounts/${path}`,{method:'POST',headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(input)});return {status:r.status,body:await r.json()};};
  const first=await call('register',{username:'Music_Fan',password:'a unique password 123'});assert.equal(first.status,200);const token=first.body.token;assert.equal(token.length,43);assert.equal(first.body.account.username,'music_fan');
  assert.equal((await call('register',{username:'MUSIC_fan',password:'another password 123'})).status,409);
  assert.equal((await call('login',{username:'music_fan',password:'bad password 123'})).status,401);assert.equal((await call('login',{username:'unknown_user',password:'bad password 123'})).status,401);
  const second=await call('register',{username:'Other_User',password:'another password 123'});assert.equal(second.status,200);
  const stored=await pg.query('SELECT password_hash FROM soryn_accounts');assert.ok(stored.rows.every(row=>row.password_hash.startsWith('scrypt-v1$')&&!row.password_hash.includes('password')));
  const sessions=await pg.query('SELECT token_hash FROM soryn_sessions');assert.ok(sessions.rows.every(row=>row.token_hash!==token&&row.token_hash.length===64));
  const snapshot=sharedSnapshot(seed()),deviceA=randomUUID(),deviceB=randomUUID();snapshot.playlists[0].name='Mes titres depuis le PC';snapshot.favorites=[snapshot.tracks[0].id];
  // Swift UUID.uuidString uses uppercase, PostgreSQL returns lowercase UUIDs.
  const packet=(deviceID,snapshot,ack)=>({protocol:1,deviceID:deviceID.toUpperCase(),requestID:randomUUID().toUpperCase(),snapshot,acknowledgedRequestID:ack});
  const a=await call('sync',packet(deviceA,snapshot),token);assert.equal(a.status,200);assert.equal(a.body.snapshot.favorites.length,1);
  const empty=()=>({version:1,tracks:[],playlists:[],favorites:[],history:[],followedArtists:[],settings:{},queue:[]});
  const other=await call('sync',packet(randomUUID(),empty()),second.body.token);assert.equal(other.status,200);assert.equal(other.body.snapshot.tracks.length,0);
  const b=await call('sync',packet(deviceB,empty()),token);assert.equal(b.body.snapshot.playlists[0].name,'Mes titres depuis le PC');
  const phone=structuredClone(b.body.snapshot);phone.playlists[0].name='Renommée sur iPhone';phone.favorites=[];
  const b2=await call('sync',packet(deviceB,phone,b.body.requestID),token);assert.equal(b2.status,200);assert.equal(b2.body.snapshot.favorites.length,0);
  const a2=await call('sync',packet(deviceA,a.body.snapshot,a.body.requestID),token);assert.equal(a2.body.snapshot.playlists[0].name,'Renommée sur iPhone');assert.equal(a2.body.snapshot.favorites.length,0);
  const unseen=structuredClone(a2.body.snapshot);unseen.playlists.push({id:randomUUID(),name:'Jamais reçu sur iPhone',detail:'',trackIDs:[],createdAt:1,symbol:'waveform'});
  await call('sync',packet(deviceA,unseen,a2.body.requestID),token);
  await call('sync',packet(deviceB,b2.body.snapshot,b2.body.requestID),token); // Pretend this response was lost.
  const retry=await call('sync',packet(deviceB,b2.body.snapshot,b2.body.requestID),token);assert.ok(retry.body.snapshot.playlists.some(p=>p.name==='Jamais reçu sur iPhone'));
  const invalid=await call('sync',packet(deviceB,{...empty(),version:99}),token);assert.equal(invalid.status,400);
  assert.equal((await call('sync',packet(deviceB,empty()),'x'.repeat(43))).status,401);
  await pg.close();pg=new PGlite(directory);await pg.waitReady;accounts.db=db();
  const afterRestart=await call('sync',packet(randomUUID(),empty()),token);assert.equal(afterRestart.status,200);assert.ok(afterRestart.body.snapshot.playlists.some(p=>p.name==='Jamais reçu sur iPhone'));
  assert.equal((await call('logout',{},token)).status,200);assert.equal((await call('me',{},token)).status,401);
  const login=await call('login',{username:'MUSIC_FAN',password:'a unique password 123'});assert.equal(login.status,200);
  assert.equal((await call('delete',{password:'wrong password 123'},login.body.token)).status,401);
  assert.equal((await call('delete',{password:'a unique password 123'},login.body.token)).status,200);assert.equal((await call('me',{},login.body.token)).status,401);
  assert.equal((await pg.query('SELECT * FROM soryn_cloud_libraries WHERE account_id=$1',[first.body.account.id])).rows.length,0);
  assert.equal((await call('me',{},second.body.token)).status,200);
});
test('service without durable storage refuses registration rather than accepting temporary accounts',async t=>{
  const server=createServer(accountHandler(undefined,{allowHTTP:true}));await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));t.after(()=>new Promise(resolve=>server.close(resolve)));
  const base=`http://127.0.0.1:${server.address().port}`;const health=await(await fetch(base+'/health')).json();assert.equal(health.accounts,false);
  const r=await fetch(base+'/v1/accounts/register',{method:'POST',body:JSON.stringify({username:'Tester',password:'safe password 123'})});assert.equal(r.status,503);
});
