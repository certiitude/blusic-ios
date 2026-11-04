import {readFile,writeFile,rename,rm} from 'node:fs/promises';
import {join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {sharedSnapshot,mergeLibraries} from './library.mjs';

export const ACCOUNT_SERVER='https://soryn-accounts.onrender.com';
export function accountServerURL(value,{allowHTTP=false}={}){
  const url=new URL(value);
  if((url.protocol!=='https:'&&!(allowHTTP&&url.protocol==='http:'&&['127.0.0.1','localhost'].includes(url.hostname)))||url.username||url.password||url.pathname!=='/'||url.search||url.hash)throw Error('Adresse du serveur de comptes invalide.');
  return url.origin;
}
export class AccountClient {
  constructor({store,secureStorage,server=ACCOUNT_SERVER,allowHTTP=false,onChange=()=>{},fetchFunction=fetch}){
    this.store=store;this.secureStorage=secureStorage;this.server=accountServerURL(server,{allowHTTP});this.onChange=onChange;this.fetch=fetchFunction;this.status='Sans compte · bibliothèque locale';this.session=null;this.busy=false;this.persisting=Promise.resolve();
  }
  state(){return {signedIn:!!this.session,account:this.session?.account||null,busy:this.busy,status:this.status,lastSync:this.lastSync||null,server:this.server};}
  async load(){
    try{const decrypted=await this.secureStorage.decryptStringAsync(await readFile(join(this.store.directory,'account-session.dat')));this.session=JSON.parse(decrypted.result);if(!this.session?.account?.id||typeof this.session.token!=='string')throw Error('Session invalide');if(decrypted.shouldReEncrypt)await this.persistSession(this.session);this.status='Compte connecté · synchronisation en attente';}
    catch(e){this.session=null;if(e.code!=='ENOENT')this.status='Session protégée illisible. Reconnecte-toi pour synchroniser.';}
    try{this.device=JSON.parse(await readFile(join(this.store.directory,'account-device.json'),'utf8'));}catch{this.device={deviceID:randomUUID(),acknowledgedRequestID:null};await this.persistDevice();}
  }
  async persistDevice(){const file=join(this.store.directory,'account-device.json');await writeFile(file+'.tmp',JSON.stringify(this.device));await rename(file+'.tmp',file);}
  async persistSession(session){const file=join(this.store.directory,'account-session.dat');await writeFile(file+'.tmp',await this.secureStorage.encryptStringAsync(JSON.stringify(session)));await rename(file+'.tmp',file);}
  async request(path,input={},token=this.session?.token){
    const response=await this.fetch(this.server+'/v1/accounts/'+path,{method:'POST',redirect:'error',signal:AbortSignal.timeout(65000),headers:{'Content-Type':'application/json',...(token?{Authorization:'Bearer '+token}:{})},body:JSON.stringify(input)});
    let size=0,chunks=[];for await(const chunk of response.body){size+=chunk.length;if(size>8_000_000)throw Error('Réponse du compte trop volumineuse.');chunks.push(chunk);}
    let body;try{body=JSON.parse(Buffer.concat(chunks).toString('utf8'));}catch{throw Error('Serveur de comptes indisponible. Le mode local reste utilisable.');}
    if(!response.ok){const error=Error(body.error||'Échange avec le compte refusé.');error.status=response.status;throw error;}return body;
  }
  async authenticate(kind,input){
    if(this.busy)throw Error('Une opération est déjà en cours.');
    if(this.session)throw Error('Déconnecte le compte actuel avant d’en associer un autre.');
    if(!['login','register'].includes(kind)||typeof input?.username!=='string'||typeof input?.password!=='string')throw Error('Identifiants invalides.');
    if(!await this.secureStorage.isAsyncEncryptionAvailable())throw Error('Le stockage sécurisé Windows est indisponible. Aucun mot de passe ne sera enregistré.');
    this.busy=true;this.status='Connexion au compte…';this.onChange();
    try{
      const session=await this.request(kind,input,null);
      if(!session.account?.id||typeof session.token!=='string'||!/^[A-Za-z0-9_-]{43}$/.test(session.token))throw Error('Session reçue invalide.');
      await this.persistSession(session);
      this.session=session;this.device={deviceID:randomUUID(),acknowledgedRequestID:null};await this.persistDevice();this.status='Compte connecté. Prêt à fusionner la bibliothèque.';
    }catch(error){this.status=error.message;throw error;}finally{this.busy=false;this.onChange();}
    await this.sync();return this.state();
  }
  async sync(){
    if(!this.session||this.busy)return this.state();
    this.busy=true;this.status='Synchronisation du compte…';this.onChange();
    try{
      const sent=sharedSnapshot(this.store.data),requestID=randomUUID(),session=this.session;
      const reply=await this.request('sync',{protocol:1,deviceID:this.device.deviceID,requestID,acknowledgedRequestID:this.device.acknowledgedRequestID,snapshot:sent});
      if(this.session!==session)return this.state();
      if(reply.protocol!==1||reply.requestID!==requestID)throw Error('Réponse de synchronisation invalide.');
      const remote=sharedSnapshot(reply.snapshot),current=this.store.data,merged=mergeLibraries(sent,sharedSnapshot(current),remote);
      const localFiles=new Map(current.tracks.filter(t=>t.source==='local').map(t=>[t.id,t]));
      const aliases=new Map();for(const t of current.tracks)if(!merged.tracks.some(m=>m.id===t.id)&&t.location){const same=merged.tracks.find(m=>m.location===t.location&&m.source===t.source);if(same)aliases.set(t.id,same.id);}
      const remap=id=>aliases.get(id)||id;
      await this.store.update(s=>Object.assign(s,merged,{settings:s.settings,queue:(s.queue||[]).map(remap),currentTrackID:s.currentTrackID?remap(s.currentTrackID):undefined,tracks:[...merged.tracks.map(t=>localFiles.get(t.id)||t),...[...localFiles.values()].filter(t=>!merged.tracks.some(m=>m.id===t.id))]}));
      this.device.acknowledgedRequestID=requestID;await this.persistDevice();this.lastSync=Date.now();this.status='Bibliothèque synchronisée avec ton compte';this.onChange(aliases);
    }catch(error){this.status=error.status===401?'Session expirée. Reconnecte-toi ; ta bibliothèque locale est conservée.':error.message;}finally{this.busy=false;this.onChange();}
    return this.state();
  }
  async logout(){
    if(this.busy)throw Error('Attends la fin de la synchronisation avant de te déconnecter.');
    this.busy=true;
    const session=this.session;this.session=null;this.lastSync=null;this.status='Déconnecté · bibliothèque locale conservée';
    try{
    await rm(join(this.store.directory,'account-session.dat'),{force:true});this.device={deviceID:randomUUID(),acknowledgedRequestID:null};await this.persistDevice();this.onChange();
    if(session)try{await this.request('logout',{},session.token);}catch{this.status='Déconnecté sur ce PC. Révocation distante non confirmée ; session distante limitée à 30 jours.';this.onChange();}
    }finally{this.busy=false;this.onChange();}
    return this.state();
  }
  async deleteAccount(password){if(!this.session||this.busy)throw Error('Compte non disponible.');this.busy=true;this.onChange();try{await this.request('delete',{password});this.session=null;await rm(join(this.store.directory,'account-session.dat'),{force:true});this.status='Compte supprimé du serveur · bibliothèque locale conservée';this.lastSync=null;}finally{this.busy=false;this.onChange();}return this.state();}
}
