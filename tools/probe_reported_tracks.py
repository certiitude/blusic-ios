"""Diagnose reported catalogue tracks, checking each relay mode separately."""
import concurrent.futures
import json
import time
import sys
import urllib.request
import urllib.parse
from probe_direct_ios import probe


def rows(value):
    if isinstance(value, dict):
        if "musicResponsiveListItemRenderer" in value:
            yield value["musicResponsiveListItemRenderer"]
        for child in value.values():
            yield from rows(child)
    elif isinstance(value, list):
        for child in value:
            yield from rows(child)


def relay(video, local):
    began = time.monotonic()
    path = "https://yt.chocolatemoo53.com/api/v1/videos/" + video + ("?local=true" if local else "")
    try:
        request = urllib.request.Request(path, headers={"Accept": "application/json", "User-Agent": "Blusic/1.6 source diagnostics"})
        with urllib.request.urlopen(request, timeout=6) as response:
            payload = response.read(2_000_000)
            data = json.loads(payload)
        formats = [f for f in data.get("adaptiveFormats", []) if isinstance(f, dict) and f.get("url") and str(f.get("type", "")).startswith("audio/mp4")]
        result = {"local": local, "aac": len(formats)}
        if formats:
            formats.sort(key=lambda f: int(f.get("bitrate", 0)), reverse=True)
            url = urllib.parse.urljoin(path, formats[0]["url"])
            media = urllib.request.Request(url, headers={"Range": "bytes=0-4095"})
            with urllib.request.urlopen(media, timeout=6) as response:
                header = response.read(64)
                result.update(media_status=response.status, mime=response.headers.get_content_type(), header_hex=header[:16].hex(), mp4_ftyp=b"ftyp" in header)
        result["seconds"] = round(time.monotonic() - began, 3)
        return result
    except Exception as error:
        return {"local": local, "error": str(error), "seconds": round(time.monotonic() - began, 3)}


def diagnose(query):
    body = {"context": {"client": {"clientName": "WEB_REMIX", "clientVersion": "1.20261021.01.00", "hl": "fr", "gl": "FR"}},
            "query": query, "params": "EgWKAQIIAWoMEA4QChADEAQQCRAF"}
    request = urllib.request.Request("https://music.youtube.com/youtubei/v1/search?prettyPrint=false", data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Origin": "https://music.youtube.com", "User-Agent": "Blusic/1.6"})
    with urllib.request.urlopen(request, timeout=10) as response:
        payload = json.load(response)
    row = next(r for r in rows(payload) if r.get("playlistItemData", {}).get("videoId") and "MUSIC_VIDEO_TYPE_ATV" in json.dumps(r))
    video = row["playlistItemData"]["videoId"]
    title = row["flexColumns"][0]["musicResponsiveListItemFlexColumnRenderer"]["text"]["runs"][0]["text"]
    try:
        direct = probe(video)
    except Exception as error:
        direct = {"error": str(error)}
    return {"query": query, "title": title, "video": video, "direct": direct, "relay": [relay(video, True), relay(video, False)]}


if __name__ == "__main__":
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for result in pool.map(diagnose, sys.argv[1:] or ["Stéphanie Nafeesisboujee", "Ambre BLOU FEET", "Dieu ne ment jamais Damso", "Salé Niska"]):
            print(json.dumps(result, ensure_ascii=True))
