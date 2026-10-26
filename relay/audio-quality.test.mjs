import test from 'node:test';
import assert from 'node:assert/strict';
import {preferredAAC} from './audio-quality.mjs';
import {YouTubeProvider} from './provider.mjs';
import {writeFile} from 'node:fs/promises';
const aac=(itag,bitrate)=>({itag,bitrate,has_audio:true,has_video:false,mime_type:'audio/mp4; codecs="mp4a.40.2"',content_length:2000000});
test('high quality selects an actually offered higher-rate AAC; standard preserves ordinary AAC',()=>{
  const formats=[aac(140,131042),aac(141,258000),aac(139,48000)];
  assert.deepEqual(preferredAAC(formats).map(f=>f.itag),[140,139]);
  assert.deepEqual(preferredAAC(formats,'high').map(f=>f.itag),[141,140,139]);
});
test('quality fallback never invents 256 kbit/s, transcodes, selects video, DRM or unsupported Opus',()=>{
  const formats=[aac(140,131042),{...aac(251,155000),mime_type:'audio/webm; codecs="opus"'},
    {...aac(999,999000),has_video:true},{...aac(998,999000),drm_families:['test']},
    {...aac(997,999000),content_length:0},{...aac(996,999000),content_length:30000000}];
  assert.deepEqual(preferredAAC(formats,'high').map(f=>f.itag),[140]);
  assert.equal(preferredAAC(formats,'high')[0].bitrate,131042);
  assert.equal(preferredAAC([aac(141,256000)])[0].itag,141,'Keep a title playable if its only compatible format exceeds the usual rate');
});
test('provider caches and deduplicates each quality independently',async()=>{
  const provider=new YouTubeProvider();const requests=[];
  provider.sabr.download=async(id,path,limit,quality)=>{
    requests.push(quality);await new Promise(resolve=>setTimeout(resolve,10));
    const fixture=Buffer.from('0000ftypM4A fixture for cache routing only');await writeFile(path,fixture);
    return {path,size:fixture.length,bitrate:quality==='high'?256000:131000,duration:48,client:'fixture'};
  };
  try{
    const standard=await provider.prepare('abcdefghijk');
    const [firstHigh,secondHigh]=await Promise.all([provider.prepare('abcdefghijk','high'),provider.prepare('abcdefghijk','high')]);
    assert.equal(standard.bitrate,131000);assert.equal(firstHigh.bitrate,256000);
    assert.equal(firstHigh.path,secondHigh.path);assert.notEqual(firstHigh.path,standard.path);
    assert.equal((await provider.prepare('abcdefghijk')).path,standard.path);
    assert.deepEqual(requests,['standard','high']);
  }finally{await provider.close();}
});
