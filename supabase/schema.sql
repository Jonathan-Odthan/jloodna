-- JLOODNA — schéma PostgreSQL (Supabase). Exécuter EN PREMIER, puis policies.sql, puis seed.sql (optionnel).
create extension if not exists "pgcrypto";

-- ========== Tables ==========
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  first_name text, last_name text, email text, phone text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists public.admin_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('SUPER_ADMIN','ADMIN','MANAGER','EDITOR','SUPPORT')),
  created_at timestamptz not null default now()
);
create table if not exists public.admin_permissions (
  role text not null check (role in ('SUPER_ADMIN','ADMIN','MANAGER','EDITOR','SUPPORT')),
  permission text not null,
  primary key (role, permission)
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null, slug text not null unique,
  image_url text, parent_id uuid references public.categories(id) on delete set null,
  is_active boolean not null default true, sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 200),
  slug text not null unique,
  description text,
  price numeric(12,2) not null check (price >= 0),
  sale_price numeric(12,2) check (sale_price is null or (sale_price >= 0 and sale_price < price)),
  category_id uuid references public.categories(id) on delete set null,
  sku text unique,
  variants jsonb not null default '[]'::jsonb,
  weight_grams int check (weight_grams is null or weight_grams >= 0),
  status text not null default 'draft' check (status in ('draft','published','disabled')),
  is_featured boolean not null default false,
  is_on_sale boolean not null default false,
  sold_count int not null default 0,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists products_status_idx on public.products(status);
create index if not exists products_category_idx on public.products(category_id);
create index if not exists products_name_idx on public.products using gin (to_tsvector('simple', name));

create table if not exists public.product_images (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  url text not null, alt text, sort_order int not null default 0,
  created_at timestamptz not null default now()
);
create index if not exists product_images_product_idx on public.product_images(product_id);

create table if not exists public.inventory (
  product_id uuid primary key references public.products(id) on delete cascade,
  quantity int not null default 0 check (quantity >= 0),
  low_stock_threshold int not null default 5 check (low_stock_threshold >= 0),
  updated_at timestamptz not null default now()
);
create table if not exists public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  delta int not null, quantity_after int not null,
  reason text not null, order_id uuid, created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists inv_mov_product_idx on public.inventory_movements(product_id, created_at desc);

create table if not exists public.addresses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  label text, full_name text not null, phone text not null,
  address text not null, city text not null, department text not null, notes text,
  is_default boolean not null default false, created_at timestamptz not null default now()
);

create table if not exists public.coupons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique, type text not null check (type in ('percent','fixed')),
  value numeric(12,2) not null check (value > 0),
  min_subtotal numeric(12,2) not null default 0, max_uses int, used_count int not null default 0,
  expires_at timestamptz, is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create sequence if not exists public.order_number_seq start 1;
create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique,
  user_id uuid not null references auth.users(id) on delete restrict,
  status text not null default 'new' check (status in ('new','confirmed','preparing','shipped','out_for_delivery','delivered','cancelled')),
  payment_method text not null default 'cod',
  payment_status text not null default 'pending' check (payment_status in ('pending','paid','failed','refunded')),
  subtotal numeric(12,2) not null, shipping_fee numeric(12,2) not null default 0,
  discount numeric(12,2) not null default 0, total numeric(12,2) not null,
  coupon_code text, currency text not null default 'HTG',
  full_name text not null, phone text not null, email text not null,
  address text not null, city text not null, department text not null, notes text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists orders_user_idx on public.orders(user_id, created_at desc);
create index if not exists orders_status_idx on public.orders(status);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  name text not null, sku text, image_url text, variant jsonb,
  unit_price numeric(12,2) not null, quantity int not null check (quantity > 0)
);
create index if not exists order_items_order_idx on public.order_items(order_id);

