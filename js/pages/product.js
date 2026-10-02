import { initLayout } from '../layout.js';
import { sb, SITE_URL } from '../supabase.js';
import { getProduct, listProducts, productCard, bindAddButtons, imgOf, stockOf, priceOf } from '../products.js';
import { addItem } from '../cart.js';
import { getUser } from '../auth.js';
import { $, esc, fmtPrice, fmtDate, param, safeUrl, emptyState, errorState, toast, friendlyError, setLoading } from '../utils.js';
import { subscribe } from '../realtime.js';

initLayout();
const root = $('#pp');
(async () => {
  if (!sb) return;
  const slug = param('slug');
  try {
    const p = slug ? await getProduct(slug) : null;
    if (!p) { root.innerHTML = emptyState('Ce produit est introuvable.', '<a class="btn primary" href="/shop">Retour à la boutique</a>'); return; }
    render(p); reviews(p); similar(p); seo(p);
  } catch { root.innerHTML = errorState(); }
})();

function render(p) {
  let stock = stockOf(p);
  const imgs = [...(p.product_images || [])].sort((a, b) => a.sort_order - b.sort_order).map((i) => ({ ...i, url: safeUrl(i.url) })).filter((i) => i.url);
  if (!imgs.length) imgs.push({ url: '/assets/icons/icon-512.png', alt: p.name });
  const sale = p.sale_price != null && p.sale_price < p.price;
  document.title = `${p.name} — JLOODNA`;
  $('#crumbs').innerHTML = `<a href="/">Accueil</a> / <a href="/shop">Boutique</a>${p.categories ? ` / <a href="/shop?category=${esc(p.category_id)}">${esc(p.categories.name)}</a>` : ''} / <span>${esc(p.name)}</span>`;
  const variants = Array.isArray(p.variants) ? p.variants : [];
  root.innerHTML = `<div class="pp">
  <div class="gallery"><div class="main"><img id="main-img" src="${imgs[0].url}" alt="${esc(imgs[0].alt || p.name)}" width="700" height="700"></div>
    ${imgs.length > 1 ? `<div class="thumbs">${imgs.map((i, n) => `<button data-i="${n}" aria-label="Image ${n + 1}" ${n === 0 ? 'aria-current="true"' : ''}><img src="${i.url}" alt="" loading="lazy"></button>`).join('')}</div>` : ''}</div>
  <div><h1 style="font-size:1.8rem">${esc(p.name)}</h1>
    <p class="price">${sale ? `<s>${fmtPrice(p.price)}</s>` : ''}<strong>${fmtPrice(priceOf(p))}</strong></p>
    <p class="stock" id="stock"></p>
    ${p.sku ? `<p class="muted">SKU : ${esc(p.sku)}</p>` : ''}
    <div id="variants">${variants.map((v, vi) => `<fieldset style="border:0;padding:0;margin:0 0 12px"><legend style="font-weight:600;margin-bottom:6px">${esc(v.name)}</legend><div class="opt">${(v.options || []).map((o, oi) => `<label><input type="radio" name="v${vi}" value="${esc(o)}" data-vname="${esc(v.name)}" ${oi === 0 ? 'checked' : ''}><span>${esc(o)}</span></label>`).join('')}</div></fieldset>`).join('')}</div>
    <div class="field"><label for="qty">Quantité</label><div class="qty"><button type="button" id="q-" aria-label="Moins">−</button><input id="qty" type="number" value="1" min="1" max="99" inputmode="numeric"><button type="button" id="q+" aria-label="Plus">+</button></div></div>
    <div class="row"><button class="btn primary" id="add">Ajouter au panier</button><button class="btn dark" id="buy">Acheter maintenant</button></div>
    <div class="prose" style="padding-top:20px;white-space:pre-line">${esc(p.description || '')}</div></div></div>`;
  const q = $('#qty'); const clamp = () => { q.value = Math.max(1, Math.min(Math.max(stock, 1), +q.value || 1)); };
  const refreshStock = () => {
    const s = $('#stock'); s.className = `stock ${stock > 0 ? 'in' : 'out'}`;
    s.textContent = stock > 0 ? (stock <= 5 ? `Plus que ${stock} en stock` : 'En stock') : 'Rupture de stock';
    $('#add').disabled = $('#buy').disabled = stock <= 0; if (stock <= 0) $('#add').textContent = 'Rupture de stock'; else $('#add').textContent = 'Ajouter au panier';
    clamp();
  };
  refreshStock();
  $('#q-').onclick = () => { q.value = +q.value - 1; clamp(); }; $('#q+').onclick = () => { q.value = +q.value + 1; clamp(); }; q.onchange = clamp;
  root.querySelectorAll('.thumbs button').forEach((b) => (b.onclick = () => { const i = imgs[+b.dataset.i]; $('#main-img').src = i.url; root.querySelectorAll('.thumbs button').forEach((x) => x.removeAttribute('aria-current')); b.setAttribute('aria-current', 'true'); }));
  const variant = () => { const v = {}; root.querySelectorAll('#variants input:checked').forEach((i) => (v[i.dataset.vname] = i.value)); return Object.keys(v).length ? v : null; };
  $('#add').onclick = () => stock > 0 && addItem(p.id, +q.value, variant(), stock);
  $('#buy').onclick = () => { if (stock <= 0) return; addItem(p.id, +q.value, variant(), stock); location.href = '/checkout'; };
  // Temps réel : le stock se met à jour sans recharger.
  subscribe(`inv-${p.id}`, { event: 'UPDATE', table: 'inventory', filter: `product_id=eq.${p.id}` }, (e) => { stock = e.new.quantity; refreshStock(); });
}

