"""Reproducible, original Blusic artwork and instrumental demo audio.

Run from any directory: python tools/generate_assets.py
Requires Pillow and NumPy. No downloaded media or external credentials.
"""
from pathlib import Path
import json
import math
import wave

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "Blusic" / "Assets.xcassets"
AUDIO = ROOT / "Blusic" / "Audio"
SIZE = 768


def catalog(path, images):
    path.mkdir(parents=True, exist_ok=True)
    (path / "Contents.json").write_text(json.dumps({"images": images, "info": {"author": "xcode", "version": 1}}, indent=2), encoding="utf-8")


def cubic(start, c1, c2, end, n=50):
    result = []
    for t in np.linspace(0, 1, n):
        q = (1 - t) ** 3 * np.array(start) + 3 * (1 - t) ** 2 * t * np.array(c1) + 3 * (1 - t) * t ** 2 * np.array(c2) + t ** 3 * np.array(end)
        result.append(tuple(q))
    return result


def mark(draw, origin, scale, fill="white", holes="black"):
    def points(segments):
        out = []
        for a, b, c, d in segments:
            out += [(origin[0] + x * scale, origin[1] + y * scale) for x, y in cubic(a, b, c, d)]
        return out
    outer = [((.30, .08), (.54, -.01), (.88, .15), (.91, .36)),
             ((.91, .36), (.99, .53), (.83, .90), (.65, .92)),
             ((.65, .92), (.47, 1.01), (.09, .88), (.08, .69)),
             ((.08, .69), (.01, .56), (.14, .17), (.30, .08))]
    eye1 = [((.52, .29), (.59, .20), (.61, .44), (.64, .60)),
            ((.64, .60), (.65, .70), (.55, .71), (.54, .63)),
            ((.54, .63), (.51, .56), (.51, .38), (.52, .29))]
    eye2 = [((.72, .29), (.78, .24), (.82, .36), (.82, .45)),
            ((.82, .45), (.85, .53), (.78, .56), (.76, .51)),
            ((.76, .51), (.73, .46), (.72, .35), (.72, .29))]
    draw.polygon(points(outer), fill=fill)
    draw.polygon(points(eye1), fill=holes)
    draw.polygon(points(eye2), fill=holes)


def font(size, bold=False):
    candidates = [Path("C:/Windows/Fonts") / ("segoeuib.ttf" if bold else "segoeui.ttf"),
                  Path("/System/Library/Fonts/Helvetica.ttc"),
                  Path("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf")]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size)
    return ImageFont.load_default(size=size)


def cover(name, index, dark, glow, title):
    y, x = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32) / SIZE
    radial = np.exp(-(((x - .58) / .48) ** 2 + ((y - .38) / .52) ** 2) * 2)
    noise = np.random.default_rng(72 + index).normal(0, 1.6, (SIZE, SIZE))
    arr = np.zeros((SIZE, SIZE, 3))
    for c in range(3):
        arr[:, :, c] = dark[c] + radial * (glow[c] - dark[c]) + noise
    image = Image.fromarray(np.uint8(np.clip(arr, 0, 255)))
    light = Image.new("RGBA", image.size)
    d = ImageDraw.Draw(light)
    if index == 0:
        # A softly illuminated vinyl-like orbital sculpture.
        for r in range(260, 80, -3):
            a = int(20 + 70 * (1 - (r - 80) / 180))
            d.ellipse((400-r, 330-r*.78, 400+r, 330+r*.78), outline=(105, 190, 255, a), width=2)
        d.ellipse((170, 125, 635, 590), outline=(173, 220, 255, 210), width=3)
        d.ellipse((175, 130, 630, 585), outline=(80, 145, 240, 140), width=10)
        d.ellipse((374, 308, 426, 360), fill=(10, 29, 53, 255), outline=(140, 202, 255, 160), width=2)
    elif index == 1:
        for i in range(90):
            xx = (i * 97) % SIZE
            yy = (i * 149) % SIZE
            d.line((xx, yy, xx-55, yy+145), fill=(190, 248, 215, 20+i%40), width=1+i%3)
        for i in range(10):
            d.ellipse((120+i*9, 260+i*6, 660-i*9, 420-i*6), outline=(185, 248, 218, 90-i*6), width=2)
    elif index == 2:
        d.ellipse((200, 150, 610, 560), fill=(228, 156, 135, 255))
        d.ellipse((205, 158, 595, 550), fill=(32, 26, 61, 255))
        d.ellipse((170, 310, 665, 390), outline=(250, 199, 170, 220), width=8)
        d.ellipse((220, 172, 600, 550), outline=(191, 132, 189, 110), width=2)
    else:
        for i in range(13):
            xx = -200+i*115
            d.line((xx, 0, xx+460, 650), fill=(255, 164, 114, 90), width=4)
        for i in range(10):
            d.line((0, 280+i*36, SIZE, 280+i*36), fill=(236, 117, 86, 45), width=1)
        d.rounded_rectangle((255, 190, 535, 455), radius=135, outline=(255, 195, 155, 230), width=9)
    bloom = light.filter(ImageFilter.GaussianBlur(13))
    image = Image.alpha_composite(image.convert("RGBA"), bloom)
    image = Image.alpha_composite(image, light)
    d = ImageDraw.Draw(image)
    d.text((42, 42), "B L U S I C   S T U D I O", font=font(15, True), fill=(242, 247, 255, 200))
    d.text((42, 620), title, font=font(53, True), fill=(242, 247, 255, 240))
    d.text((45, 700), f"PREMIÈRES ONDES     /     0{index+1}", font=font(13), fill=(220, 234, 249, 150))
    path = ASSETS / f"{name}.imageset"
    catalog(path, [{"filename": f"{name}.png", "idiom": "universal"}])
    image.convert("RGB").save(path / f"{name}.png", optimize=True)