create table if not exists public.cart_items (
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  variant_key text not null default '', variant jsonb,
  quantity int not null check (quantity > 0 and quantity <= 99),
  updated_at timestamptz not null default now(),
  primary key (user_id, product_id, variant_key)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  audience text not null default 'customer' check (audience in ('customer','admin')),
  type text not null, title text not null, body text, link text,
  is_read boolean not null default false, created_at timestamptz not null default now()
);
create index if not exists notifications_user_idx on public.notifications(user_id, created_at desc);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  author_name text not null, rating int not null check (rating between 1 and 5),
  comment text check (comment is null or char_length(comment) <= 1000),
  is_visible boolean not null default true, created_at timestamptz not null default now(),
  unique (product_id, user_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 120),
  email text not null check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  subject text, body text not null check (char_length(body) between 5 and 4000),
  is_read boolean not null default false, created_at timestamptz not null default now()
);

create table if not exists public.newsletter (
  email text primary key check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'), created_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  user_id uuid, user_email text, action text not null, entity text, entity_id text,
  details jsonb, created_at timestamptz not null default now()
);
create index if not exists audit_logs_created_idx on public.audit_logs(created_at desc);

create table if not exists public.settings (
  key text primary key, value jsonb not null, updated_at timestamptz not null default now()
);

-- ========== Fonctions de rôle ==========
create or replace function public.current_role_name() returns text
language sql stable security definer set search_path = public as $$
  select role from public.admin_roles where user_id = auth.uid()
$$;
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admin_roles where user_id = auth.uid())
$$;
create or replace function public.has_perm(p text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.admin_roles r
    where r.user_id = auth.uid()
      and (r.role = 'SUPER_ADMIN' or exists (select 1 from public.admin_permissions ap where ap.role = r.role and ap.permission = p))
  )
$$;
create or replace function public.admin_user_ids() returns setof uuid
language sql stable security definer set search_path = public as $$
  select user_id from public.admin_roles
$$;

-- ========== Utilitaires ==========
create or replace function public.touch_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;
do $$ declare t text; begin
  foreach t in array array['profiles','products','orders','inventory','settings'] loop
    execute format('drop trigger if exists trg_touch on public.%I; create trigger trg_touch before update on public.%I for each row execute function public.touch_updated_at()', t, t);
  end loop; end $$;

