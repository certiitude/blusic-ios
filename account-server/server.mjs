import {createServer} from 'node:http';
import pg from 'pg';
import {Accounts,accountHandler} from './accounts.mjs';
import {databaseOptions} from './database.mjs';
let accounts,pool;
if(process.env.DATABASE_URL){
  pool=new pg.Pool(databaseOptions(process.env.DATABASE_URL));
  const database={query:(...args)=>pool.query(...args),async transaction(action){const client=await pool.connect();try{await client.query('BEGIN');const result=await action(client);await client.query('COMMIT');return result;}catch(error){await client.query('ROLLBACK');throw error;}finally{client.release();}}};
  accounts=new Accounts(database);await accounts.init();
}
const server=createServer(accountHandler(accounts,{trustProxy:process.env.TRUST_PROXY==='1'}));
server.requestTimeout=20000;server.headersTimeout=10000;
server.listen(Number(process.env.PORT||10000),'0.0.0.0',()=>console.log('Soryn account service ready; persistent storage '+(accounts?'configured':'NOT configured; registration disabled')));
process.on('SIGTERM',()=>server.close(async()=>{await pool?.end();process.exit();}));
