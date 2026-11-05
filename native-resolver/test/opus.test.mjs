import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {demuxOpusWebM,remuxOpusToCAF,preferredOpus,opusPacketFrames} from '../opus-caf.mjs';
import {downloadOpusRanges} from '../direct-opus.mjs';
const fixture=await readFile(new URL('./fixtures/opus-vbr.webm',import.meta.url));
test('selects public original Opus 251, not lower quality, AAC or premium/DRM',()=>{
  const f={itag:251,has_audio:true,has_video:false,mime_type:'audio/webm; codecs="opus"',content_length:1000,bitrate:140000};
  assert.equal(preferredOpus([f,{...f,itag:249},{...f,itag:774},{...f,has_video:true},{...f,drm_families:['widevine']},{...f,content_length:30_000_000}]).length,1);
  assert.equal(preferredOpus([{...f,mime_type:'audio/mp4; codecs="mp4a.40.2"'}]).length,0);
});
test('real VBR fixture copies every compressed packet unchanged to CAF, preserving trim and duration',async()=>{
  const demux=demuxOpusWebM(fixture),result=remuxOpusToCAF(fixture);
  assert.equal(result.duration,4);assert.equal(result.channels,2);assert.equal(result.packets,201);
  assert.ok(new Set(demux.packets.map(p=>p.data.length)).size>2,'Fixture really uses VBR');
  assert.equal(result.bitrate,Math.round(demux.bytes*8/4));
  const caf=Buffer.from(result.data);assert.equal(caf.toString('ascii',0,4),'caff');
  const chunks=new Map();for(let i=8;i<caf.length;){const id=caf.toString('ascii',i,i+4),n=Number(caf.readBigUInt64BE(i+4));chunks.set(id,caf.subarray(i+12,i+12+n));i+=12+n;assert.ok(i<=caf.length);}
  assert.equal(chunks.get('desc').toString('ascii',8,12),'opus');
  assert.deepEqual(chunks.get('kuki'),Buffer.from(demux.head));
  assert.deepEqual(chunks.get('data').subarray(4),Buffer.concat(demux.packets.map(p=>Buffer.from(p.data))));
  assert.equal(Number(chunks.get('pakt').readBigUInt64BE(8)),192000);
  assert.deepEqual(caf,await readFile(new URL('../../BlusicTests/opus-vbr.caf',import.meta.url)));
});
test('rejects corrupt/truncated WebM instead of accepting a short or differently encoded file',()=>{
  for(const x of [Buffer.from('not opus'),fixture.subarray(0,200),fixture.subarray(0,fixture.length-1000)])assert.throws(()=>remuxOpusToCAF(x));
  const other=Buffer.from(fixture),at=other.indexOf('A_OPUS');assert.ok(at>0);other.write('A_AAC!',at);assert.throws(()=>remuxOpusToCAF(other));
});
test('Opus packet duration follows RFC6716, including variable packet frame counts',()=>{
  assert.equal(opusPacketFrames(Uint8Array.of(0xf8,0)),960);
  assert.equal(opusPacketFrames(Uint8Array.of(0xf9,0)),1920);
  assert.equal(opusPacketFrames(Uint8Array.of(0xfb,3)),2880);
  assert.throws(()=>opusPacketFrames(Uint8Array.of(0xfb,0)));
  assert.throws(()=>opusPacketFrames(Uint8Array.of(0xfb,63)));
});
test('finite Opus downloads verify every byte boundary and reject rate limits or ignored ranges',async()=>{
  const f={itag:251,has_audio:true,has_video:false,mime_type:'audio/webm; codecs="opus"',content_length:600000,bitrate:150000,url:'https://test.googlevideo.com/audio'};
  const bytes=Buffer.alloc(600000,7),ranges=[];
  const fetchFunction=async(url,init)=>{const [start,end]=new URL(url).searchParams.get('range').split('-').map(Number);ranges.push([start,end]);assert.equal(init.headers.Range,`bytes=${start}-${end}`);return new Response(bytes.subarray(start,end+1),{status:206,headers:{'Content-Range':`bytes ${start}-${end}/${bytes.length}`}});};
  assert.deepEqual(Buffer.from(await downloadOpusRanges(f,{fetchFunction})),bytes);assert.equal(ranges.length,3);
  await assert.rejects(()=>downloadOpusRanges(f,{fetchFunction:async()=>new Response('denied',{status:403})}),/403/);
  await assert.rejects(()=>downloadOpusRanges(f,{fetchFunction:async()=>new Response(bytes)}),/ignorée/);
  await assert.rejects(()=>downloadOpusRanges({...f,url:'http://test.googlevideo.com/audio'},{fetchFunction}));
  await assert.rejects(()=>downloadOpusRanges({...f,url:'https://other.example/audio'},{fetchFunction}));
});
test('unknown-size clusters remux without dropping later clusters',()=>{
  const data=Buffer.from(fixture),mark=Buffer.from([0x1f,0x43,0xb6,0x75]),start=data.indexOf(mark);assert.ok(start>0);
  let n=1,mask=128;while(!(data[start+4]&mask)){mask>>=1;n++;}
  data[start+4]=mask*2-1;for(let i=1;i<n;i++)data[start+4+i]=255;
  assert.deepEqual(remuxOpusToCAF(data).data,remuxOpusToCAF(fixture).data);
});
