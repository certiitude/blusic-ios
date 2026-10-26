"""Measure a real YouTube Music thumbnail before/after known Google sizing.

Only fetches metadata/images, prints dimensions, never signed audio links.
Requires Pillow in the diagnostic Python environment.
"""
import io
import json
import re
import urllib.request
import urllib.parse
from PIL import Image


def dictionaries(key, value):
    if isinstance(value, dict):
        if isinstance(value.get(key), dict):
            yield value[key]
        for child in value.values():
            yield from dictionaries(key, child)
    elif isinstance(value, list):
        for child in value:
            yield from dictionaries(key, child)


def dimensions(address):
    request = urllib.request.Request(address, headers={"User-Agent": "Blusic artwork diagnostic"})
    with urllib.request.urlopen(request, timeout=15) as response:
        data = response.read(8_000_001)
    assert len(data) <= 8_000_000
    with Image.open(io.BytesIO(data)) as image:
        return {"width": image.width, "height": image.height, "bytes": len(data)}


def main():
    body = {"context": {"client": {"clientName": "WEB_REMIX", "clientVersion": "1.20261021.01.00", "hl": "fr", "gl": "FR"}},
            "query": "Niska", "params": "EgWKAQIIAWoMEA4QChADEAQQCRAF"}
    request = urllib.request.Request("https://music.youtube.com/youtubei/v1/search?prettyPrint=false", data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json", "Origin": "https://music.youtube.com"})
    with urllib.request.urlopen(request, timeout=15) as response:
        root = json.load(response)
    for row in dictionaries("musicResponsiveListItemRenderer", root):
        covers = [thumb for node in dictionaries("thumbnail", row) for thumb in node.get("thumbnails", [])]
        covers = sorted(covers, key=lambda item: item.get("width", 0), reverse=True)
        for cover in covers:
            address = cover.get("url", "")
            parsed = urllib.parse.urlsplit(address)
            if parsed.hostname and parsed.hostname.endswith(".googleusercontent.com") and not parsed.query and re.search(r"=[whs]\d+(?:-[A-Za-z0-9]+)*$", address):
                upgraded = re.sub(r"=[whs]\d+(?:-[A-Za-z0-9]+)*$", "=w1024-h1024-l90-rj", address)
                print(json.dumps({"host": parsed.hostname, "original": dimensions(address), "requested_1024": dimensions(upgraded)}))
                return
    raise RuntimeError("No safely resizable public Google artwork returned")


if __name__ == "__main__":
    main()