create or replace function public.notify_admins(p_type text, p_title text, p_body text, p_link text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications(user_id, audience, type, title, body, link)
  select user_id, 'admin', p_type, p_title, p_body, p_link from public.admin_roles;
end $$;
revoke all on function public.notify_admins(text,text,text,text) from public, anon, authenticated;

-- ========== Nouveau compte : profil + admin initial ==========
-- L'email admin initial est lu dans settings.bootstrap_admin_email. Le rôle n'est donné QUE si l'email est confirmé.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles(id, email, first_name, last_name, phone)
  values (new.id, new.email, left(new.raw_user_meta_data->>'first_name',80), left(new.raw_user_meta_data->>'last_name',80), left(new.raw_user_meta_data->>'phone',30))
  on conflict (id) do nothing;
  perform public.notify_admins('new_customer','Nouveau client', coalesce(new.email,''), '/admin/#customers');
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.grant_bootstrap_admin() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_email text;
begin
  select value #>> '{}' into v_email from public.settings where key = 'bootstrap_admin_email';
  if new.email_confirmed_at is not null and v_email is not null and lower(new.email) = lower(v_email)
     and not exists (select 1 from public.admin_roles where role = 'SUPER_ADMIN') then
    insert into public.admin_roles(user_id, role) values (new.id, 'SUPER_ADMIN') on conflict do nothing;
  end if;
  return new;
end $$;
drop trigger if exists on_auth_user_confirmed on auth.users;
create trigger on_auth_user_confirmed after insert or update of email_confirmed_at on auth.users
  for each row execute function public.grant_bootstrap_admin();

-- ========== Audit automatique ==========
create or replace function public.audit_row() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_row jsonb; v_old jsonb; v_email text;
begin
  if auth.uid() is null then return coalesce(new, old); end if; -- actions système (triggers/RPC internes) déjà tracées ailleurs
  -- Ignorer les mises à jour purement techniques (compteur de ventes, horodatage) : ce ne sont pas des actions admin.
  if tg_op = 'UPDATE' and tg_table_name = 'products' and (to_jsonb(new) - 'sold_count' - 'updated_at') = (to_jsonb(old) - 'sold_count' - 'updated_at') then return new; end if;
  if not public.is_admin() then return coalesce(new, old); end if;
  select email into v_email from auth.users where id = auth.uid();
  v_row := to_jsonb(coalesce(new, old));
  if tg_op = 'UPDATE' then v_old := to_jsonb(old); end if;
  insert into public.audit_logs(user_id, user_email, action, entity, entity_id, details)
  values (auth.uid(), v_email, lower(tg_op) || '_' || tg_table_name, tg_table_name, v_row->>'id',
          jsonb_build_object('name', coalesce(v_row->>'name', v_row->>'code', v_row->>'key', v_row->>'role'), 'before_status', v_old->>'status', 'after_status', v_row->>'status'));
  return coalesce(new, old);
end $$;
do $$ declare t text; begin
  foreach t in array array['products','categories','coupons','settings','admin_roles'] loop
    execute format('drop trigger if exists trg_audit on public.%I; create trigger trg_audit after insert or update or delete on public.%I for each row execute function public.audit_row()', t, t);
  end loop; end $$;

-- ========== Alertes stock ==========
create or replace function public.inventory_alert() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_name text;
begin
  if new.quantity < coalesce(old.quantity, new.quantity + 1) then
    select name into v_name from public.products where id = new.product_id;
    if new.quantity = 0 then
      perform public.notify_admins('out_of_stock','Produit en rupture', v_name || ' est en rupture de stock.', '/admin/#inventory');
    elsif new.quantity <= new.low_stock_threshold then
      perform public.notify_admins('low_stock','Stock faible', 'Attention : le produit ' || v_name || ' possède seulement ' || new.quantity || ' unité(s).', '/admin/#inventory');
    end if;
  end if;
  return new;
end $$;
drop trigger if exists trg_inventory_alert on public.inventory;
create trigger trg_inventory_alert after update on public.inventory for each row execute function public.inventory_alert();

-- ========== RPC : valider un coupon ==========
create or replace function public.validate_coupon(p_code text, p_subtotal numeric)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare c public.coupons; d numeric;
begin
  select * into c from public.coupons where upper(code) = upper(trim(p_code)) and is_active;
  if not found or (c.expires_at is not null and c.expires_at < now()) or (c.max_uses is not null and c.used_count >= c.max_uses) then
    return jsonb_build_object('valid', false, 'message', 'Code promo invalide ou expiré.');
  end if;
  if p_subtotal < c.min_subtotal then
    return jsonb_build_object('valid', false, 'message', 'Montant minimum non atteint pour ce code.');
  end if;
  d := case when c.type = 'percent' then round(p_subtotal * least(c.value,100) / 100, 2) else least(c.value, p_subtotal) end;
  return jsonb_build_object('valid', true, 'discount', d, 'code', c.code);
end $$;
grant execute on function public.validate_coupon(text, numeric) to authenticated;

-- ========== RPC : créer une commande (prix et stock calculés côté serveur) ==========
create or replace function public.create_order(p_items jsonb, p_shipping jsonb, p_coupon text default null, p_payment_method text default 'cod')
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid(); v_item jsonb; v_prod public.products; v_inv public.inventory;
  v_qty int; v_price numeric; v_subtotal numeric := 0; v_fee numeric := 0; v_discount numeric := 0;
  v_order_id uuid := gen_random_uuid(); v_number text; v_img text; v_cfg jsonb; v_cv jsonb; v_methods jsonb;
  v_free_over numeric;
begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) = 0 or jsonb_array_length(p_items) > 50 then raise exception 'CART_EMPTY'; end if;
  if char_length(coalesce(p_shipping->>'full_name','')) < 2 or char_length(coalesce(p_shipping->>'phone','')) < 6
     or char_length(coalesce(p_shipping->>'address','')) < 3 or char_length(coalesce(p_shipping->>'city','')) < 2
     or char_length(coalesce(p_shipping->>'department','')) < 2 or coalesce(p_shipping->>'email','') !~* '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'INVALID_SHIPPING';
  end if;
  select value into v_methods from public.settings where key = 'payment_methods';
  if v_methods is null or not (v_methods ? p_payment_method) or coalesce((v_methods->p_payment_method->>'enabled')::boolean, false) = false then
    raise exception 'PAYMENT_METHOD_UNAVAILABLE';
  end if;

  v_number := 'JLD-' || lpad(nextval('public.order_number_seq')::text, 6, '0');
  insert into public.orders(id, order_number, user_id, payment_method, subtotal, shipping_fee, discount, total, full_name, phone, email, address, city, department, notes)
  values (v_order_id, v_number, v_uid, p_payment_method, 0, 0, 0, 0,
          left(p_shipping->>'full_name',150), left(p_shipping->>'phone',30), left(p_shipping->>'email',200),
          left(p_shipping->>'address',300), left(p_shipping->>'city',100), left(p_shipping->>'department',100), left(p_shipping->>'notes',1000));

  for v_item in select * from jsonb_array_elements(p_items) loop
    v_qty := greatest(1, least(99, coalesce((v_item->>'quantity')::int, 1)));
    select * into v_prod from public.products where id = (v_item->>'product_id')::uuid and status = 'published' for update;
    if not found then raise exception 'PRODUCT_UNAVAILABLE'; end if;
    select * into v_inv from public.inventory where product_id = v_prod.id for update;
    if not found or v_inv.quantity < v_qty then raise exception 'OUT_OF_STOCK:%', v_prod.name; end if;
    v_price := coalesce(v_prod.sale_price, v_prod.price);
    v_subtotal := v_subtotal + v_price * v_qty;
    select url into v_img from public.product_images where product_id = v_prod.id order by sort_order limit 1;
    insert into public.order_items(order_id, product_id, name, sku, image_url, variant, unit_price, quantity)
    values (v_order_id, v_prod.id, v_prod.name, v_prod.sku, v_img, v_item->'variant', v_price, v_qty);
    update public.inventory set quantity = quantity - v_qty where product_id = v_prod.id;
    insert into public.inventory_movements(product_id, delta, quantity_after, reason, order_id, created_by)
    values (v_prod.id, -v_qty, v_inv.quantity - v_qty, 'Commande ' || v_number, v_order_id, v_uid);
    update public.products set sold_count = sold_count + v_qty where id = v_prod.id;
  end loop;

  select value into v_cfg from public.settings where key = 'shipping';
  v_fee := coalesce((v_cfg->>'flat_fee')::numeric, 0);
  v_free_over := (v_cfg->>'free_over')::numeric;
  if v_free_over is not null and v_free_over > 0 and v_subtotal >= v_free_over then v_fee := 0; end if;

  if p_coupon is not null and trim(p_coupon) <> '' then
    v_cv := public.validate_coupon(p_coupon, v_subtotal);
    if (v_cv->>'valid')::boolean then
      v_discount := (v_cv->>'discount')::numeric;
      update public.coupons set used_count = used_count + 1 where upper(code) = upper(v_cv->>'code');
    else raise exception 'COUPON_INVALID'; end if;
  end if;

  update public.orders set subtotal = v_subtotal, shipping_fee = v_fee, discount = v_discount,
         total = greatest(v_subtotal + v_fee - v_discount, 0), coupon_code = case when v_discount > 0 then upper(trim(p_coupon)) end
   where id = v_order_id;

  delete from public.cart_items where user_id = v_uid;
  insert into public.notifications(user_id, audience, type, title, body, link)
  values (v_uid, 'customer', 'order_new', 'Votre commande a été enregistrée', 'Commande ' || v_number || ' reçue.', '/orders.html');
  perform public.notify_admins('order_new', 'Nouvelle commande #' || v_number, 'Total : ' || (select total from public.orders where id = v_order_id), '/admin/#orders');
  return jsonb_build_object('id', v_order_id, 'order_number', v_number);
