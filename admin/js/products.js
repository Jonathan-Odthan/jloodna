import { sb, bucketUrl } from '/js/supabase.js';
import { $, $$, esc, fmtPrice, slugify, setLoading, toast, friendlyError, validateImage, debounce } from '/js/utils.js';
import { table, confirmBox } from './ui.js';
import { imgOf, stockOf } from '/js/products.js';
import { ctx } from './admin.js';

const SEL = '*, product_images(id, url, alt, sort_order), inventory(quantity, low_stock_threshold), categories(name)';
export async function render(el, [id]) { return id ? form(el, id) : list(el); }

async function list(el) {
  el.innerHTML = `<h1>Produits</h1><div class="toolbar"><input id="q" type="search" placeholder="Rechercher (nom, SKU)" aria-label="Rechercher"><select id="st" aria-label="Statut"><option value="">Tous les statuts</option><option value="published">Publiés</option><option value="draft">Brouillons</option><option value="disabled">Désactivés</option></select><a class="btn primary" href="#products/new">Ajouter un produit</a></div><div id="t"></div>`;
  const load = async () => {
    const q = $('#q').value.replace(/[%,()]/g, ' ').trim(); let query = sb.from('products').select(SEL).order('created_at', { ascending: false }).limit(200);
    if ($('#st').value) query = query.eq('status', $('#st').value); if (q) query = query.or(`name.ilike.%${q}%,sku.ilike.%${q}%`);
    const { data, error } = await query; if (error) throw error;
    $('#t').innerHTML = table(['', 'Nom', 'SKU', 'Prix', 'Stock', 'Statut', 'Actions'], data.map((p) => `<tr><td><img class="thumb" src="${imgOf(p)}" alt=""></td><td class="wrap-t">${esc(p.name)}${p.is_featured ? ' ★' : ''}</td><td>${esc(p.sku || '—')}</td><td>${p.sale_price != null ? `<s>${fmtPrice(p.price)}</s> ` : ''}${fmtPrice(p.sale_price ?? p.price)}</td><td>${stockOf(p)}</td><td>${{ published: 'Publié', draft: 'Brouillon', disabled: 'Désactivé' }[p.status]}</td>
      <td><a class="btn ghost sm" href="#products/${p.id}">Modifier</a> <button class="btn ghost sm" data-st="${p.id}" data-to="${p.status === 'published' ? 'disabled' : 'published'}">${p.status === 'published' ? 'Désactiver' : 'Publier'}</button> <button class="btn danger sm" data-del="${p.id}">Supprimer</button></td></tr>`));
    $$('[data-st]').forEach((b) => (b.onclick = async () => { const { error } = await sb.from('products').update({ status: b.dataset.to }).eq('id', b.dataset.st); toast(error ? friendlyError(error) : 'Produit mis à jour.', error ? 'err' : 'ok'); load(); }));
    $$('[data-del]').forEach((b) => (b.onclick = async () => { if (!(await confirmBox('Supprimer définitivement ce produit ?'))) return; const { error } = await sb.from('products').delete().eq('id', b.dataset.del); toast(error ? friendlyError(error) : 'Produit supprimé.', error ? 'err' : 'ok'); load(); }));
  };
  $('#q').oninput = debounce(load, 300); $('#st').onchange = load; await load();
}

