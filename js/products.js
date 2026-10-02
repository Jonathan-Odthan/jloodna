import { sb } from './supabase.js';
import { esc, fmtPrice, safeUrl } from './utils.js';
import { addItem } from './cart.js';

const SELECT = '*, product_images(url, alt, sort_order), inventory(quantity, low_stock_threshold), categories(name, slug)';
export const PAGE_SIZE = 12;

export const imgOf = (p) => safeUrl([...(p.product_images || [])].sort((a, b) => a.sort_order - b.sort_order)[0]?.url) || '/assets/icons/icon-192.png';
export const stockOf = (p) => { const i = Array.isArray(p.inventory) ? p.inventory[0] : p.inventory; return i?.quantity ?? 0; };
export const priceOf = (p) => p.sale_price ?? p.price;

export async function listProducts({ q, category, min, max, sort = 'new', page = 0, featured, onSale, limit = PAGE_SIZE, exclude } = {}) {
  let query = sb.from('products').select(SELECT, { count: 'exact' }).eq('status', 'published');
  if (category) query = query.eq('category_id', category);
  if (featured) query = query.eq('is_featured', true);
  if (onSale) query = query.eq('is_on_sale', true).not('sale_price', 'is', null);
  if (exclude) query = query.neq('id', exclude);
  if (q) { const s = q.replace(/[%,()]/g, ' ').trim(); query = query.or(`name.ilike.%${s}%,sku.ilike.%${s}%`); }
  if (min != null && min !== '') query = query.gte('price', min);
  if (max != null && max !== '') query = query.lte('price', max);
  if (sort === 'price_asc') query = query.order('price', { ascending: true });
  else if (sort === 'price_desc') query = query.order('price', { ascending: false });
  else if (sort === 'popular') query = query.order('sold_count', { ascending: false });
  else query = query.order('created_at', { ascending: false });
  const from = page * limit; query = query.range(from, from + limit - 1);
  const { data, error, count } = await query; if (error) throw error;
  return { items: data || [], count: count || 0 };
}
export async function getProduct(slug) {
  const { data, error } = await sb.from('products').select(SELECT).eq('slug', slug).eq('status', 'published').maybeSingle();
  if (error) throw error; return data;
}
export async function getProductsByIds(ids) {
  if (!ids.length) return [];
  const { data, error } = await sb.from('products').select(SELECT).in('id', ids).eq('status', 'published'); if (error) throw error; return data || [];
}
export async function listCategories() {
  const { data, error } = await sb.from('categories').select('*').eq('is_active', true).order('sort_order'); if (error) throw error; return data || [];
}

export function productCard(p) {
  const stock = stockOf(p); const sale = p.sale_price != null && p.sale_price < p.price;
  const href = `/product?slug=${encodeURIComponent(p.slug)}`;
  const simple = !(p.variants || []).length;
  return `<article class="card product">
    <a class="pimg" href="${href}" aria-label="${esc(p.name)}">
      <img src="${imgOf(p)}" alt="${esc(p.name)}" loading="lazy" width="400" height="400">
      ${sale ? '<span class="badge sale">Promo</span>' : ''}
    </a>
    <div class="pbody">
      <h3><a href="${href}">${esc(p.name)}</a></h3>
      <p class="price">${sale ? `<s>${fmtPrice(p.price)}</s>` : ''}<strong>${fmtPrice(priceOf(p))}</strong></p>
      <p class="stock ${stock > 0 ? 'in' : 'out'}">${stock > 0 ? 'En stock' : 'Rupture de stock'}</p>
      <div class="row">
        ${stock > 0 && simple ? `<button class="btn primary" data-add="${p.id}" data-max="${stock}">Ajouter au panier</button>` : ''}
        <a class="btn ghost" href="${href}">Voir détails</a>
      </div>
    </div></article>`;
}
export function bindAddButtons(root = document) {
  root.querySelectorAll('[data-add]').forEach((b) => { if (b.dataset.bound) return; b.dataset.bound = 1; b.addEventListener('click', () => addItem(b.dataset.add, 1, null, +b.dataset.max || 99)); });
}
