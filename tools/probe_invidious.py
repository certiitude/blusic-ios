"""Probe search, audio metadata and a short HTTP byte range; never downloads a song.

python tools/probe_invidious.py --instance https://yt.chocolatemoo53.com
"""
import argparse
import json
import urllib.error
import urllib.parse
import urllib.request


def request(url, *, byte_range=False):
    headers = {"User-Agent": "Blusic/1.1 (Invidious compatibility check)"}
    if byte_range:
        headers["Range"] = "bytes=0-8191"
        headers["Accept"] = "audio/mp4,audio/*;q=0.9,*/*;q=0.5"
    return urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=20)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--instance", default="https://yt.chocolatemoo53.com")
    parser.add_argument("--query", default="Niska Salé")
    args = parser.parse_args()
    base = args.instance.rstrip("/")
    url = base + "/api/v1/search?" + urllib.parse.urlencode({"q": args.query, "type": "video"})
    with request(url) as response:
        found = json.load(response)
    videos = [item for item in found if item.get("type") == "video" and item.get("videoId")]
    if not videos:
        raise RuntimeError("Aucun résultat vidéo.")
    video = videos[0]
    print(json.dumps({"instance": base, "title": video["title"], "video_id": video["videoId"]}, ensure_ascii=True))
    outcomes = []
    for local in (False, True):
        with request(base + "/api/v1/videos/" + video["videoId"] + ("?local=true" if local else "")) as response:
            metadata = json.load(response)
        formats = sorted([f for f in metadata.get("adaptiveFormats", []) if "audio/mp4" in f.get("type", "") and "mp4a" in f.get("type", "")],
                         key=lambda f: int(f.get("bitrate", 0)), reverse=True)
        if not formats:
            print("Aucun flux AAC/M4A compatible avec le moteur iOS.")
            continue
        stream = formats[0]
        url = urllib.parse.urljoin(base + "/", stream["url"])
        print(json.dumps({"mode": "local" if local else "direct", "host": urllib.parse.urlparse(url).hostname,
                          "type": stream.get("type"), "bitrate": stream.get("bitrate"), "duration": metadata.get("lengthSeconds")}, ensure_ascii=True))
        try:
            with request(url, byte_range=True) as response:
                data = response.read(8192)
                outcome = {"mode": "local" if local else "direct", "status": response.status, "type": response.headers.get("Content-Type"),
                           "bytes_read": len(data), "mp4_ftyp": b"ftyp" in data[:64]}
                outcomes.append(outcome)
                print(json.dumps(outcome, ensure_ascii=True))
        except (OSError, urllib.error.URLError) as error:
            outcome = {"mode": "local" if local else "direct", "error": str(error)}
            outcomes.append(outcome)
            print(json.dumps(outcome, ensure_ascii=True))
    if not any(outcome.get("mp4_ftyp") for outcome in outcomes):
        raise RuntimeError("Métadonnées reçues, mais aucun accès aux octets AAC/M4A n’a été validé.")
    print("Accès HTTP aux octets audio validé. Ce contrôle ne constitue pas un test d’écoute iPhone.")


if __name__ == "__main__":
    main()
