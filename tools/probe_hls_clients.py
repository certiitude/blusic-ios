"""Probe public player protocols; report only metadata, never signed URLs.

Client compatibility profiles are compared against yt-dlp's maintained notes.
No account cookies, DRM processing, or challenge-solving code is used.
"""
import concurrent.futures
import json
import re
import sys
import time
import urllib.request
import urllib.parse
import urllib.error

SAFARI = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)"
PROFILES = {
    "web_safari": {"clientName": "WEB", "clientVersion": "2.20260708.00.00", "userAgent": SAFARI},
    "web_embedded": {"clientName": "WEB_EMBEDDED_PLAYER", "clientVersion": "2.20260708.00.00", "userAgent": SAFARI, "clientScreen": "EMBED"},
    "visionos": {"clientName": "VISIONOS", "clientVersion": "1.02", "deviceMake": "Apple", "deviceModel": "RealityDevice17,1", "osName": "visionOS", "osVersion": "26.5.23O471", "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"},
    "mweb_safari": {"clientName": "MWEB", "clientVersion": "2.20260708.05.00", "userAgent": "Mozilla/5.0 (iPad; CPU OS 16_7_10 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1,gzip(gfe)"},
    "ios_current": {"clientName": "IOS", "clientVersion": "21.26.4", "deviceMake": "Apple", "deviceModel": "iPhone16,2", "userAgent": "com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)", "osName": "iPhone", "osVersion": "18.3.2.22D82"},
}


def get(url, ua, maximum=1_000_000):
    request = urllib.request.Request(url, headers={"User-Agent": ua, "Accept": "*/*"})
    with urllib.request.urlopen(request, timeout=7) as response:
        return response.read(maximum), response.status, response.headers.get_content_type()


def inspect_hls(url, ua):
    raw, status, mime = get(url, ua)
    text = raw.decode("utf-8")
    if not text.startswith("#EXTM3U"):
        return {"status": status, "valid_playlist": False, "mime": mime}
    lines = [line.strip() for line in text.splitlines() if line.strip()]
    audio = []
    variants = []
    for index, line in enumerate(lines):
        if line.startswith("#EXT-X-MEDIA:") and "TYPE=AUDIO" in line:
            match = re.search(r'URI="([^"]+)"', line)
            if match:
                audio.append(urllib.parse.urljoin(url, match[1]))
        if line.startswith("#EXT-X-STREAM-INF:") and index+1 < len(lines):
            next_line = lines[index+1]
            if not next_line.startswith("#"):
                variant = urllib.parse.urljoin(url, next_line)
                variants.append(variant)
                if "mp4a" in line and not any(codec in line for codec in ["avc1", "hev1", "hvc1", "vp09", "av01"]):
                    audio.append(variant)
    result = {"status": status, "valid_playlist": True, "audio_renditions": len(audio), "variants": len(variants)}
    chosen = audio[0] if audio else None
    if chosen:
        payload, _, _ = get(chosen, ua)
        playlist = payload.decode("utf-8")
        if "#EXT-X-KEY" in playlist:
            result["protected_segments"] = True
            return result
        segments = [urllib.parse.urljoin(chosen, line.strip()) for line in playlist.splitlines() if line.strip() and not line.startswith("#")]
        result["segments"] = len(segments)
        result["segment_checks"] = []
        for index in sorted({0, len(segments)//2, len(segments)-1}):
            if index < 0 or not segments:
                continue
            data, status, mime = get(segments[index], ua, 512_000)
            result["segment_checks"].append({"index": index, "status": status, "bytes": len(data), "mime": mime})
    return result


def probe(name, video):
    began = time.monotonic()
    client = dict(PROFILES[name], hl="fr", gl="FR")
    context = {"client": client}
    if name == "web_embedded":
        context["thirdParty"] = {"embedUrl": "https://app.blusic.ios/"}
    body = {"videoId": video, "context": context, "contentCheckOk": True, "racyCheckOk": True,
            "playbackContext": {"contentPlaybackContext": {"vis": 0, "splay": False}}}
    request = urllib.request.Request("https://www.youtube.com/youtubei/v1/player?prettyPrint=false", data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "User-Agent": client["userAgent"], "Origin": "https://www.youtube.com"})
    result = {"client": name, "video": video}
    try:
        with urllib.request.urlopen(request, timeout=8) as response:
            data = json.load(response)
        status = data.get("playabilityStatus", {})
        streams = data.get("streamingData", {})
        formats = streams.get("adaptiveFormats", [])
        result.update(status=status.get("status"), reason=status.get("reason"), hls=bool(streams.get("hlsManifestUrl")),
                      sabr=bool(streams.get("serverAbrStreamingUrl")), direct_aac=sum(f.get("mimeType", "").startswith("audio/mp4") and bool(f.get("url")) for f in formats))
        if streams.get("hlsManifestUrl"):
            result["hls_checks"] = inspect_hls(streams["hlsManifestUrl"], client["userAgent"])
        if name == "visionos":
            aac = sorted([f for f in formats if f.get("mimeType", "").startswith("audio/mp4") and f.get("url")], key=lambda f:f.get("bitrate",0), reverse=True)
            if aac:
                size = int(aac[0].get("contentLength", "0"))
                result["finite_checks"] = []
                for offset in [0, max(4096, size//2)]:
                    request = urllib.request.Request(aac[0]["url"], headers={"Range": f"bytes={offset}-{offset+63}", "User-Agent": client["userAgent"]})
                    with urllib.request.urlopen(request, timeout=7) as response:
                        result["finite_checks"].append({"offset": offset, "status": response.status, "bytes": len(response.read(64))})
    except urllib.error.HTTPError as error:
        result["error"] = f"HTTP {error.code}"
    except Exception as error:
        result["error"] = re.sub(r"https?://[^\s]+", "[source]", str(error))[:250]
    result["seconds"] = round(time.monotonic()-began,3)
    return result


if __name__ == "__main__":
    video = sys.argv[1] if len(sys.argv)>1 else "qMAzmGNeDxc"
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        for result in pool.map(lambda name:probe(name,video), PROFILES):
            print(json.dumps(result, ensure_ascii=True))