end $$;
grant execute on function public.create_order(jsonb, jsonb, text, text) to authenticated;

-- ========== RPC : changer le statut d'une commande (admin) ==========
create or replace function public.set_order_status(p_order_id uuid, p_status text)
returns void language plpgsql security definer set search_path = public as $$
declare o public.orders; v_title text; v_type text; v_email text; it record;
begin
  if not public.has_perm('orders.write') then raise exception 'FORBIDDEN'; end if;
  select * into o from public.orders where id = p_order_id for update;
  if not found then raise exception 'NOT_FOUND'; end if;
  if p_status not in ('new','confirmed','preparing','shipped','out_for_delivery','delivered','cancelled') then raise exception 'INVALID_STATUS'; end if;
  if o.status = p_status then return; end if;
  if p_status = 'cancelled' and o.status <> 'cancelled' then
    for it in select product_id, quantity from public.order_items where order_id = o.id and product_id is not null loop
      update public.inventory set quantity = quantity + it.quantity where product_id = it.product_id;
      insert into public.inventory_movements(product_id, delta, quantity_after, reason, order_id, created_by)
      select it.product_id, it.quantity, quantity, 'Annulation ' || o.order_number, o.id, auth.uid() from public.inventory where product_id = it.product_id;
    end loop;
  end if;
  update public.orders set status = p_status where id = o.id;
  v_title := case p_status
    when 'confirmed' then 'Votre commande a été confirmée.' when 'preparing' then 'Votre commande est en préparation.'
    when 'shipped' then 'Votre commande a été expédiée.' when 'out_for_delivery' then 'Votre commande est en cours de livraison.'
    when 'delivered' then 'Votre commande a été livrée.' when 'cancelled' then 'Votre commande a été annulée.' else 'Mise à jour de votre commande.' end;
  insert into public.notifications(user_id, audience, type, title, body, link)
  values (o.user_id, 'customer', 'order_' || p_status, v_title, 'Commande ' || o.order_number, '/orders.html');
  select email into v_email from auth.users where id = auth.uid();
  insert into public.audit_logs(user_id, user_email, action, entity, entity_id, details)
  values (auth.uid(), v_email, 'order_status_change', 'orders', o.id::text, jsonb_build_object('order_number', o.order_number, 'from', o.status, 'to', p_status));
