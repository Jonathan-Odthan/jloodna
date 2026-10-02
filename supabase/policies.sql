-- JLOODNA — Row Level Security + Storage. Exécuter APRÈS schema.sql.
do $$ declare t text; begin
  foreach t in array array['profiles','admin_roles','admin_permissions','categories','products','product_images','inventory','inventory_movements','addresses','coupons','orders','order_items','cart_items','notifications','reviews','messages','newsletter','audit_logs','settings'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('alter table public.%I force row level security', t);
  end loop; end $$;

-- Nettoyage (idempotent)
do $$ declare r record; begin
  for r in select schemaname, tablename, policyname from pg_policies where schemaname = 'public' loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop; end $$;

-- profiles : chacun voit/modifie le sien ; le staff autorisé lit tout
create policy profiles_select on public.profiles for select to authenticated using (id = auth.uid() or public.has_perm('customers.read'));
create policy profiles_update on public.profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- admin_roles / permissions : lecture de son propre rôle ; gestion réservée au SUPER_ADMIN
create policy roles_select on public.admin_roles for select to authenticated using (user_id = auth.uid() or public.current_role_name() = 'SUPER_ADMIN');
create policy roles_write on public.admin_roles for all to authenticated using (public.current_role_name() = 'SUPER_ADMIN') with check (public.current_role_name() = 'SUPER_ADMIN');
create policy perms_select on public.admin_permissions for select to authenticated using (public.is_admin());
create policy perms_write on public.admin_permissions for all to authenticated using (public.current_role_name() = 'SUPER_ADMIN') with check (public.current_role_name() = 'SUPER_ADMIN');

-- catalogue : lecture publique des éléments actifs ; écriture par permission
create policy categories_read on public.categories for select to anon, authenticated using (is_active or public.has_perm('categories.write'));
create policy categories_write on public.categories for all to authenticated using (public.has_perm('categories.write')) with check (public.has_perm('categories.write'));
create policy products_read on public.products for select to anon, authenticated using (status = 'published' or public.has_perm('products.write'));
create policy products_write on public.products for all to authenticated using (public.has_perm('products.write')) with check (public.has_perm('products.write'));
create policy pimages_read on public.product_images for select to anon, authenticated
  using (exists (select 1 from public.products p where p.id = product_id and (p.status = 'published' or public.has_perm('products.write'))));
create policy pimages_write on public.product_images for all to authenticated using (public.has_perm('products.write')) with check (public.has_perm('products.write'));

-- stock : lecture publique (disponibilité), écriture UNIQUEMENT via RPC admin_set_stock / create_order
create policy inventory_read on public.inventory for select to anon, authenticated
  using (exists (select 1 from public.products p where p.id = product_id and (p.status = 'published' or public.has_perm('products.write'))));
create policy inv_mov_read on public.inventory_movements for select to authenticated using (public.has_perm('inventory.write'));

-- adresses : privées
create policy addresses_all on public.addresses for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- coupons : jamais lisibles par les clients (validation via RPC)
create policy coupons_admin on public.coupons for all to authenticated using (public.has_perm('coupons.write')) with check (public.has_perm('coupons.write'));

-- commandes : le client lit les siennes ; création UNIQUEMENT via RPC ; statut via RPC set_order_status
create policy orders_select on public.orders for select to authenticated using (user_id = auth.uid() or public.has_perm('orders.write') or public.has_perm('customers.read'));
create policy order_items_select on public.order_items for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id and (o.user_id = auth.uid() or public.has_perm('orders.write') or public.has_perm('customers.read'))));
create policy orders_admin_update on public.orders for update to authenticated using (public.has_perm('orders.write')) with check (public.has_perm('orders.write'));

-- panier synchronisé : privé
create policy cart_all on public.cart_items for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- notifications : chacun lit/met à jour/supprime les siennes ; création uniquement par fonctions serveur
create policy notif_select on public.notifications for select to authenticated using (user_id = auth.uid());
create policy notif_update on public.notifications for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy notif_delete on public.notifications for delete to authenticated using (user_id = auth.uid());

-- avis : lecture publique des visibles ; un avis par client connecté
create policy reviews_read on public.reviews for select to anon, authenticated using (is_visible or public.has_perm('products.write'));
create policy reviews_insert on public.reviews for insert to authenticated with check (user_id = auth.uid() and is_visible);
create policy reviews_admin on public.reviews for update to authenticated using (public.has_perm('products.write')) with check (public.has_perm('products.write'));
create policy reviews_delete on public.reviews for delete to authenticated using (user_id = auth.uid() or public.has_perm('products.write'));

-- messages de contact / newsletter : insertion publique, lecture staff
create policy messages_insert on public.messages for insert to anon, authenticated with check (true);
create policy messages_admin on public.messages for select to authenticated using (public.has_perm('messages.write'));
create policy messages_update on public.messages for update to authenticated using (public.has_perm('messages.write')) with check (public.has_perm('messages.write'));
create policy newsletter_insert on public.newsletter for insert to anon, authenticated with check (true);
create policy newsletter_admin on public.newsletter for select to authenticated using (public.is_admin());

-- audit : lecture seule pour ceux qui ont audit.read ; aucune écriture directe
create policy audit_read on public.audit_logs for select to authenticated using (public.has_perm('audit.read'));

-- réglages : lecture publique des clés non sensibles ; écriture par permission
create policy settings_read on public.settings for select to anon, authenticated using (key in ('store','shipping','payment_methods') or public.has_perm('settings.write'));
create policy settings_write on public.settings for all to authenticated using (public.has_perm('settings.write')) with check (public.has_perm('settings.write'));

-- Droits de table minimaux (RLS fait le reste)
revoke all on all tables in schema public from anon, authenticated;
grant select on public.categories, public.products, public.product_images, public.inventory, public.reviews, public.settings to anon;
grant insert on public.messages, public.newsletter to anon;
grant select, insert, update, delete on public.categories, public.products, public.product_images, public.coupons, public.admin_roles, public.admin_permissions, public.settings, public.addresses, public.cart_items, public.reviews to authenticated;
grant select on public.inventory, public.inventory_movements, public.order_items, public.audit_logs, public.newsletter to authenticated;
grant select, update on public.orders, public.messages, public.profiles to authenticated;
grant insert on public.messages, public.newsletter to authenticated;
grant select, update, delete on public.notifications to authenticated;
revoke update on public.orders from authenticated;
grant update (payment_status) on public.orders to authenticated;
revoke update on public.profiles from authenticated;
grant update (first_name, last_name, phone) on public.profiles to authenticated;
revoke update on public.notifications from authenticated;
grant update (is_read) on public.notifications to authenticated;

-- ========== Storage : bucket public product-images ==========
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-images', 'product-images', true, 5242880, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = true, file_size_limit = 5242880, allowed_mime_types = array['image/jpeg','image/png','image/webp'];

drop policy if exists "pi_read" on storage.objects;
drop policy if exists "pi_insert" on storage.objects;
drop policy if exists "pi_update" on storage.objects;
drop policy if exists "pi_delete" on storage.objects;
create policy "pi_read" on storage.objects for select using (bucket_id = 'product-images');
create policy "pi_insert" on storage.objects for insert to authenticated with check (bucket_id = 'product-images' and (public.has_perm('products.write') or public.has_perm('categories.write')));
create policy "pi_update" on storage.objects for update to authenticated using (bucket_id = 'product-images' and public.has_perm('products.write'));
create policy "pi_delete" on storage.objects for delete to authenticated using (bucket_id = 'product-images' and public.has_perm('products.write'));