async function reviews(p) {
  $('#reviews-sec').hidden = false;
  const { data } = await sb.from('reviews').select('author_name, rating, comment, created_at').eq('product_id', p.id).eq('is_visible', true).order('created_at', { ascending: false }).limit(30);
  const avg = data?.length ? data.reduce((s, r) => s + r.rating, 0) / data.length : 0;
  $('#reviews').innerHTML = data?.length ? `<p><span class="stars">${'★'.repeat(Math.round(avg))}${'☆'.repeat(5 - Math.round(avg))}</span> ${avg.toFixed(1)} / 5 (${data.length} avis)</p>` + data.map((r) => `<div class="review"><span class="stars">${'★'.repeat(r.rating)}${'☆'.repeat(5 - r.rating)}</span> <strong>${esc(r.author_name)}</strong> <time class="muted">${fmtDate(r.created_at)}</time><p>${esc(r.comment || '')}</p></div>`).join('') : '<p class="muted">Aucun avis pour le moment.</p>';
  const u = await getUser();
  $('#review-form').innerHTML = u ? `<form id="rf" style="max-width:520px;margin-top:12px"><h3>Donner votre avis</h3><div class="field"><label for="rt">Note</label><select id="rt"><option>5</option><option>4</option><option>3</option><option>2</option><option>1</option></select></div><div class="field"><label for="rc">Commentaire</label><textarea id="rc" maxlength="1000"></textarea></div><button class="btn primary" id="rb">Publier mon avis</button></form>` : '<p><a href="/login?next=' + encodeURIComponent(location.pathname + location.search) + '">Connectez-vous</a> pour donner votre avis.</p>';
  $('#rf')?.addEventListener('submit', async (e) => {
    e.preventDefault(); const b = $('#rb'); setLoading(b, true);
    const { data: prof } = await sb.from('profiles').select('first_name').eq('id', u.id).maybeSingle();
    const { error } = await sb.from('reviews').insert({ product_id: p.id, user_id: u.id, author_name: prof?.first_name || 'Client', rating: +$('#rt').value, comment: $('#rc').value.trim() || null });
    setLoading(b, false);
    if (error) toast(String(error.message).includes('duplicate') ? 'Vous avez déjà donné votre avis sur ce produit.' : friendlyError(error), 'err'); else { toast('Merci pour votre avis !'); reviews(p); }
  });
}
async function similar(p) {
  if (!p.category_id) return;
  const { items } = await listProducts({ category: p.category_id, exclude: p.id, limit: 4 }).catch(() => ({ items: [] }));
  if (!items.length) return; $('#similar-sec').hidden = false; $('#similar').innerHTML = items.map(productCard).join(''); bindAddButtons($('#similar'));
}
function seo(p) {
  const s = document.createElement('script'); s.type = 'application/ld+json';
  const url = `${SITE_URL}/product?slug=${encodeURIComponent(p.slug)}`;
  s.textContent = JSON.stringify([
    { '@context': 'https://schema.org', '@type': 'Product', name: p.name, description: (p.description || '').slice(0, 300), sku: p.sku || undefined, image: [imgOf(p)], offers: { '@type': 'Offer', url, priceCurrency: 'HTG', price: priceOf(p), availability: stockOf(p) > 0 ? 'https://schema.org/InStock' : 'https://schema.org/OutOfStock' } },
    { '@context': 'https://schema.org', '@type': 'BreadcrumbList', itemListElement: [{ '@type': 'ListItem', position: 1, name: 'Accueil', item: SITE_URL + '/' }, { '@type': 'ListItem', position: 2, name: 'Boutique', item: SITE_URL + '/shop' }, { '@type': 'ListItem', position: 3, name: p.name, item: url }] },
  ]);
  document.head.append(s);
  const d = document.querySelector('meta[name=description]'); if (d) d.content = `${p.name} — ${(p.description || 'Disponible chez JLOODNA').slice(0, 140)}`;
  const c = document.querySelector('link[rel=canonical]'); if (c) c.href = url;
}
