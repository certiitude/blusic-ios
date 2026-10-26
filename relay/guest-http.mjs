import {CookieJar} from 'tough-cookie';

/** A fresh anonymous HTTP session only. No browser cookie imports, Google
 * account credentials, or application/Render access tokens are accepted here.
 */
export class GuestHTTP {
  constructor(fetchFunction=fetch){this.jar=new CookieJar();this.fetchFunction=fetchFunction;}
  async fetch(input,init={}){
    const request=new Request(input,init);
    const url=new URL(request.url);
    if(url.protocol!=='https:')throw Error('Guest session requires HTTPS');
    const headers=new Headers(request.headers);
    headers.delete('cookie');headers.delete('authorization');
    const cookies=await this.jar.getCookieString(url.href);
    if(cookies)headers.set('cookie',cookies);
    const response=await this.fetchFunction(new Request(request,{headers}));
    for(const cookie of response.headers.getSetCookie?.()||[]){
      if(/^(?:SAPISID|APISID|SID|HSID|SSID|LOGIN_INFO|__Secure-\dPAPISID)=/i.test(cookie))continue;
      await this.jar.setCookie(cookie,response.url||url.href,{ignoreError:true});
    }
    return response;
  }
}
