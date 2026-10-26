"""Check the deployed relay without printing credentials or temporary media links."""
import hashlib
import json
from pathlib import Path
import sys
import time
import urllib.request
import urllib.error
import urllib.parse


def main():
    private = json.loads(Path(r"C:\Users\elome\AppData\Local\Temp\opencode\blusic-relay-deployment-private.json").read_text(encoding="utf-8"))
    base = "https://blusic-audio-relay.onrender.com"
    access=private["key"]
    if "--application" in sys.argv:
        access=json.loads(Path(r"C:\Users\elome\AppData\Local\Temp\opencode\blusic-ios-relay-capability-private.json").read_text(encoding="utf-8"))["capability"]
    video = sys.argv[1] if len(sys.argv) > 1 else "qMAzmGNeDxc"
    request = urllib.request.Request(base + "/v1/streams/" + video, headers={"Authorization": "Bearer " + access})
    began = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=90) as response:
            payload = json.load(response)
        url = urllib.parse.urljoin(base, payload["url"])
        assert urllib.parse.urlsplit(url).hostname == urllib.parse.urlsplit(base).hostname
        size = payload["size"]
        assert 0 < size <= 25_000_000
        request = urllib.request.Request(url, headers={"Range": "bytes=0-4095"})
        with urllib.request.urlopen(request, timeout=30) as response:
            first = response.read(4096)
            assert response.status == 206 and b"ftyp" in first[:64]
        request = urllib.request.Request(url)
        with urllib.request.urlopen(request, timeout=60) as response:
            audio = response.read(25_000_001)
            assert len(audio) == size
        print(json.dumps({"video": video, "complete": True, "bytes": size, "bitrate": payload["bitrate"], "seconds": round(time.monotonic() - began, 3), "sha256": hashlib.sha256(audio).hexdigest()}))
    except urllib.error.HTTPError as error:
        body = error.read(3000).decode("utf-8", errors="replace")
        print(json.dumps({"video": video, "complete": False, "http": error.code, "error": body, "seconds": round(time.monotonic() - began, 3)}))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
