import {randomBytes,randomUUID,scrypt as scryptCallback,createHash,timingSafeEqual} from 'node:crypto';
import {promisify} from 'node:util';
import {readFile} from 'node:fs/promises';
import {sharedSnapshot,mergeLibraries} from '../windows/core/library.mjs';

const scrypt=promisify(scryptCallback),uuid=/^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const empty=()=>({version:1,tracks:[],playlists:[],favorites:[],history:[],followedArtists:[],queue:[],settings:{}});
const error=(status,message)=>Object.assign(Error(message),{status});
const digest=value=>createHash('sha256').update(value).digest('hex');
export function username(value){if(typeof value!=='string'||!/^[a-zA-Z0-9_][a-zA-Z0-9_.-]{2,23}$/.test(value))throw error(400,'Pseudo : 3 à 24 lettres, chiffres, points, tirets ou underscores.');return value.toLowerCase();}
export function password(value){if(typeof value!=='string'||value.length<12||value.length>128)throw error(400,'Le mot de passe doit contenir entre 12 et 128 caractères.');return value;}
export async function hashPassword(value){password(value);const salt=randomBytes(16),hash=await scrypt(value,salt,64,{N:32768,r:8,p:1,maxmem:67108864});return `scrypt-v1$${salt.toString('hex')}$${hash.toString('hex')}`;}
export async function verifyPassword(value,encoded){
  if(typeof value!=='string'||value.length>128)return false;
  const [,saltHex,hashHex]=String(encoded).split('$');
  if(!/^[a-f0-9]{32}$/.test(saltHex||'')||!/^[a-f0-9]{128}$/.test(hashHex||''))return false;
  const actual=await scrypt(value,Buffer.from(saltHex,'hex'),64,{N:32768,r:8,p:1,maxmem:67108864});return timingSafeEqual(actual,Buffer.from(hashHex,'hex'));
}
export class Accounts {
  constructor(database){this.db=database;this.now=()=>Date.now();}
  async init(){
    for(const statement of (await readFile(new URL('./schema.sql',import.meta.url),'utf8')).split(';').map(s=>s.trim()).filter(Boolean))await this.db.query(statement);
    // Supabase can have explicit default grants in addition to PUBLIC grants.
    // Only revoke on our tables; never change another project's/default schema privileges.
    const {rows}=await this.db.query("SELECT rolname FROM pg_roles WHERE rolname IN ('anon','authenticated')");
    for(const {rolname}of rows)await this.db.query(`REVOKE ALL ON soryn_accounts,soryn_sessions,soryn_cloud_libraries,soryn_cloud_devices FROM "${rolname}"`);
  }
  async session(account,db=this.db){
    const token=randomBytes(32).toString('base64url'),expiresAt=this.now()+30*86400000;
    await db.query('INSERT INTO soryn_sessions(token_hash,account_id,expires_at) VALUES($1,$2,$3)',[digest(token),account.id,new Date(expiresAt)]);
    return {account:{id:account.id,username:account.username,displayName:account.display_name},token,expiresAt};
  }
  async register(input){
    const name=username(input.username),hash=await hashPassword(input.password),id=randomUUID();
    try{await this.db.query('INSERT INTO soryn_accounts(id,username,display_name,password_hash) VALUES($1,$2,$3,$4)',[id,name,input.username,hash]);}
    catch(e){if(e.code==='23505')throw error(409,'Ce pseudo n’est pas disponible.');throw e;}
    return this.session({id,username:name,display_name:input.username});
  }
  async login(input){
    const name=username(input.username);password(input.password);
    const {rows}=await this.db.query('SELECT id,username,display_name,password_hash FROM soryn_accounts WHERE username=$1',[name]);
    const account=rows[0];
    // A missing user still performs the same expensive password KDF.
    const fake=`scrypt-v1$${'0'.repeat(32)}$${'0'.repeat(128)}`;
    const valid=await verifyPassword(input.password,account?.password_hash||fake);
    if(!account||!valid)throw error(401,'Pseudo ou mot de passe incorrect.');
    await this.db.query('DELETE FROM soryn_sessions WHERE expires_at < now()');
    return this.session(account);
  }
  async authenticate(authorization){
    const token=/^Bearer ([A-Za-z0-9_-]{43})$/.exec(authorization||'')?.[1];if(!token)throw error(401,'Connexion requise pour la synchronisation.');
    const {rows}=await this.db.query('SELECT a.id,a.username,a.display_name FROM soryn_sessions s JOIN soryn_accounts a ON a.id=s.account_id WHERE s.token_hash=$1 AND s.expires_at>$2',[digest(token),new Date(this.now())]);
    if(!rows[0])throw error(401,'Session expirée. Reconnecte-toi pour synchroniser.');return rows[0];
  }
  async logout(authorization){await this.authenticate(authorization);await this.db.query('DELETE FROM soryn_sessions WHERE token_hash=$1',[digest(authorization.slice(7))]);return {ok:true};}
  async deleteAccount(account,input){
    const {rows}=await this.db.query('SELECT password_hash FROM soryn_accounts WHERE id=$1',[account.id]);
    if(!rows[0]||!await verifyPassword(input.password,rows[0].password_hash))throw error(401,'Mot de passe incorrect.');
    await this.db.query('DELETE FROM soryn_accounts WHERE id=$1',[account.id]);return {ok:true};
  }
  async sync(account,input){
    if(input.protocol!==1||!uuid.test(input.deviceID||'')||!uuid.test(input.requestID||''))throw error(400,'Échange de bibliothèque invalide.');
    const requestID=input.requestID.toLowerCase(),acknowledgedRequestID=typeof input.acknowledgedRequestID==='string'?input.acknowledgedRequestID.toLowerCase():null;
    let incoming;try{incoming=sharedSnapshot(input.snapshot);}catch{throw error(400,'Bibliothèque invalide.');}
    return this.db.transaction(async db=>{
      await db.query('INSERT INTO soryn_cloud_libraries(account_id,snapshot) VALUES($1,$2) ON CONFLICT(account_id) DO NOTHING',[account.id,JSON.stringify(empty())]);
      const {rows:[row]}=await db.query('SELECT snapshot FROM soryn_cloud_libraries WHERE account_id=$1 FOR UPDATE',[account.id]);
      const {rows:[device]}=await db.query('SELECT baseline,pending_request,pending_snapshot FROM soryn_cloud_devices WHERE account_id=$1 AND device_id=$2',[account.id,input.deviceID]);
      if(device?.pending_request===requestID)return {protocol:1,requestID:input.requestID,snapshot:device.pending_snapshot};
      const baseline=device&&acknowledgedRequestID===device.pending_request?device.pending_snapshot:device?.baseline;
      const snapshot=sharedSnapshot(mergeLibraries(baseline,row.snapshot,incoming));
      await db.query('UPDATE soryn_cloud_libraries SET snapshot=$2,updated_at=now() WHERE account_id=$1',[account.id,JSON.stringify(snapshot)]);
      await db.query('INSERT INTO soryn_cloud_devices(account_id,device_id,baseline,pending_request,pending_snapshot) VALUES($1,$2,$3,$4,$5) ON CONFLICT(account_id,device_id) DO UPDATE SET baseline=EXCLUDED.baseline,pending_request=EXCLUDED.pending_request,pending_snapshot=EXCLUDED.pending_snapshot',[account.id,input.deviceID,baseline?JSON.stringify(baseline):null,input.requestID,JSON.stringify(snapshot)]);
      return {protocol:1,requestID:input.requestID,snapshot};
    });
  }
}

