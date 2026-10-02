-- JLOODNA — données de démonstration (OPTIONNEL). Tout est marqué sku 'DEMO-%' / slug 'demo-%' pour être supprimé facilement :
--   delete from public.products where sku like 'DEMO-%';  delete from public.categories where slug like 'demo-%';
insert into public.categories(name, slug, sort_order) values
 ('Électronique','demo-electronique',1),('Maison','demo-maison',2),('Mode','demo-mode',3),('Beauté','demo-beaute',4)
on conflict (slug) do nothing;

with c as (select id, slug from public.categories where slug like 'demo-%')
insert into public.products(name, slug, description, price, sale_price, category_id, sku, status, is_featured, is_on_sale, variants)
select v.name, v.slug, v.descr, v.price, v.sale, (select id from c where c.slug = v.cat), v.sku, 'published', v.feat, v.sale is not null, v.variants::jsonb
from (values
 ('Écouteurs sans fil','demo-ecouteurs','Écouteurs Bluetooth avec boîtier de charge.',2500,1990,'demo-electronique','DEMO-001',true,'[{"name":"Couleur","options":["Noir","Blanc"]}]'),
 ('Lampe LED rechargeable','demo-lampe-led','Lampe LED rechargeable USB, idéale pendant les coupures de courant.',1200,null,'demo-maison','DEMO-002',true,'[]'),
 ('T-shirt coton','demo-tshirt','T-shirt 100 % coton, coupe classique.',900,750,'demo-mode','DEMO-003',false,'[{"name":"Taille","options":["S","M","L","XL"]}]'),
 ('Crème hydratante','demo-creme','Crème hydratante visage et corps, 200 ml.',650,null,'demo-beaute','DEMO-004',false,'[]')
) as v(name, slug, descr, price, sale, cat, sku, feat, variants)
on conflict (slug) do nothing;

insert into public.inventory(product_id, quantity, low_stock_threshold)
select id, 20, 5 from public.products where sku like 'DEMO-%' on conflict (product_id) do nothing;
