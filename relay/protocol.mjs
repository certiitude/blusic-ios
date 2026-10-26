import {createHmac, timingSafeEqual} from 'node:crypto';

export const validVideo = value => /^[A-Za-z0-9_-]{11}$/.test(value);
export function bearerMatches(header, key) {
  const actual = Buffer.from(header || '');
  const expected = Buffer.from(`Bearer ${key}`);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}
// The IPA receives a non-expiring application access token, never the server's
// HMAC master key. It cannot sign audio tickets or change configuration.
export function applicationAccess(key, platform='ios') {
  if(!['ios','android'].includes(platform))throw Error('Unknown application platform');
  return `app.${platform}.${createHmac('sha256', key).update(`application:${platform}|v1`).digest('hex')}`;
}
export function clientCapability(key, expiry) {
  return `ios.${expiry}.${createHmac('sha256', key).update(`client:ios|${expiry}`).digest('hex')}`;
}
export function verifyClientCapability(key, header, now = Date.now()) {
  const value = typeof header === 'string' && header.startsWith('Bearer ') ? header.slice(7) : '';
  const application=/^app\.(ios|android)\.[a-f0-9]{64}$/.exec(value);
  if (application) {
    const expected = Buffer.from(applicationAccess(key,application[1]));
    return timingSafeEqual(Buffer.from(value), expected);
  }
  const match = /^ios\.(\d+)\.([a-f0-9]{64})$/.exec(value);
  if (!match) return false;
  const expiry = Number(match[1]);
  if (!Number.isSafeInteger(expiry) || expiry <= now || expiry > now + 366 * 86400000) return false;
  const expected = Buffer.from(clientCapability(key, expiry));
  const actual = Buffer.from(value);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}
export function ticket(key, id, expiry, quality='standard') {
  const binding=`${id}|${expiry}`+(quality==='high'?'|high':'');
  return `${expiry}.${createHmac('sha256', key).update(binding).digest('hex')}`;
}
export function verifyTicket(key, id, value, now = Date.now(), quality='standard') {
  if (typeof value !== 'string') return false;
  const [time] = value.split('.');
  const expiry = Number(time);
  if (!Number.isSafeInteger(expiry) || expiry < now || expiry > now + 21 * 60 * 1000) return false;
  const expected = ticket(key, id, expiry, quality);
  const actual = Buffer.from(value);
  return actual.length === expected.length && timingSafeEqual(actual, Buffer.from(expected));
}
export function parseRange(header, size) {
  if (!header) return {start: 0, end: size - 1, partial: false};
  const match = /^bytes=(\d*)-(\d*)$/.exec(header);
  if (!match || (!match[1] && !match[2])) return null;
  const start = match[1] ? Number(match[1]) : Math.max(0, size - Number(match[2]));
  const end = match[1] && match[2] ? Math.min(size - 1, Number(match[2])) : size - 1;
  if (!Number.isSafeInteger(start) || !Number.isSafeInteger(end) || start < 0 || start >= size || end < start) return null;
  return {start, end, partial: true};
}