def compose(filename, seed, root, bpm, rhythm):
    sr, duration = 44100, 48
    total = sr * duration
    audio = np.zeros((total, 2), dtype=np.float64)
    rng = np.random.default_rng(seed)
    beat = 60 / bpm

    def note(midi, start, length, gain=.12, pan=0, soft=True):
        count = min(int(length * sr), total - int(start * sr))
        if count <= 0:
            return
        t = np.arange(count) / sr
        freq = 440 * 2 ** ((midi - 69) / 12)
        wave_ = np.sin(2*np.pi*freq*t) + .18*np.sin(2*np.pi*freq*2.003*t) + .07*np.sin(2*np.pi*freq*3*t)
        attack = .12 if soft else .012
        env = np.minimum(t / attack, 1) * np.minimum((length-t) / .7, 1)
        env = np.maximum(0, env) * np.exp(-t / (length * (.65 if soft else .22)))
        signal = wave_ * env * gain
        at = int(start*sr)
        audio[at:at+count, 0] += signal * math.sqrt((1-pan)/2)
        audio[at:at+count, 1] += signal * math.sqrt((1+pan)/2)

    chords = [(0, 3, 7, 10), (-5, -2, 2, 5), (-2, 2, 5, 9), (-7, -3, 0, 4)]
    bar = beat * 4
    for bar_index, start in enumerate(np.arange(0, duration-1, bar)):
        chord = chords[bar_index % 4]
        for j, offset in enumerate(chord):
            note(root+offset, start+j*.024, bar*1.22, .075, (j-1.5)*.35)
        note(root+chord[0]-12, start, bar*.9, .14, 0)
        for step in range(8):
            midi = root + 12 + chord[(step + bar_index) % 4]
            note(midi, start+step*beat/2, beat*1.6, .05 if seed != 2 else .07, rng.uniform(-.7, .7), False)
    if rhythm:
        for k, start in enumerate(np.arange(0, duration-.5, beat)):
            at = int(start*sr)
            n = min(int(.32*sr), total-at)
            t = np.arange(n)/sr
            kick = np.sin(2*np.pi*(45*t+4*(1-np.exp(-t*22)))) * np.exp(-t*16) * .21
            if k % 4 in [0, 2]:
                audio[at:at+n] += kick[:, None]
            if k % 4 in [1, 3]:
                snare = rng.normal(0, .055, n) * np.exp(-t*24)
                audio[at:at+n] += snare[:, None]
            h_at = min(total-1, int((start+beat/2)*sr))
            hn = min(int(.07*sr), total-h_at)
            noise = rng.normal(0, 1, hn)
            hat = np.diff(noise, prepend=0) * np.exp(-np.arange(hn)/sr*80)*.018
            audio[h_at:h_at+hn, 1] += hat
    # Short stereo echoes and gentle saturation, then a seamless fade in/out.
    delay = int(.31*sr)
    audio[delay:, 1] += audio[:-delay, 0]*.12
    audio[delay*2:, 0] += audio[:-delay*2, 1]*.08
    audio = np.tanh(audio*.9)
    fade = np.minimum(np.arange(total)/sr/1.5, 1) * np.minimum((total-np.arange(total))/sr/3, 1)
    audio *= fade[:, None]
    audio *= .85/max(.001, np.abs(audio).max())
    pcm = np.int16(np.clip(audio, -1, 1)*32767)
    with wave.open(str(AUDIO/filename), "wb") as out:
        out.setnchannels(2); out.setsampwidth(2); out.setframerate(sr); out.writeframes(pcm.astype("<i2").tobytes())


def main():
    ASSETS.mkdir(parents=True, exist_ok=True)
    AUDIO.mkdir(parents=True, exist_ok=True)
    (ASSETS/"Contents.json").write_text('{"info":{"author":"xcode","version":1}}', encoding="utf-8")
    icon_path = ASSETS / "AppIcon.appiconset"
    catalog(icon_path, [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}])
    icon = Image.new("RGB", (2048, 2048), "#050609")
    mark(ImageDraw.Draw(icon), (300, 300), 1448, fill="white", holes="#050609")
    icon.resize((1024, 1024), Image.Resampling.LANCZOS).save(icon_path / "AppIcon.png")
    launch = ASSETS/"LaunchBackground.colorset"
    launch.mkdir(exist_ok=True)
    (launch/"Contents.json").write_text(json.dumps({"colors": [{"idiom":"universal", "color":{"color-space":"srgb","components":{"red":"0.027","green":"0.031","blue":"0.043","alpha":"1.000"}}}], "info":{"author":"xcode","version":1}}), encoding="utf-8")
    cover("cover-night", 0, (4, 13, 28), (32, 103, 160), "Bleu nuit")
    cover("cover-rain", 1, (8, 26, 29), (52, 119, 98), "Après la pluie")
    cover("cover-orbit", 2, (22, 14, 38), (107, 66, 112), "Orbite")
    cover("cover-metro", 3, (30, 11, 17), (137, 57, 41), "Dernier métro")
    for args in [("bleu-nuit.wav", 1, 57, 80, True), ("apres-la-pluie.wav", 2, 60, 72, False),
                 ("orbite.wav", 3, 54, 100, True), ("dernier-metro.wav", 4, 55, 88, True)]:
        compose(*args)
        print(f"Audio original généré : {args[0]}")
    print("Icône 1024px, 4 pochettes 768px, 4 WAV stéréo 44,1kHz / 16bit / 48s.")


if __name__ == "__main__":
    main()