async function form(el, id) {
  const isNew = id === 'new'; let p = { name: '', slug: '', description: '', price: '', sale_price: '', category_id: '', sku: '', variants: [], weight_grams: '', status: 'draft', is_featured: false, is_on_sale: false, product_images: [], inventory: { quantity: 0, low_stock_threshold: 5 } };
  if (!isNew) { const { data, error } = await sb.from('products').select(SEL).eq('id', id).maybeSingle(); if (error || !data) { el.innerHTML = '<p>Produit introuvable.</p>'; return; } p = data; if (Array.isArray(p.inventory)) p.inventory = p.inventory[0] || { quantity: 0, low_stock_threshold: 5 }; }
  const { data: cats } = await sb.from('categories').select('id, name').order('name');
  let images = [...p.product_images].sort((a, b) => a.sort_order - b.sort_order).map((i) => ({ url: i.url, alt: i.alt })); const removedUrls = [];
  let variants = (p.variants || []).map((v) => ({ name: v.name, options: (v.options || []).join(', ') }));
  el.innerHTML = `<p><a href="#products">← Produits</a></p><h1>${isNew ? 'Ajouter un produit' : 'Modifier le produit'}</h1>
  <form id="pf" class="panel-box" novalidate style="max-width:760px">
    <div class="field"><label for="name">Nom</label><input id="name" value="${esc(p.name)}" required maxlength="200"></div>
    <div class="two"><div class="field"><label for="slug">Slug (adresse du produit)</label><input id="slug" value="${esc(p.slug)}" required></div><div class="field"><label for="sku">SKU</label><input id="sku" value="${esc(p.sku || '')}"></div></div>
    <div class="field"><label for="description">Description</label><textarea id="description">${esc(p.description || '')}</textarea></div>
    <div class="two"><div class="field"><label for="price">Prix (G)</label><input id="price" type="number" min="0" step="0.01" inputmode="decimal" value="${esc(p.price)}" required></div><div class="field"><label for="sale_price">Prix promotionnel (G)</label><input id="sale_price" type="number" min="0" step="0.01" inputmode="decimal" value="${esc(p.sale_price ?? '')}"></div></div>
    <div class="two"><div class="field"><label for="category_id">Catégorie</label><select id="category_id"><option value="">Aucune</option>${(cats || []).map((c) => `<option value="${c.id}" ${c.id === p.category_id ? 'selected' : ''}>${esc(c.name)}</option>`).join('')}</select></div><div class="field"><label for="weight">Poids (g)</label><input id="weight" type="number" min="0" inputmode="numeric" value="${esc(p.weight_grams ?? '')}"></div></div>
    <div class="two"><div class="field"><label for="stock">Stock disponible</label><input id="stock" type="number" min="0" inputmode="numeric" value="${p.inventory.quantity}" ${ctx.can('inventory.write') ? '' : 'disabled'}></div><div class="field"><label for="thr">Alerte stock faible à</label><input id="thr" type="number" min="0" inputmode="numeric" value="${p.inventory.low_stock_threshold}" ${ctx.can('inventory.write') ? '' : 'disabled'}></div></div>
    <div class="field"><label for="status">Statut</label><select id="status"><option value="draft">Brouillon</option><option value="published">Publié</option><option value="disabled">Désactivé</option></select></div>
    <label class="chk"><input type="checkbox" id="is_featured" ${p.is_featured ? 'checked' : ''}> Produit vedette (recommandé)</label>
    <label class="chk" style="margin-bottom:14px"><input type="checkbox" id="is_on_sale" ${p.is_on_sale ? 'checked' : ''}> Produit en promotion</label>
    <div class="field"><label>Images (JPG, PNG ou WebP, 5 Mo max)</label><div class="imgs" id="imgs"></div><input id="file" type="file" accept="image/jpeg,image/png,image/webp" multiple></div>
    <div class="field"><label>Variantes (ex. Taille : S, M, L)</label><div id="vars"></div><button type="button" class="btn ghost sm" id="addv">Ajouter une variante</button></div>
    <p class="err-msg" id="err" role="alert"></p>
    <div class="row"><button class="btn primary" id="save">Enregistrer</button><a class="btn ghost" href="#products">Annuler</a></div></form>`;
  $('#status').value = p.status;
  const drawImgs = () => { $('#imgs').innerHTML = images.map((im, i) => `<div class="im"><img src="${esc(im.url)}" alt="Image ${i + 1}">${i === 0 ? '' : `<button type="button" data-first="${i}" style="right:auto;left:-6px;background:#000" aria-label="Mettre en premier">↑</button>`}<button type="button" data-rm="${i}" aria-label="Retirer l’image">×</button></div>`).join(''); $$('[data-rm]').forEach((b) => (b.onclick = () => { const [r] = images.splice(+b.dataset.rm, 1); removedUrls.push(r.url); drawImgs(); })); $$('[data-first]').forEach((b) => (b.onclick = () => { const [r] = images.splice(+b.dataset.first, 1); images.unshift(r); drawImgs(); })); };
  const drawVars = () => { $('#vars').innerHTML = variants.map((v, i) => `<div class="vrow"><input data-vn="${i}" placeholder="Nom (Taille)" value="${esc(v.name)}" aria-label="Nom de la variante"><input data-vo="${i}" placeholder="Options séparées par des virgules" value="${esc(v.options)}" aria-label="Options"><button type="button" class="btn danger sm" data-vd="${i}">×</button></div>`).join(''); $$('[data-vn]').forEach((i) => (i.oninput = () => (variants[+i.dataset.vn].name = i.value))); $$('[data-vo]').forEach((i) => (i.oninput = () => (variants[+i.dataset.vo].options = i.value))); $$('[data-vd]').forEach((b) => (b.onclick = () => { variants.splice(+b.dataset.vd, 1); drawVars(); })); };
  drawImgs(); drawVars();
  $('#addv').onclick = () => { variants.push({ name: '', options: '' }); drawVars(); };
  if (isNew) $('#name').oninput = () => { if (!$('#slug').dataset.touched) $('#slug').value = slugify($('#name').value); }; $('#slug').oninput = () => ($('#slug').dataset.touched = 1);
  $('#file').onchange = async (e) => {
    for (const f of e.target.files) {
      const bad = validateImage(f); if (bad) { toast(`${f.name} : ${bad}`, 'err'); continue; }
      const ext = { 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' }[f.type]; const path = `products/${crypto.randomUUID()}.${ext}`;
      const { error } = await sb.storage.from('product-images').upload(path, f, { contentType: f.type, cacheControl: '31536000' });
      if (error) toast(friendlyError(error), 'err'); else { images.push({ url: bucketUrl(path), alt: $('#name').value }); drawImgs(); }
    } e.target.value = '';
  };
  $('#pf').onsubmit = async (e) => {
    e.preventDefault(); const err = $('#err'); err.textContent = '';
    const num = (s) => (s === '' ? null : Number(s));
    const row = { name: $('#name').value.trim(), slug: slugify($('#slug').value || $('#name').value), description: $('#description').value.trim() || null, price: num($('#price').value), sale_price: num($('#sale_price').value), category_id: $('#category_id').value || null, sku: $('#sku').value.trim() || null, weight_grams: num($('#weight').value), status: $('#status').value, is_featured: $('#is_featured').checked, is_on_sale: $('#is_on_sale').checked,
      variants: variants.filter((v) => v.name.trim()).map((v) => ({ name: v.name.trim(), options: v.options.split(',').map((o) => o.trim()).filter(Boolean) })) };
    if (row.name.length < 2 || row.price == null || row.price < 0 || !row.slug) { err.textContent = 'Renseignez au moins un nom, un slug et un prix valide.'; return; }
    if (row.sale_price != null && row.sale_price >= row.price) { err.textContent = 'Le prix promotionnel doit être inférieur au prix normal.'; return; }
    if (row.sale_price == null) row.is_on_sale = false; else row.is_on_sale = true;
    setLoading($('#save'), true, 'Enregistrement…');
    try {
      let pid = id;
      if (isNew) { const { data, error } = await sb.from('products').insert(row).select('id').single(); if (error) throw error; pid = data.id; }
      else { const { error } = await sb.from('products').update(row).eq('id', id); if (error) throw error; }
      await sb.from('product_images').delete().eq('product_id', pid);
      if (images.length) { const { error } = await sb.from('product_images').insert(images.map((im, i) => ({ product_id: pid, url: im.url, alt: im.alt || row.name, sort_order: i }))); if (error) throw error; }
      if (ctx.can('inventory.write')) { const { error } = await sb.rpc('admin_set_stock', { p_product_id: pid, p_quantity: Math.max(0, parseInt($('#stock').value || '0', 10)), p_reason: isNew ? 'Stock initial' : 'Modification fiche produit', p_threshold: Math.max(0, parseInt($('#thr').value || '5', 10)) }); if (error) throw error; }
      const paths = removedUrls.filter((u) => !images.some((i) => i.url === u)).map((u) => u.split('/product-images/')[1]).filter(Boolean); if (paths.length) sb.storage.from('product-images').remove(paths);
      toast(isNew ? 'Produit ajouté.' : 'Produit enregistré.'); location.hash = '#products';
    } catch (ex) { err.textContent = friendlyError(ex); } finally { setLoading($('#save'), false); }
  };
}
