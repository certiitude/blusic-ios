// CI-only real HTTP/PostgreSQL-engine fixture for the native Swift account client.
import {createServer} from 'node:http';
import {PGlite} from '@electric-sql/pglite';
import {Accounts,accountHandler} from '../accounts.mjs';
const pg=new PGlite();await pg.waitReady;
const accounts=new Accounts({query:(...args)=>pg.query(...args),transaction:fn=>pg.transaction(fn)});await accounts.init();
const server=createServer(accountHandler(accounts,{allowHTTP:true}));
await new Promise(resolve=>server.listen(48765,'127.0.0.1',resolve));
console.log('Soryn account interoperability fixture ready on loopback port 48765.');
for(const signal of ['SIGTERM','SIGINT'])process.on(signal,()=>server.close(async()=>{await pg.close();process.exit();}));
