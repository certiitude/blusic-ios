// WebM -> CAF packet-copy remuxer for Apple's native Opus decoder (iOS 17+).
// No decoder/encoder, bitrate conversion, account or server is involved.
const text=new TextDecoder(),ascii=s=>new TextEncoder().encode(s);
const fail=()=>{throw Error('WebM/Opus invalide ou non pris en charge');};
export function preferredOpus(formats){return (formats||[]).filter(f=>f.itag===251&&f.has_audio&&!f.has_video&&/^audio\/webm.*opus/i.test(f.mime_type||'')&&!f.drm_families?.length&&!f.drm_track_type&&Number.isSafeInteger(Number(f.content_length))&&Number(f.content_length)>0&&Number(f.content_length)<=25_000_000).sort((a,b)=>(Number(b.bitrate)||0)-(Number(a.bitrate)||0));}
function vint(data,offset,keep=false){
  if(offset>=data.length||!data[offset])fail();let length=1,mask=128;
  while(!(data[offset]&mask)){mask>>=1;length++;}
  if(length>(keep?4:8)||offset+length>data.length)fail();
  let n=BigInt(keep?data[offset]:data[offset]&(mask-1));
  for(let i=1;i<length;i++)n=(n<<8n)|BigInt(data[offset+i]);
  const unknown=!keep&&n===(1n<<BigInt(7*length))-1n;
  if(!unknown&&n>BigInt(Number.MAX_SAFE_INTEGER))fail();
  return {value:unknown?null:Number(n),length};
}
function elements(data,start,end,visit,depth=0){
  if(depth>8)fail();for(let pos=start;pos<end;){const id=vint(data,pos,true);pos+=id.length;const size=vint(data,pos);pos+=size.length;
    let stop=size.value===null?end:pos+size.value;
    if(size.value===null&&id.value===0x1f43b675){let at=pos;while(at<end){const child=vint(data,at,true);if([0x1f43b675,0x1c53bb6b,0x1654ae6b,0x1549a966,0x1254c367].includes(child.value))break;const s=vint(data,at+child.length);if(s.value===null)fail();at+=child.length+s.length+s.value;if(at>end)fail();}stop=at;}
    else if(size.value===null&&id.value!==0x18538067)fail();
    if(stop>end||stop<pos)fail();visit(id.value,pos,stop,depth);pos=stop;}
}
function uint(data,a,b){if(b-a>8||a===b)fail();let v=0n;for(let i=a;i<b;i++)v=v*256n+BigInt(data[i]);if(v>BigInt(Number.MAX_SAFE_INTEGER))fail();return Number(v);}
function signed(data,a,b){let n=BigInt(uint(data,a,b));if(data[a]&128)n-=1n<<BigInt((b-a)*8);return Number(n);}
export function opusPacketFrames(packet){
  if(!packet.length)fail();const c=packet[0]>>3;
  const ms=c<12?[10,20,40,60][c%4]:c<16?[10,20][c%2]:[2.5,5,10,20][c%4];
  const code=packet[0]&3,count=code===0?1:code<3?2:(packet.length>1?packet[1]&63:0);
  if(!count||ms*count>120)fail();return ms*count*48;
}
function packetsInBlock(data,start,end){
  const track=vint(data,start);if(track.value===null)fail();let p=start+track.length;
  if(p+3>=end)fail();const time=new DataView(data.buffer,data.byteOffset+p,2).getInt16(0);p+=2;
  const lace=(data[p++]>>1)&3;let sizes=[];
  if(!lace)sizes=[end-p];else{
    const count=data[p++]+1;if(count<2)fail();
    if(lace===2){if((end-p)%count)fail();sizes=Array(count).fill((end-p)/count);}
    else if(lace===1){for(let i=0;i<count-1;i++){let n=0,x;do{if(p>=end)fail();x=data[p++];n+=x;}while(x===255);sizes.push(n);}sizes.push(end-p-sizes.reduce((a,b)=>a+b,0));}
    else{const first=vint(data,p);p+=first.length;if(first.value===null)fail();sizes.push(first.value);
      for(let i=1;i<count-1;i++){const d=vint(data,p);p+=d.length;if(d.value===null)fail();sizes.push(sizes.at(-1)+d.value-(2**(7*d.length-1)-1));}sizes.push(end-p-sizes.reduce((a,b)=>a+b,0));}
  }
  const packets=sizes.map(n=>{if(n<=0||p+n>end||n>65535)fail();const value=data.subarray(p,p+n);p+=n;return value;});
  if(p!==end)fail();return {track:track.value,time,packets};
}
export function demuxOpusWebM(input){
  const data=input instanceof Uint8Array?input:new Uint8Array(input);if(data.length>25_000_000||data.length<32)fail();
  const first=vint(data,0,true);if(first.value!==0x1a45dfa3)fail();
  let track,head,scale=1_000_000,discard=0,segments=0;const blocks=[];
  elements(data,0,data.length,(id,a,b)=>{
    if(id!==0x18538067)return;segments++;
    elements(data,a,b,(id,a,b)=>{
      if(id===0x1549a966)elements(data,a,b,(i,a,b)=>{if(i===0x2ad7b1)scale=uint(data,a,b);});
      if(id===0x1654ae6b)elements(data,a,b,(i,a,b)=>{
        if(i!==0xae)return;let number,type,codec,privateData,encrypted=false;
        elements(data,a,b,(i,a,b)=>{if(i===0xd7)number=uint(data,a,b);if(i===0x83)type=uint(data,a,b);if(i===0x86)codec=text.decode(data.subarray(a,b));if(i===0x63a2)privateData=data.slice(a,b);if(i===0x6d80)encrypted=true;});
        if(type===2){if(track!==undefined||codec!=='A_OPUS'||encrypted)fail();track=number;head=privateData;}
      });
      if(id===0x1f43b675){let clusterTime=0;elements(data,a,b,(i,a,b)=>{
        if(i===0xe7)clusterTime=uint(data,a,b);
        if(i===0xa3)blocks.push({...packetsInBlock(data,a,b),clusterTime,padding:0});
        if(i===0xa0){let block,padding=0;elements(data,a,b,(i,a,b)=>{if(i===0xa1)block=packetsInBlock(data,a,b);if(i===0x75a2)padding=signed(data,a,b);});if(block)blocks.push({...block,clusterTime,padding});}
      });}
    });
  });
  if(segments!==1||track===undefined||!head||head.length!==19||text.decode(head.subarray(0,8))!=='OpusHead'||head[8]>15||![1,2].includes(head[9])||head[18]!==0)fail();
  const preSkip=new DataView(head.buffer,head.byteOffset).getUint16(10,true),packets=[];let frames=0,bytes=0,lastTime=-Infinity;
  for(const block of blocks){if(block.track!==track)continue;const time=(block.clusterTime+block.time)*scale/1e9;
    if(time<lastTime||Math.abs(time-frames/48000)>.15)fail();lastTime=time;
    if(discard)fail();if(block.padding<0)fail();discard=Math.round(block.padding*48000/1e9);
    for(const data of block.packets){const samples=opusPacketFrames(data);packets.push({data,frames:samples});frames+=samples;bytes+=data.length;}
  }
  if(!packets.length||packets.length>500000||frames<=preSkip+discard||discard>5760)fail();
  return {packets,head,channels:head[9],preSkip,discard,frames,validFrames:frames-preSkip-discard,bytes};
}
const concat=parts=>{const out=new Uint8Array(parts.reduce((n,p)=>n+p.length,0));let at=0;for(const p of parts){out.set(p,at);at+=p.length;}return out;};
function integers(values){const out=new Uint8Array(values.length*4),v=new DataView(out.buffer);values.forEach((n,i)=>v.setUint32(i*4,n));return out;}
function u64(n){const out=new Uint8Array(8);new DataView(out.buffer).setBigUint64(0,BigInt(n));return out;}
function variable(n){const bytes=[n&127];while(n=Math.floor(n/128))bytes.unshift((n&127)|128);return Uint8Array.from(bytes);}
function chunk(id,body){return concat([ascii(id),u64(body.length),body]);}
export function remuxOpusToCAF(webm){
  const d=demuxOpusWebM(webm),rate=new Uint8Array(8);new DataView(rate.buffer).setFloat64(0,48000);
  const desc=concat([rate,ascii('opus'),integers([0,0,0,d.channels,0])]);
  const table=concat([u64(d.packets.length),u64(d.validFrames),integers([d.preSkip,d.discard]),...d.packets.flatMap(p=>[variable(p.data.length),variable(p.frames)])]);
  const caf=concat([ascii('caff'),Uint8Array.of(0,1,0,0),chunk('desc',desc),chunk('kuki',d.head),chunk('pakt',table),chunk('data',concat([integers([0]),...d.packets.map(p=>p.data)]))]);
  const duration=d.validFrames/48000;
  return {data:caf,duration,bitrate:Math.round(d.bytes*8/duration),packets:d.packets.length,channels:d.channels};
}
