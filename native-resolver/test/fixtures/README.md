`opus-vbr.webm` is a four-second excerpt of this project's original instrumental
`Blusic/Audio/bleu-nuit.wav`, encoded **for testing only** with FFmpeg/libopus at
160k VBR. It is not a downloaded commercial track or a claim about YouTube bitrate.

`BlusicTests/opus-vbr.caf` is produced from this fixture by `remuxOpusToCAF`.
The test checks every Opus packet is byte-identical. No encoder is included in the
application: production media is only remuxed, never re-encoded.