end $$;
grant execute on function public.set_order_status(uuid, text) to authenticated;

-- ========== RPC : stock admin ==========
create or replace function public.admin_set_stock(p_product_id uuid, p_quantity int, p_reason text default 'Ajustement manuel', p_threshold int default null)
returns void language plpgsql security definer set search_path = public as $$
declare v_old int; v_email text;
begin
  if not public.has_perm('inventory.write') then raise exception 'FORBIDDEN'; end if;
  if p_quantity < 0 then raise exception 'INVALID_QUANTITY'; end if;
  select quantity into v_old from public.inventory where product_id = p_product_id;
  if not found then
    insert into public.inventory(product_id, quantity, low_stock_threshold) values (p_product_id, p_quantity, coalesce(p_threshold, 5)); v_old := 0;
  else
    update public.inventory set quantity = p_quantity, low_stock_threshold = coalesce(p_threshold, low_stock_threshold) where product_id = p_product_id;
  end if;
  if p_quantity <> v_old then
    insert into public.inventory_movements(product_id, delta, quantity_after, reason, created_by) values (p_product_id, p_quantity - v_old, p_quantity, left(p_reason,200), auth.uid());
    select email into v_email from auth.users where id = auth.uid();
    insert into public.audit_logs(user_id, user_email, action, entity, entity_id, details)
    values (auth.uid(), v_email, 'stock_change', 'inventory', p_product_id::text, jsonb_build_object('from', v_old, 'to', p_quantity, 'reason', p_reason));
  end if;
