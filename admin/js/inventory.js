import { sb } from '/js/supabase.js';
import { $, $$, esc, fmtDate, toast, friendlyError } from '/js/utils.js';
import { table } from './ui.js';
export async function render(el) {
  const [{ data: inv, error }, { data: mov }] = await Promise.all([
    sb.from('inventory').select('quantity, low_stock_threshold, products(id, name, sku, status)').order('quantity'),
    sb.from('inventory_movements').select('delta, quantity_after, reason, created_at, products(name)').order('created_at', { ascending: false }).limit(30)]);
  if (error) throw error;
  const low = inv.filter((i) => i.quantity > 0 && i.quantity <= i.low_stock_threshold); const out = inv.filter((i) => i.quantity === 0);
  el.innerHTML = `<h1>Stock</h1>
  ${out.length || low.length ? `<div class="panel-box" role="alert">${out.map((i) => `<p style="margin:.2em 0"><strong>Rupture :</strong> ${esc(i.products.name)}</p>`).join('')}${low.map((i) => `<p style="margin:.2em 0">Attention : le produit <strong>${esc(i.products.name)}</strong> possède seulement ${i.quantity} unité(s).</p>`).join('')}</div>` : '<p class="muted">Aucune alerte de stock.</p>'}
  ${table(['Produit', 'SKU', 'Stock', 'Alerte à', 'Ajuster'], inv.map((i) => `<tr><td class="wrap-t">${esc(i.products.name)}</td><td>${esc(i.products.sku || '—')}</td><td><strong>${i.quantity}</strong></td><td>${i.low_stock_threshold}</td><td><div class="row"><input type="number" min="0" value="${i.quantity}" style="width:90px" data-q="${i.products.id}" aria-label="Nouveau stock"><button class="btn ghost sm" data-s="${i.products.id}">Mettre à jour</button></div></td></tr>`))}
  <h2 style="margin-top:24px">Derniers mouvements</h2>${table(['Date', 'Produit', 'Variation', 'Stock après', 'Motif'], (mov || []).map((m) => `<tr><td>${fmtDate(m.created_at)}</td><td class="wrap-t">${esc(m.products?.name || '—')}</td><td>${m.delta > 0 ? '+' : ''}${m.delta}</td><td>${m.quantity_after}</td><td class="wrap-t">${esc(m.reason)}</td></tr>`))}`;
  $$('[data-s]').forEach((b) => (b.onclick = async () => { const q = parseInt($(`[data-q="${b.dataset.s}"]`).value, 10); if (!(q >= 0)) return toast('Quantité invalide.', 'err'); const { error } = await sb.rpc('admin_set_stock', { p_product_id: b.dataset.s, p_quantity: q, p_reason: 'Ajustement manuel' }); toast(error ? friendlyError(error) : 'Stock mis à jour.', error ? 'err' : 'ok'); render(el); }));
}
