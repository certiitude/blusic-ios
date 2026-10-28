import test from 'node:test';
import assert from 'node:assert/strict';
import {parseSearch} from '../core/catalog.mjs';
test('catalog parser selects actual songs, excludes music videos and deduplicates',()=>{
  const row=type=>({musicResponsiveListItemRenderer:{playlistItemData:{videoId:'qMAzmGNeDxc'},endpoint:{musicVideoType:type},flexColumns:[{musicResponsiveListItemFlexColumnRenderer:{text:{runs:[{text:'FUTUR AMOUR'}]}}},{musicResponsiveListItemFlexColumnRenderer:{text:{runs:[{text:'Artist',navigationEndpoint:{browseEndpoint:{browseId:'UCartist'}}},{text:'3:20'}]}}}]}});
  const results=parseSearch({contents:[row('MUSIC_VIDEO_TYPE_ATV'),row('MUSIC_VIDEO_TYPE_ATV'),row('MUSIC_VIDEO_TYPE_OMV')]});
  assert.equal(results.length,1);assert.equal(results[0].title,'FUTUR AMOUR');assert.equal(results[0].artist,'Artist');assert.equal(results[0].duration,200);assert.equal(results[0].source,'invidious');
  assert.equal(parseSearch({contents:[row('MUSIC_VIDEO_TYPE_OMV')]}).length,0);
});
