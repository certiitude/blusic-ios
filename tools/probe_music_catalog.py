"""Inspect the public YouTube Music songs-only search response (metadata only)."""
import argparse
import json
import re
import urllib.request


def walk(value, key):
    if isinstance(value, dict):
        if key in value:
            yield value[key]
        for child in value.values():
            yield from walk(child, key)
    elif isinstance(value, list):
        for child in value:
            yield from walk(child, key)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--query", default="Niska Salé")
    parser.add_argument("--artist-id")
    args = parser.parse_args()
    version = "1.20261021.01.00"
    try:
        with urllib.request.urlopen("https://music.youtube.com/", timeout=10) as response:
            html = response.read(3_000_000).decode("utf-8", errors="replace")
        match = re.search(r'"INNERTUBE_CLIENT_VERSION"\s*:\s*"([^"]+)"', html)
        if match:
            version = match.group(1)
    except OSError:
        pass
    body = {"context": {"client": {"clientName": "WEB_REMIX", "clientVersion": version, "hl": "fr", "gl": "FR"}},
            "query": args.query, "params": "EgWKAQIIAWoMEA4QChADEAQQCRAF"}
    endpoint = "search"
    if args.artist_id:
        endpoint = "browse"
        body.pop("query"); body.pop("params"); body["browseId"] = args.artist_id
    request = urllib.request.Request("https://music.youtube.com/youtubei/v1/" + endpoint + "?prettyPrint=false",
        data=json.dumps(body).encode(), headers={"Content-Type": "application/json", "Origin": "https://music.youtube.com",
            "Referer": "https://music.youtube.com/", "X-YouTube-Client-Name": "67", "X-YouTube-Client-Version": version,
            "User-Agent": "Blusic/1.2 (YouTube Music catalog client)"})
    with urllib.request.urlopen(request, timeout=20) as response:
        result = json.load(response)
    rows = list(walk(result, "musicResponsiveListItemRenderer"))
    print("Client version:", version, "song rows:", len(rows))
    if args.artist_id:
        print("Artist header keys:", list(result.get("header", {}).keys()))
    for row in rows[:5]:
        columns = [col.get("musicResponsiveListItemFlexColumnRenderer", {}).get("text", {}).get("runs", []) for col in row.get("flexColumns", [])]
        print(json.dumps({"columns": columns, "playlistItemData": row.get("playlistItemData"),
            "video_types": list(walk(row, "musicVideoType")),
            "play_endpoints": list(walk(row.get("overlay", {}), "watchEndpoint"))[:1]}, ensure_ascii=True))
    if not rows:
        raise RuntimeError("Aucun résultat de chanson YouTube Music.")


if __name__ == "__main__":
    main()
