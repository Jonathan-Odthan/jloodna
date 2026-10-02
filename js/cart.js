import { sb } from './supabase.js';
import { getUser } from './auth.js';
import { toast } from './utils.js';

const KEY = 'jl_cart';
const read = () => { try { const v = JSON.parse(localStorage.getItem(KEY) || '[]'); return Array.isArray(v) ? v : []; } catch { return []; } };
const vkey = (v) => (v ? Object.keys(v).sort().map((k) => `${k}:${v[k]}`).join('|') : '');
let syncTimer;

function write(items) {
  localStorage.setItem(KEY, JSON.stringify(items));
  window.dispatchEvent(new CustomEvent('jl:cart'));
  clearTimeout(syncTimer); syncTimer = setTimeout(pushToServer, 600);
}
export const getCart = () => read();
export const cartCount = () => read().reduce((n, i) => n + i.quantity, 0);

export function addItem(product_id, quantity = 1, variant = null, max = 99) {
  const items = read(); const k = vkey(variant);
  const ex = items.find((i) => i.product_id === product_id && vkey(i.variant) === k);
  const next = Math.min((ex?.quantity || 0) + quantity, Math.min(max, 99));
  if (ex) ex.quantity = next; else items.push({ product_id, quantity: next, variant });
  write(items); toast('Produit ajouté au panier.');
}
export function setQty(product_id, variant, quantity) {
  const k = vkey(variant);
  const items = read().map((i) => (i.product_id === product_id && vkey(i.variant) === k ? { ...i, quantity: Math.max(1, Math.min(99, quantity)) } : i));
  write(items);
}
export function removeItem(product_id, variant) {
  const k = vkey(variant);
  write(read().filter((i) => !(i.product_id === product_id && vkey(i.variant) === k)));
}
export const clearCart = () => write([]);

// Synchronisation avec cart_items quand le client est connecté (le panier reste local pour les invités).
async function pushToServer() {
  if (!sb) return; const u = await getUser(); if (!u) return;
  const items = read();
  await sb.from('cart_items').delete().eq('user_id', u.id);
  if (items.length) await sb.from('cart_items').insert(items.map((i) => ({ user_id: u.id, product_id: i.product_id, variant_key: vkey(i.variant), variant: i.variant, quantity: i.quantity })));
}
export async function mergeServerCart() {
  if (!sb) return; const u = await getUser(); if (!u) return;
  const { data } = await sb.from('cart_items').select('product_id, variant, quantity');
  if (!data?.length) return;
  const items = read();
  for (const r of data) {
    const ex = items.find((i) => i.product_id === r.product_id && vkey(i.variant) === vkey(r.variant));
    if (ex) ex.quantity = Math.max(ex.quantity, r.quantity); else items.push({ product_id: r.product_id, quantity: r.quantity, variant: r.variant });
  }
  localStorage.setItem(KEY, JSON.stringify(items)); window.dispatchEvent(new CustomEvent('jl:cart'));
}
