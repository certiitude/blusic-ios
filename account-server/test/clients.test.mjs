import test from 'node:test';
import assert from 'node:assert/strict';
import {PGlite} from '@electric-sql/pglite';
import pg from 'pg';
import {createServer} from 'node:http';
import {randomBytes,randomUUID,createCipheriv,createDecipheriv} from 'node:crypto';
import {mkdtemp,rm,readFile,readdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {Accounts,accountHandler} from '../accounts.mjs';
import {databaseOptions} from '../database.mjs';
import {AccountClient,accountServerURL} from '../../windows/core/account-client.mjs';
import {LibraryStore} from '../../windows/core/library.mjs';

// Production uses Electron safeStorage (DPAPI), not this injected test implementation.
function testStorage(){
  const key=randomBytes(32);
  return {async isAsyncEncryptionAvailable(){return true;},async encryptStringAsync(text){const nonce=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key,nonce);const data=Buffer.concat([cipher.update(text),cipher.final()]);return Buffer.concat([nonce,cipher.getAuthTag(),data]);},async decryptStringAsync(data){const cipher=createDecipheriv('aes-256-gcm',key,data.subarray(0,12));cipher.setAuthTag(data.subarray(12,28));return {result:Buffer.concat([cipher.update(data.subarray(28)),cipher.final()]).toString(),shouldReEncrypt:false};}};
}
test('account URL rejects plaintext, credentials, query strings and non-loopback test servers',()=>{
  assert.equal(accountServerURL('https://soryn-accounts.onrender.com'),'https://soryn-accounts.onrender.com');
  for(const url of ['http://example.com','http://127.0.0.1:8000','https://user:secret@example.com','https://example.com/path','https://example.com/?token=secret'])assert.throws(()=>accountServerURL(url));
  assert.equal(accountServerURL('http://127.0.0.1:1234',{allowHTTP:true}),'http://127.0.0.1:1234');
  assert.throws(()=>accountServerURL('http://example.com',{allowHTTP:true}));
});
test('two actual Windows account clients preserve anonymous mode, offline library and cross-device edits',async t=>{
  const directory=await mkdtemp(join(tmpdir(),'soryn-account-clients-'));let pool,embedded,db;
  if(process.env.SORYN_TEST_DATABASE_PRIVATE){
    const privateConfig=JSON.parse(await readFile(process.env.SORYN_TEST_DATABASE_PRIVATE,'utf8'));
    pool=new pg.Pool(databaseOptions(privateConfig.databaseURL));
    db={query:(...args)=>pool.query(...args),async transaction(fn){const c=await pool.connect();try{await c.query('BEGIN');const r=await fn(c);await c.query('COMMIT');return r;}catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}}};
  }else{embedded=new PGlite();await embedded.waitReady;db={query:(...args)=>embedded.query(...args),transaction:fn=>embedded.transaction(fn)};}
  const accounts=new Accounts(db);await accounts.init();
  const server=createServer(accountHandler(accounts,{allowHTTP:true}));await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const serverURL=`http://127.0.0.1:${server.address().port}`,created=[];
  t.after(async()=>{for(const id of created)await db.query('DELETE FROM soryn_accounts WHERE id=$1',[id]);await new Promise(resolve=>{server.close(resolve);server.closeAllConnections();});await pool?.end();await embedded?.close();await rm(directory,{recursive:true,force:true});});
  let calls=0,dropReply=false,duringSync;
  const fetchFunction=async(url,options)=>{calls++;const r=await fetch(url,options);if(url.endsWith('/sync')){if(duringSync){const fn=duringSync;duringSync=null;await fn();}if(dropReply){dropReply=false;await r.arrayBuffer();throw Error('Test: réponse perdue');}}return r;};
  const make=async(name)=>{const store=new LibraryStore(join(directory,name));await store.load();const secureStorage=testStorage(),client=new AccountClient({store,secureStorage,server:serverURL,allowHTTP:true,fetchFunction});await client.load();return {client,store,secureStorage};};
  const a=await make('PC'),b=await make('phone-protocol-peer');await a.client.sync();await b.client.sync();assert.equal(calls,0,'Anonymous mode must not contact the service');
  const credentials={username:'qa_'+randomBytes(7).toString('hex'),password:randomBytes(24).toString('base64url')};
  const local={...a.store.data.tracks[0],id:randomUUID(),source:'local',title:'Personnel',location:'C:\\private\\personal.flac'};
  await a.store.update(s=>{s.tracks.push(local);s.settings.volume=.23;});
  await a.client.authenticate('register',credentials);created.push(a.client.state().account.id);assert.ok(a.client.lastSync);
  assert.equal(a.client.state().token,undefined);assert.equal(a.client.state().password,undefined);
  const protectedBytes=await readFile(join(a.store.directory,'account-session.dat'));assert.equal(protectedBytes.includes(Buffer.from(a.client.session.token)),false);
  for(const file of await readdir(a.store.directory))assert.equal((await readFile(join(a.store.directory,file))).includes(Buffer.from(credentials.password)),false);
  await b.client.authenticate('login',credentials);assert.ok(b.client.lastSync);assert.equal(b.store.data.tracks.find(x=>x.id===local.id).location,'');
  await b.store.update(s=>{s.playlists[0].name='Renommée ailleurs';s.favorites=[s.tracks[0].id];});await b.client.sync();await a.client.sync();
  assert.equal(a.store.data.playlists[0].name,'Renommée ailleurs');assert.equal(a.store.data.favorites.length,1);assert.equal(a.store.data.settings.volume,.23);assert.equal(a.store.data.tracks.find(x=>x.id===local.id).location,local.location);
  const remoteID=randomUUID();await b.store.update(s=>s.playlists.push({id:remoteID,name:'Ajout distant',trackIDs:[],createdAt:1,symbol:'music.note',detail:''}));await b.client.sync();
  duringSync=()=>a.store.update(s=>{s.playlists[0].name='Modification pendant la requête';});await a.client.sync();assert.equal(a.store.data.playlists[0].name,'Modification pendant la requête');assert.ok(a.store.data.playlists.some(p=>p.id===remoteID));
  await a.client.sync();await b.client.sync();assert.equal(b.store.data.playlists[0].name,'Modification pendant la requête');
  await b.store.update(s=>{s.favorites=[];s.playlists=s.playlists.filter(p=>p.id!==remoteID);});await b.client.sync();await a.client.sync();assert.equal(a.store.data.favorites.length,0);assert.equal(a.store.data.playlists.some(p=>p.id===remoteID),false);
  const unseenID=randomUUID();await b.store.update(s=>s.playlists.push({id:unseenID,name:'Réponse perdue',trackIDs:[],createdAt:2,symbol:'music.note',detail:''}));await b.client.sync();dropReply=true;await a.client.sync();assert.equal(a.store.data.playlists.some(p=>p.id===unseenID),false);await a.client.sync();assert.ok(a.store.data.playlists.some(p=>p.id===unseenID));
  const restarted=new AccountClient({store:a.store,secureStorage:a.secureStorage,server:serverURL,allowHTTP:true,fetchFunction});await restarted.load();assert.equal(restarted.state().signedIn,true);await restarted.sync();assert.ok(restarted.lastSync);
  const before=structuredClone(a.store.data);await restarted.logout();assert.deepEqual(a.store.data,before);const beforeCalls=calls;await restarted.sync();assert.equal(calls,beforeCalls);assert.equal(restarted.state().signedIn,false);
  await b.client.deleteAccount(credentials.password);assert.equal(b.client.state().signedIn,false);assert.ok(b.store.data.tracks.length);assert.equal((await db.query('SELECT * FROM soryn_cloud_libraries WHERE account_id=$1',[created[0]])).rows.length,0);
  await a.client.sync();assert.match(a.client.state().status,/expirée/);assert.deepEqual(a.store.data,before);
});
