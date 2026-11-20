// CI-only loopback media. No catalogue, credentials, proxy or user files.
import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';

const aac = readFileSync(new URL('../BlusicTests/aac-standard.m4a', import.meta.url));
const rate = 48000, frames = rate * 12;
const wav = Buffer.alloc(44 + frames * 4);
wav.write('RIFF', 0); wav.writeUInt32LE(wav.length - 8, 4); wav.write('WAVEfmt ', 8);
wav.writeUInt32LE(16, 16); wav.writeUInt16LE(1, 20); wav.writeUInt16LE(2, 22);
wav.writeUInt32LE(rate, 24); wav.writeUInt32LE(rate * 4, 28); wav.writeUInt16LE(4, 32); wav.writeUInt16LE(16, 34);
wav.write('data', 36); wav.writeUInt32LE(frames * 4, 40);
for (let i = 0; i < frames; i++) {
  const time = i / rate, phase = time % 0.5;
  const sample = phase < 0.12 ? Math.round(Math.sin(2 * Math.PI * 80 * time) * Math.exp(-phase * 30) * 12000) : 0;
  wav.writeInt16LE(sample, 44 + i * 4); wav.writeInt16LE(sample, 46 + i * 4);
}
createServer((request, response) => {
  const data = request.url === '/aac.m4a' ? aac : request.url === '/pulses.wav' ? wav : null;
  if (!data || !['GET', 'HEAD'].includes(request.method)) { response.writeHead(404).end(); return; }
  const match = request.headers.range?.match(/^bytes=(\d+)-(\d*)$/);
  const start = match ? Number(match[1]) : 0;
  const end = match && match[2] ? Math.min(Number(match[2]), data.length - 1) : data.length - 1;
  if (start > end || start >= data.length) { response.writeHead(416, { 'Content-Range': `bytes */${data.length}` }).end(); return; }
  const headers = { 'Content-Type': request.url.endsWith('.m4a') ? 'audio/mp4' : 'audio/wav', 'Accept-Ranges': 'bytes', 'Content-Length': end - start + 1 };
  if (match) headers['Content-Range'] = `bytes ${start}-${end}/${data.length}`;
  response.writeHead(match ? 206 : 200, headers);
  response.end(request.method === 'HEAD' ? undefined : data.subarray(start, end + 1));
}).listen(48766, '127.0.0.1', () => console.log('Reactive PCM media fixture on loopback port 48766.'));
