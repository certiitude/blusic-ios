// Shared by the on-device bundle and Node relay. Never manufactures a format
// or increases a file's bitrate by re-encoding it.
export const STANDARD_AAC_CEILING=160000;
export const audioQuality=value=>value==='high'?'high':'standard';
export function preferredAAC(formats,quality='standard',maxBytes=25000000){
  const compatible=(formats||[]).filter(f=>f.has_audio&&!f.has_video&&
    /^audio\/mp4\s*;.*mp4a/i.test(f.mime_type||'')&&!f.drm_families?.length&&!f.drm_track_type&&
    Number.isSafeInteger(Number(f.content_length))&&Number(f.content_length)>0&&Number(f.content_length)<=maxBytes)
    .sort((a,b)=>(Number(b.bitrate)||0)-(Number(a.bitrate)||0));
  if(audioQuality(quality)==='high')return compatible;
  const standard=compatible.filter(f=>(Number(f.bitrate)||0)<=STANDARD_AAC_CEILING);
  return standard.length?standard:compatible;
}
