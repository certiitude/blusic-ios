import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, writeFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {seed, sharedSnapshot, mergeLibraries, mergeSet, clone, validateLibrary, LibraryStore} from '../core/library.mjs';

test('Swift-compatible snapshot, dates and stable original IDs', () => {
  const s = validateLibrary(seed()); assert.equal(s.tracks.length,4); assert.equal(s.tracks[0].duration,48);
  assert.ok(Math.abs((s.tracks[0].addedAt + 978307200) * 1000 - Date.now()) < 1000);
  assert.deepEqual(s.tracks.map(t=>t.id),seed().tracks.map(t=>t.id));
});
test('atomic persistence, backup and restart without seeding over existing data', async t => {
  const directory = await mkdtemp(join(tmpdir(),'soryn-library-test-')); t.after(()=>rm(directory,{recursive:true,force:true}));
  const a = new LibraryStore(directory); await a.load();
  await a.update(s=>{s.favorites=[s.tracks[0].id];s.playlists[0].name='Écoutez le moment.';});
  const b = new LibraryStore(directory); await b.load();assert.equal(b.data.playlists[0].name,'Écoutez le moment.');assert.equal(b.data.favorites.length,1);
  assert.equal(JSON.parse(await readFile(join(directory,'library.json.bak'),'utf8')).favorites.length,0);
  await writeFile(join(directory,'library.json'),'BROKEN');
  await assert.rejects(()=>new LibraryStore(directory).load(),/conservé/);
  assert.equal(await readFile(join(directory,'library.json'),'utf8'),'BROKEN');
});
test('private audio paths and relay settings never cross the sync boundary', () => {
  const s=seed();s.tracks[0].source='local';s.tracks[0].location='private.wav';s.tracks[0].artworkURL='file:///private/cover.png';s.settings.relayKey='secret';
  const safe=sharedSnapshot(s);assert.equal(safe.tracks[0].source,'unresolved');assert.equal(safe.tracks[0].location,'');assert.equal(safe.tracks[0].artworkURL,undefined);assert.deepEqual(safe.settings,{});assert.deepEqual(safe.queue,[]);
});
test('three-way favorite removals and independent additions are retained', () => {
  assert.deepEqual(new Set(mergeSet(['a'],['a','b'],['c'])),new Set(['b','c']));
  const base=seed();base.favorites=[base.tracks[0].id];const local=clone(base),remote=clone(base);
  local.favorites.push(base.tracks[1].id);remote.favorites=[];
  assert.deepEqual(mergeLibraries(base,local,remote).favorites,[base.tracks[1].id]);
});
test('playlist rename, membership deletion and concurrent additions merge', () => {
  const base=seed(),local=clone(base),remote=clone(base);
  base.playlists[0].trackIDs=base.tracks.slice(0,2).map(t=>t.id);local.playlists[0].trackIDs=[base.tracks[0].id,base.tracks[2].id];remote.playlists[0].trackIDs=[base.tracks[0].id,base.tracks[1].id,base.tracks[3].id];remote.playlists[0].name='Sur iPhone';
  const result=mergeLibraries(base,local,remote);assert.equal(result.playlists[0].name,'Sur iPhone');assert.deepEqual(new Set(result.playlists[0].trackIDs),new Set([base.tracks[0].id,base.tracks[2].id,base.tracks[3].id]));
});
test('playlist deletion propagates, edited conflict is preserved', () => {
  const base=seed(),local=clone(base),remote=clone(base);remote.playlists=[];
  assert.equal(mergeLibraries(base,local,remote).playlists.length,0);
  local.playlists[0].name='Edited during disconnect';assert.equal(mergeLibraries(base,local,remote).playlists.length,1);
});
test('independently added identical songs deduplicate with every reference remapped', () => {
  const local=seed(),remote=seed(),old=remote.tracks[0].id,newID=randomUUID().toUpperCase();remote.tracks[0].id=newID;
  remote.favorites=[newID];remote.playlists[0].id=randomUUID().toUpperCase();remote.playlists[0].trackIDs=[newID];
  remote.history=[{id:randomUUID(),trackID:newID,date:1,seconds:15}];
  const result=mergeLibraries(null,local,remote);assert.equal(result.tracks.length,4);assert.deepEqual(result.favorites,[old]);assert.equal(result.playlists[1].trackIDs[0],old);assert.equal(result.history[0].trackID,old);
});
test('listening sessions merge by maximum duration, never double counted',()=>{
  const local=seed(),remote=clone(local),id=randomUUID();local.history=[{id,trackID:local.tracks[0].id,date:1,seconds:30}];remote.history=[{...local.history[0],seconds:45}];
  const result=mergeLibraries(null,local,remote);assert.equal(result.history.length,1);assert.equal(result.history[0].seconds,45);
});
test('malformed snapshots and unsupported future versions are rejected',()=>{
  const s=seed();s.version=2;assert.throws(()=>validateLibrary(s));s.version=1;s.tracks.push(s.tracks[0]);assert.throws(()=>validateLibrary(s));
  s.tracks.pop();s.playlists[0].trackIDs=[{}];assert.throws(()=>validateLibrary(s));
});
