import {parentPort, workerData} from 'node:worker_threads';
import {parseFile} from 'music-metadata';
import {YouTubeProvider} from '../vendor/provider.mjs';
const provider = new YouTubeProvider({maxFileBytes: 100_000_000});
try {
  const entry = await provider.prepare(workerData.videoID, 'high');
  const metadata = await parseFile(entry.path, {duration: true});
  if (!(metadata.format.duration > 0) || workerData.duration > 0 && metadata.format.duration < workerData.duration - Math.max(2, workerData.duration * 0.02)) throw Error('Fichier audio incomplet : durée invalide.');
  parentPort.postMessage({path: entry.path, duration: metadata.format.duration, bitrate: entry.bitrate, size: entry.size});
  // Main copies the validated file before acknowledging and deleting scratch data.
  await new Promise(resolve => parentPort.once('message', resolve));
} catch (error) { parentPort.postMessage({error: String(error.message).replace(/https?:\/\/\S+/g, '[source]').slice(0, 800)}); }
finally { await provider.close(); }
