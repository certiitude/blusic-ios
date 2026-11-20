import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

test('progressive PCM fixture serves real finite media, HEAD and byte ranges', async () => {
  const child = spawn(process.execPath, [fileURLToPath(new URL('./reactive_audio_fixture.mjs', import.meta.url))], { stdio: ['ignore', 'pipe', 'pipe'] });
  let error = '';
  child.stderr.on('data', chunk => { error += chunk; });
  try {
    await new Promise((resolve, reject) => {
      child.stdout.once('data', resolve);
      child.once('error', reject);
      child.once('exit', code => reject(new Error(`Fixture exited ${code}: ${error}`)));
    });
    const base = 'http://127.0.0.1:48766';
    const head = await fetch(base + '/aac.m4a', { method: 'HEAD' });
    assert.equal(head.status, 200); assert.equal(head.headers.get('content-type'), 'audio/mp4');
    assert.ok(Number(head.headers.get('content-length')) > 1000);
    const range = await fetch(base + '/aac.m4a', { headers: { Range: 'bytes=0-31' } });
    assert.equal(range.status, 206); assert.equal((await range.arrayBuffer()).byteLength, 32);
    assert.match(range.headers.get('content-range'), /^bytes 0-31\/\d+$/);
    const rejected = await fetch(base + '/aac.m4a', { headers: { Range: 'bytes=999999999-' } });
    assert.equal(rejected.status, 416);
    const pulse = await fetch(base + '/pulses.wav');
    const data = Buffer.from(await pulse.arrayBuffer());
    assert.equal(data.toString('ascii', 0, 4), 'RIFF'); assert.equal(data.readUInt32LE(24), 48000);
    assert.ok(Math.abs(data.readInt16LE(44 + 750 * 4)) > 0);
    assert.equal(data.readInt16LE(44 + 15000 * 4), 0, 'Silence between kicks is real PCM silence');
    assert.equal((await fetch(base + '/not-media')).status, 404);
  } finally { child.kill(); }
});