export function accountHandler(accounts,{trustProxy=false,allowHTTP=false}={}){
  const attempts=new Map();let hashing=0;
  return async(req,res)=>{
    res.setHeader('Content-Type','application/json; charset=utf-8');res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');
    const send=(status,body)=>{res.statusCode=status;res.end(JSON.stringify(body));};
    try{
      const path=new URL(req.url,'http://localhost').pathname;
      if(req.headers.origin)throw error(403,'Origine navigateur refusée.');
      if(path==='/health'){send(200,{ok:true,accounts:!!accounts,persistent:!!accounts});return;}
      if(!allowHTTP&&!req.socket.encrypted&&!(trustProxy&&req.headers['x-forwarded-proto']==='https'))throw error(400,'HTTPS requis.');
      if(!accounts)throw error(503,'Synchronisation par compte indisponible : stockage persistant non configuré. Le mode local reste utilisable.');
      if(req.method!=='POST')throw error(405,'Méthode non autorisée.');
      const ip=trustProxy?String(req.headers['x-forwarded-for']||req.socket.remoteAddress).split(',').at(-1).trim():req.socket.remoteAddress;
      const authPath=['/v1/accounts/register','/v1/accounts/login'].includes(path),key=ip+(authPath?'auth':'sync'),now=Date.now();
      for(const [id,v]of attempts)if(now-v.at>900000)attempts.delete(id);
      const count=attempts.get(key)||{n:0,at:now};attempts.set(key,count);
      if(++count.n>(authPath?20:600))throw error(429,'Trop de tentatives. Réessaie dans quelques minutes.');
      let size=0;const chunks=[];
      for await(const chunk of req){size+=chunk.length;if(size>(path.endsWith('/sync')?8_000_000:4096))throw error(413,'Requête trop volumineuse.');chunks.push(chunk);}
      let input;try{input=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{throw error(400,'Données JSON invalides.');}
      if(!input||Array.isArray(input)||typeof input!=='object')throw error(400,'Données invalides.');
      if(authPath){if(hashing>=2)throw error(429,'Serveur occupé. Réessaie dans un instant.');hashing++;try{send(200,await accounts[path.endsWith('register')?'register':'login'](input));}finally{hashing--;}return;}
      const account=await accounts.authenticate(req.headers.authorization);
      if(path==='/v1/accounts/logout')send(200,await accounts.logout(req.headers.authorization));
      else if(path==='/v1/accounts/me')send(200,{account:{id:account.id,username:account.username,displayName:account.display_name}});
      else if(path==='/v1/accounts/sync')send(200,await accounts.sync(account,input));
      else if(path==='/v1/accounts/delete'){if(hashing>=2)throw error(429,'Serveur occupé. Réessaie dans un instant.');hashing++;try{send(200,await accounts.deleteAccount(account,input));}finally{hashing--;}}
      else throw error(404,'Route inconnue.');
    }catch(e){send(e.status||500,{error:e.status?e.message:'Service temporairement indisponible. Aucune donnée locale n’a été effacée.'});}
  };
}
