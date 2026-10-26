// Origin attestation in an isolated DOM, with no account state. The service can
// reject this runtime; token generation alone is never counted as playable audio.
import vm from 'node:vm';

export async function createOriginMinter(yt, load = name => import(name), options = {}) {
  const {JSDOM, VirtualConsole} = await load('jsdom');
  const {BotGuardClient,getChallenge} = await load('bgutils-js/botguard');
  const {WebPoMinter} = await load('bgutils-js/webpo');
  const {getHeaders, buildURL, USER_AGENT, parseLooseJSON} = await load('bgutils-js/utils');
  let html='';
  if(!options.forceWaa && !options.skipPage){
    const response = await fetch('https://www.youtube.com/', {headers:{'User-Agent':USER_AGENT},signal:AbortSignal.timeout(8000)});
    if (!response.ok) throw Error(`Attestation page HTTP ${response.status}`);
    html=await response.text();
  }
  const configuration = html.match(/ytcfg\.set\((\{.+?\})\);/s)?.[1];
  const embedded = html.match(/window\.ytAtN\(\s*({[\s\S]*?})\s*\)/)?.[1];
  let challenge = embedded ? parseLooseJSON(embedded).R?.bgChallenge : undefined;
  if(!challenge && options.forceWaa){
    challenge=await getChallenge({requestKey:'O43z0dpjhgX20SCx4KAo',useYouTubeAPI:false,
      fetchFunction:(input,init={})=>fetch(input,{...init,signal:AbortSignal.timeout(8000)})});
  }
  if (!challenge && yt) {
    const result = await yt.getAttestationChallenge('ENGAGEMENT_TYPE_UNBOUND');
    const c = result.bg_challenge;
    if (c) challenge = {program:c.program,globalName:c.global_name,interpreterUrl:{privateDoNotAccessOrElseTrustedResourceUrlWrappedValue:c.interpreter_url?.private_do_not_access_or_else_trusted_resource_url_wrapped_value}};
  }
  if (!challenge?.program || !challenge?.globalName) throw Error('No public origin attestation program returned');
  const address = challenge.interpreterUrl?.privateDoNotAccessOrElseTrustedResourceUrlWrappedValue;
  const inline=challenge.interpreterJavascript?.privateDoNotAccessOrElseSafeScriptWrappedValue;
  let script=inline,url;
  if(!script){
    if(!address)throw Error('No attestation interpreter returned');
    url = new URL(address, 'https://www.youtube.com');
    if (url.protocol!=='https:' || !['www.google.com','www.gstatic.com','www.youtube.com'].includes(url.hostname)) throw Error('Unrecognized attestation interpreter host');
    const scriptResponse = await fetch(url,{signal:AbortSignal.timeout(8000)});
    if (!scriptResponse.ok) throw Error(`Attestation interpreter HTTP ${scriptResponse.status}`);
    script = await scriptResponse.text();
  }
  if (script.length>2_000_000) throw Error('Attestation interpreter exceeded diagnostic size limit');
  const dom = new JSDOM('<!doctype html><html><head><title>Blusic protocol diagnostic</title></head><body></body></html>',
    {url:'https://www.youtube.com/',referrer:'https://www.youtube.com/',runScripts:'outside-only',virtualConsole:new VirtualConsole()});
  dom.window.yt = {config_:configuration ? JSON.parse(configuration) : {INNERTUBE_CONTEXT:yt?.session.context || {}}};
  vm.runInContext(script,dom.getInternalVMContext(),{timeout:2500});
  if(options.diagnostic)console.log(JSON.stringify({phase:'attestation-runtime',globalName:challenge.globalName,interpreterHost:url?.hostname||'Google WAA inline',scriptBytes:script.length,inline:!!inline,installed:typeof dom.window[challenge.globalName]}));
  const client = await BotGuardClient.create({program:challenge.program,globalName:challenge.globalName,globalObject:dom.window});
  const output = [];
  const snapshot = await client.snapshot({webPoSignalOutput:output},8000);
  const integrity = await fetch(buildURL('GenerateIT',!options.forceWaa),{method:'POST',headers:getHeaders(),
    body:JSON.stringify(['O43z0dpjhgX20SCx4KAo',snapshot]),signal:AbortSignal.timeout(8000)});
  if(!integrity.ok) {dom.window.close();throw Error(`Origin attestation HTTP ${integrity.status}`);}
  const [integrityToken,estimatedTtlSecs,mintRefreshThreshold,websafeFallbackToken] = await integrity.json();
  if (!integrityToken) {dom.window.close();throw Error('Runtime integrity was not accepted');}
  // Cross-realm functions and typed arrays are valid JS values, but the library
  // uses instanceof checks against the host realm. Adapt the boundary only.
  const originalFactory = output[0];
  if(typeof originalFactory!=='function') throw Error('Origin minter factory unavailable');
  output[0] = async bytes => {
    const callback = await originalFactory(bytes);
    if(typeof callback!=='function') throw Error('Runtime integrity minter rejected');
    return async binding => new Uint8Array(await callback(binding));
  };
  const minter = await WebPoMinter.create({integrityToken,estimatedTtlSecs,mintRefreshThreshold,websafeFallbackToken},output);
  return {mint:id=>minter.mint(id),close:async()=>{await client.shutdown().catch(()=>{});dom.window.close();}};
}
