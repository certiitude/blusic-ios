// CI-only encrypted Node/Swift interoperability fixture. No user data or production key.
import {tmpdir} from 'node:os';
import {mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import {LibraryStore} from '../core/library.mjs';
import {SyncServer} from '../core/sync.mjs';
const directory = await mkdtemp(join(tmpdir(), 'soryn-ios-sync-test-'));
const store = new LibraryStore(directory); await store.load();
const server = new SyncServer(store);
await server.start(Buffer.alloc(32), 48764);
console.log('Soryn Node interoperability fixture listening on port 48764.');
for (const signal of ['SIGTERM', 'SIGINT']) process.on(signal, async () => { await server.stop(); await rm(directory, {recursive: true, force: true}); process.exit(); });