end $$;
grant execute on function public.admin_set_stock(uuid, int, text, int) to authenticated;

-- ========== RPC : journal de connexion admin ==========
create or replace function public.log_admin_login() returns void
language plpgsql security definer set search_path = public as $$
declare v_email text;
begin
  if not public.is_admin() then return; end if;
  select email into v_email from auth.users where id = auth.uid();
  insert into public.audit_logs(user_id, user_email, action, entity) values (auth.uid(), v_email, 'admin_login', 'auth');
end $$;
grant execute on function public.log_admin_login() to authenticated;

-- ========== RPC : stats dashboard ==========
create or replace function public.admin_stats() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'FORBIDDEN'; end if;
  return jsonb_build_object(
    'revenue', coalesce((select sum(total) from public.orders where status <> 'cancelled'),0),
    'orders', (select count(*) from public.orders),
    'pending', (select count(*) from public.orders where status in ('new','confirmed','preparing')),
    'products', (select count(*) from public.products),
    'out_of_stock', (select count(*) from public.inventory i join public.products p on p.id = i.product_id where i.quantity = 0 and p.status = 'published'),
    'low_stock', (select count(*) from public.inventory where quantity > 0 and quantity <= low_stock_threshold),
    'customers', (select count(*) from public.profiles),
    'by_day', coalesce((select jsonb_agg(x order by x->>'day') from (
        select jsonb_build_object('day', to_char(d::date,'YYYY-MM-DD'), 'orders', count(o.id), 'revenue', coalesce(sum(o.total),0)) x
        from generate_series(current_date - 13, current_date, '1 day') d
        left join public.orders o on o.created_at::date = d::date and o.status <> 'cancelled' group by d) s),'[]'::jsonb),
    'by_status', coalesce((select jsonb_object_agg(status, c) from (select status, count(*) c from public.orders group by status) t),'{}'::jsonb)
  );
end $$;
grant execute on function public.admin_stats() to authenticated;

-- ========== Données de base (pas de démo) ==========
insert into public.admin_permissions(role, permission) values
 ('ADMIN','products.write'),('ADMIN','categories.write'),('ADMIN','orders.write'),('ADMIN','inventory.write'),('ADMIN','coupons.write'),('ADMIN','customers.read'),('ADMIN','messages.write'),('ADMIN','settings.write'),('ADMIN','audit.read'),
 ('MANAGER','products.write'),('MANAGER','categories.write'),('MANAGER','orders.write'),('MANAGER','inventory.write'),('MANAGER','coupons.write'),('MANAGER','customers.read'),('MANAGER','messages.write'),
 ('EDITOR','products.write'),('EDITOR','categories.write'),
 ('SUPPORT','orders.write'),('SUPPORT','customers.read'),('SUPPORT','messages.write')
on conflict do nothing;

insert into public.settings(key, value) values
 ('bootstrap_admin_email', '"jloodna@gmail.com"'),
 ('store', '{"name":"JLOODNA","tagline":"Magazin global en Haïti","email":"jloodna@gmail.com","phone":"","currency":"HTG"}'),
 ('shipping', '{"flat_fee":250,"free_over":5000}'),
 ('payment_methods', '{"cod":{"enabled":true,"label":"Paiement à la livraison"},"moncash":{"enabled":false,"label":"MonCash"},"natcash":{"enabled":false,"label":"NatCash"},"card":{"enabled":false,"label":"Carte bancaire"},"paypal":{"enabled":false,"label":"PayPal"}}')
on conflict (key) do nothing;

-- ========== Realtime ==========
do $$ begin
  begin alter publication supabase_realtime add table public.notifications; exception when others then null; end;
  begin alter publication supabase_realtime add table public.orders; exception when others then null; end;
  begin alter publication supabase_realtime add table public.products; exception when others then null; end;
  begin alter publication supabase_realtime add table public.inventory; exception when others then null; end;
  begin alter publication supabase_realtime add table public.messages; exception when others then null; end;
end $$;
