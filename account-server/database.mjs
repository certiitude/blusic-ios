import {readFileSync} from 'node:fs';

// Supabase's database CA is separate from the public HTTPS trust store.
// Keep hostname and certificate verification on, including through the IPv4 pooler.
export function databaseOptions(connectionString){
  const url=new URL(connectionString);
  if(!['postgres:','postgresql:'].includes(url.protocol))throw Error('PostgreSQL URL required');
  const supabase=url.hostname.endsWith('.supabase.co')||url.hostname.endsWith('.pooler.supabase.com');
  const ssl={rejectUnauthorized:true,...(supabase?{ca:readFileSync(new URL('./certs/supabase-prod-ca-2021.crt',import.meta.url),'utf8')}:{})};
  for(const key of ['sslmode','sslcert','sslkey','sslrootcert'])url.searchParams.delete(key);
  return {connectionString:url.href,ssl,max:4,connectionTimeoutMillis:10000,statement_timeout:15000};
}
