import { initLayout } from '../layout.js';
import { sb } from '../supabase.js';
import { getCart, setQty, removeItem } from '../cart.js';
import { getProductsByIds, imgOf, stockOf, priceOf } from '../products.js';
import { $, esc, fmtPrice, emptyState, errorState, toast } from '../utils.js';

initLayout();
let shipping = { flat_fee: 0, free_over: null }; let coupon = null;
const sum = $('#sum'); const lines = $('#lines');

async function render() {
  const cart = getCart();
  if (!cart.length) { lines.innerHTML = emptyState('Votre panier est vide.', '<a class="btn primary" href="/shop">Continuer les achats</a>'); sum.hidden = true; return; }
  sum.hidden = false;
  let prods; try { prods = await getProductsByIds([...new Set(cart.map((i) => i.product_id))]); } catch { lines.innerHTML = errorState(); return; }
  const map = new Map(prods.map((p) => [p.id, p])); let subtotal = 0; let blocked = false; let html = '';
  for (const it of cart) {
    const p = map.get(it.product_id);
    if (!p) { removeItem(it.product_id, it.variant); continue; }
    const stock = stockOf(p); const qty = Math.min(it.quantity, Math.max(stock, 1));
    if (stock <= 0) blocked = true; else subtotal += priceOf(p) * qty;
    html += `<div class="cart-line"><img src="${imgOf(p)}" alt="" loading="lazy" width="90" height="90"><div><a href="/product?slug=${encodeURIComponent(p.slug)}"><strong>${esc(p.name)}</strong></a>${it.variant ? `<br><span class="muted">${Object.entries(it.variant).map(([k, v]) => `${esc(k)} : ${esc(v)}`).join(', ')}</span>` : ''}<br>${fmtPrice(priceOf(p))}${stock <= 0 ? '<br><span class="stock out">Produit actuellement indisponible</span>' : stock < qty ? `<br><span class="stock out">Stock limité : ${stock}</span>` : ''}</div>
      <div class="ctl"><div class="qty"><button aria-label="Moins" data-act="dec" data-id="${p.id}" data-v="${esc(JSON.stringify(it.variant ?? null))}">−</button><input aria-label="Quantité" value="${qty}" readonly><button aria-label="Plus" data-act="inc" data-id="${p.id}" data-v="${esc(JSON.stringify(it.variant ?? null))}" ${qty >= stock ? 'disabled' : ''}>+</button></div><button class="link" data-act="rm" data-id="${p.id}" data-v="${esc(JSON.stringify(it.variant ?? null))}">Supprimer</button></div></div>`;
  }
  lines.innerHTML = html || emptyState('Votre panier est vide.', '<a class="btn primary" href="/shop">Continuer les achats</a>');
  lines.querySelectorAll('[data-act]').forEach((b) => (b.onclick = () => {
    const variant = JSON.parse(b.dataset.v || 'null'); const id = b.dataset.id;
    const cur = getCart().find((i) => i.product_id === id && JSON.stringify(i.variant ?? null) === JSON.stringify(variant)); if (!cur) return;
    if (b.dataset.act === 'rm') removeItem(id, cur.variant); else setQty(id, cur.variant, cur.quantity + (b.dataset.act === 'inc' ? 1 : -1));
    render();
  }));
  const fee = shipping.free_over && subtotal >= shipping.free_over ? 0 : shipping.flat_fee;
  let discount = 0;
  if (coupon && sb) { const { data } = await sb.rpc('validate_coupon', { p_code: coupon, p_subtotal: subtotal }); if (data?.valid) discount = data.discount; else { coupon = null; if (data?.message) toast(data.message, 'err'); } }
  sessionStorage.setItem('jl_coupon', coupon || '');
  const total = Math.max(subtotal + fee - discount, 0);
  sum.innerHTML = `<h2 style="font-size:1.2rem">Résumé</h2>
    <div class="line"><span>Sous-total</span><span>${fmtPrice(subtotal)}</span></div>
    <div class="line"><span>Livraison</span><span>${fee ? fmtPrice(fee) : 'Offerte'}</span></div>
    ${discount ? `<div class="line"><span>Code ${esc(coupon)}</span><span>− ${fmtPrice(discount)}</span></div>` : ''}
    <div class="line total"><span>Total</span><span>${fmtPrice(total)}</span></div>
    <form id="cp" class="row" style="margin-top:6px"><input id="cp-code" placeholder="Code promo" aria-label="Code promo" style="flex:1" value="${esc(coupon || '')}"><button class="btn ghost sm">Appliquer</button></form>
    <a class="btn primary block ${blocked || subtotal <= 0 ? 'disabled' : ''}" ${blocked || subtotal <= 0 ? 'aria-disabled="true" style="pointer-events:none;opacity:.5"' : ''} href="/checkout">Passer commande</a>
    <a class="btn ghost block" href="/shop">Continuer les achats</a>`;
  $('#cp').onsubmit = (e) => { e.preventDefault(); coupon = $('#cp-code').value.trim() || null; render(); };
}
(async () => {
  if (sb) { const { data } = await sb.from('settings').select('value').eq('key', 'shipping').maybeSingle(); if (data) shipping = data.value; }
  coupon = sessionStorage.getItem('jl_coupon') || null; render();
  window.addEventListener('jl:cart', () => {});
})();
