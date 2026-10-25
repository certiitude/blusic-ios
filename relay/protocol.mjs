import {createHmac, timingSafeEqual} from 'node:crypto';

export const validVideo = value => /^[A-Za-z0-9_-]{11}$/.test(value);
export function bearerMatches(header, key) {
  const actual = Buffer.from(header || '');
  const expected = Buffer.from(`Bearer ${key}`);
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}
export function ticket(key, id, expiry) {
  return `${expiry}.${createHmac('sha256', key).update(`${id}|${expiry}`).digest('hex')}`;
}
export function verifyTicket(key, id, value, now = Date.now()) {
  if (typeof value !== 'string') return false;
  const [time] = value.split('.');
  const expiry = Number(time);
  if (!Number.isSafeInteger(expiry) || expiry < now || expiry > now + 21 * 60 * 1000) return false;
  const expected = ticket(key, id, expiry);
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
