import test from 'node:test';
import assert from 'node:assert/strict';
import {selectTracks, recentTracks} from '../ui/library-view.mjs';

const tracks = [
  {id:'1',title:'Orbite 10',artist:'Zoé',album:'Premières ondes',addedAt:2,duration:48},
  {id:'2',title:'Après la pluie',artist:'Soryn Studio',album:'Premières ondes',addedAt:3,duration:20},
  {id:'3',title:'Orbite 2',artist:'Ariane',album:'Ailleurs',addedAt:1,duration:30},
];
test('library search ignores accents and case and matches all query terms',()=>{
  assert.deepEqual(selectTracks(tracks,{query:'APRES soryn'}).map(t=>t.id),['2']);
  assert.deepEqual(selectTracks(tracks,{query:'premieres ondes'}).map(t=>t.id),['1','2']);
  assert.equal(selectTracks(tracks,{query:'nonexistent'}).length,0);
});
test('view sort is numeric, stable and does not mutate the saved selection',()=>{
  assert.deepEqual(selectTracks(tracks,{sort:'title'}).map(t=>t.id),['2','3','1']);
  assert.deepEqual(selectTracks(tracks,{sort:'artist'}).map(t=>t.id),['3','2','1']);
  assert.deepEqual(selectTracks(tracks,{sort:'recent'}).map(t=>t.id),['2','1','3']);
  assert.deepEqual(selectTracks(tracks,{sort:'duration'}).map(t=>t.id),['2','3','1']);
  assert.deepEqual(tracks.map(t=>t.id),['1','2','3']);
});
test('recently played derives only from actual history, omits missing titles and duplicates',()=>{
  const library={tracks,history:[{trackID:'2'},{trackID:'1'},{trackID:'missing'},{trackID:'2'}]};
  assert.deepEqual(recentTracks(library).map(t=>t.id),['2','1']);
  assert.deepEqual(recentTracks(library,1).map(t=>t.id),['2']);
  assert.deepEqual(recentTracks({...library,history:[]}),[]);
});
