"""Validate the public iOS player request used successfully by youtubei.js.

No login, cookies, PO tokens, or encrypted formats. Reads at most 4096 media bytes.
"""
import json
import time
import urllib.request


def probe(video="-WXpT4Ej2No"):
    began = time.monotonic()
    body = {"videoId": video, "context": {"client": {
        "clientName": "iOS", "clientVersion": "20.11.6", "deviceMake": "Apple", "deviceModel": "iPhone10,4",
        "osName": "iOS", "osVersion": "16.7.7.20H330", "hl": "fr", "gl": "FR", "platform": "MOBILE"
    }}, "contentCheckOk": True, "racyCheckOk": True}
    request = urllib.request.Request("https://www.youtube.com/youtubei/v1/player?prettyPrint=false", data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "User-Agent": "Blusic/1.6 (iOS audio source)", "Origin": "https://www.youtube.com"})
    with urllib.request.urlopen(request, timeout=8) as response:
        data = json.load(response)
    formats = [f for f in data.get("streamingData", {}).get("adaptiveFormats", []) if f.get("url") and f.get("mimeType", "").startswith("audio/mp4")]
    formats.sort(key=lambda f: f.get("bitrate", 0), reverse=True)
    result = {"id": video, "status": data.get("playabilityStatus", {}).get("status"), "aac": [{"itag": f.get("itag"), "bitrate": f.get("bitrate")} for f in formats]}
    if formats:
        request = urllib.request.Request(formats[0]["url"], headers={"Range": "bytes=0-4095"})
        with urllib.request.urlopen(request, timeout=8) as response:
            chunk = response.read(4096)
            result.update(media_status=response.status, mp4_ftyp=b"ftyp" in chunk[:64], bytes=len(chunk))
    result["seconds"] = round(time.monotonic() - began, 3)
    return result


if __name__ == "__main__":
    print(json.dumps(probe()))
