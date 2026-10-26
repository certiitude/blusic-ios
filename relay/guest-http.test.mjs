import test from 'node:test';
import assert from 'node:assert/strict';
import {GuestHTTP} from './guest-http.mjs';

test('guest transport keeps its own anonymous cookies without accepting account imports or leaking to media hosts',async()=>{
  let call=0;
  const guest=new GuestHTTP(async request=>{
    call++;
    if(call===1){
      assert.equal(request.headers.get('cookie'),null);
      assert.equal(request.headers.get('authorization'),null);
      const headers=new Headers();
      headers.append('Set-Cookie','YSC=anonymous-fixture; Path=/; Secure; HttpOnly');
      headers.append('Set-Cookie','SAPISID=must-not-be-retained; Path=/; Secure');
      return new Response('public page',{status:200,headers});
    }
    if(call===2){assert.equal(request.headers.get('cookie'),'YSC=anonymous-fixture');}
    if(call===3){assert.equal(request.headers.get('cookie'),null,'A YouTube guest cookie must not be sent to a googlevideo host');}
    return new Response('ok');
  });
  await guest.fetch('https://www.youtube.com/',{headers:{Cookie:'LOGIN_INFO=must-be-ignored',Authorization:'must-be-ignored'}});
  await guest.fetch('https://www.youtube.com/youtubei/v1/player');
  await guest.fetch('https://rr1.googlevideo.com/media');
  assert.equal(call,3);
});
