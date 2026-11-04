import test from 'node:test';
import assert from 'node:assert/strict';
import {parseSearch,parseEntities,catalogSearch,browse} from '../core/catalog.mjs';
test('catalog parser selects actual songs, excludes music videos and deduplicates',()=>{
  const row=type=>({musicResponsiveListItemRenderer:{playlistItemData:{videoId:'qMAzmGNeDxc'},endpoint:{musicVideoType:type},flexColumns:[{musicResponsiveListItemFlexColumnRenderer:{text:{runs:[{text:'FUTUR AMOUR'}]}}},{musicResponsiveListItemFlexColumnRenderer:{text:{runs:[{text:'Artist',navigationEndpoint:{browseEndpoint:{browseId:'UCartist'}}},{text:'3:20'}]}}}]}});
  const results=parseSearch({contents:[row('MUSIC_VIDEO_TYPE_ATV'),row('MUSIC_VIDEO_TYPE_ATV'),row('MUSIC_VIDEO_TYPE_OMV')]});
  assert.equal(results.length,1);assert.equal(results[0].title,'FUTUR AMOUR');assert.equal(results[0].artist,'Artist');assert.equal(results[0].duration,200);assert.equal(results[0].source,'invidious');
  assert.equal(parseSearch({contents:[row('MUSIC_VIDEO_TYPE_OMV')]}).length,0);
});
test('catalog album and artist cards retain real browse IDs and never treat songs as artists',()=>{
  const entity=(id,title)=>({musicResponsiveListItemRenderer:{navigationEndpoint:{browseEndpoint:{browseId:id}},flexColumns:[{musicResponsiveListItemFlexColumnRenderer:{text:{runs:[{text:title}]}}},{musicResponsiveListItemFlexColumnRenderer:{text:{runs:[{text:'2026 · Album'}]}}}]}});
  const root={contents:[entity('MPREb_test_album','Test album'),entity('UCartist_test','Test artiste'),entity('VLPLplaylist_test','Test playlist')]};
  assert.deepEqual(parseEntities(root,'albums').map(e=>e.title),['Test album']);
  assert.deepEqual(parseEntities(root,'artists').map(e=>e.title),['Test artiste']);
  assert.deepEqual(parseEntities(root,'playlists').map(e=>e.title),['Test playlist']);
});
test('album browse can accept music shelf rows without a redundant ATV label but still rejects music videos',()=>{
  const row={musicResponsiveListItemRenderer:{playlistItemData:{videoId:'RFzfXv9wzfo'},flexColumns:[{musicResponsiveListItemFlexColumnRenderer:{text:{runs:[{text:'Test titre'}]}}}]}};
  assert.equal(parseSearch(row).length,0);assert.equal(parseSearch(row,{allowUnlabelledSongs:true}).length,1);
  row.musicResponsiveListItemRenderer.endpoint={musicVideoType:'MUSIC_VIDEO_TYPE_OMV'};assert.equal(parseSearch(row,{allowUnlabelledSongs:true}).length,0);
  const explicitPlaylist=parseSearch(row,{allowPlaylistVideos:true});assert.equal(explicitPlaylist.length,1);assert.equal(explicitPlaylist[0].musicCatalog,'youtube-music-video');
  row.musicResponsiveListItemRenderer.fixedColumns=[{musicResponsiveListItemFixedColumnRenderer:{text:{runs:[{text:'3:42'}]}}}];
  assert.equal(parseSearch(row,{allowPlaylistVideos:true})[0].duration,222);
  row.musicResponsiveListItemRenderer.endpoint={musicVideoType:'MUSIC_VIDEO_TYPE_UGC'};assert.equal(parseSearch(row).length,0);assert.equal(parseSearch(row,{allowPlaylistVideos:true}).length,1);
});
test('catalog queries, pagination and browse identifiers are bounded before contacting YouTube',async()=>{
  await assert.rejects(()=>catalogSearch({query:'x'}));await assert.rejects(()=>catalogSearch({query:'valid',kind:'__proto__'}));
  await assert.rejects(()=>catalogSearch({query:'valid',continuation:'x'.repeat(20001)}));
  await assert.rejects(()=>browse({id:'https://localhost/private'}));
});
