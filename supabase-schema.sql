create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  role text not null default 'customer' check (role in ('customer','owner')),
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text not null default '',
  image_url text,
  price numeric(12,2) not null check (price >= 0),
  category text not null check (category in ('Cakes','Pastries','Cookies','Breads','Donuts','Cupcakes','Chocolates','Other Bakery Items')),
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  published boolean not null default true,
  is_sample boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  order_number text not null unique,
  customer_name text not null,
  phone text not null,
  fulfilment text not null check (fulfilment in ('Delivery','Pickup')),
  address text not null default '',
  notes text,
  total numeric(12,2) not null default 0 check (total >= 0),
  status text not null default 'New Order' check (status in (
    'New Order','Order Accepted','Preparing','Ready for Pickup',
    'Out for Delivery','Completed','Cancellation Requested','Cancelled'
  )),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null,
  product_name text not null,
  unit_price numeric(12,2) not null check (unit_price >= 0),
  quantity integer not null check (quantity > 0),
  line_total numeric(12,2) not null check (line_total >= 0)
);

create table if not exists public.cancellation_requests (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  reason text not null,
  status text not null default 'Pending' check (status in ('Pending','Approved','Rejected')),
  previous_order_status text,
  decided_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  order_id uuid references public.orders(id) on delete cascade,
  user_id uuid references auth.users(id) on delete cascade,
  type text not null,
  message text not null,
  read boolean not null default false,
  created_at timestamptz not null default now()
);

alter table public.notifications
  add column if not exists user_id uuid references auth.users(id) on delete cascade;
alter table public.cancellation_requests
  add column if not exists previous_order_status text;

alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.cancellation_requests enable row level security;
alter table public.notifications enable row level security;

create or replace function public.is_owner()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles
    where id = auth.uid()
      and role = 'owner'
  );
$$;

drop function if exists public.decrement_product_stock(uuid);
drop function if exists public.decrement_product_stock(uuid,jsonb);
drop function if exists public.restore_cancelled_stock(uuid);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform pg_advisory_xact_lock(hashtext('artisan-bakery-owner-registration'));
  insert into public.profiles(id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name',''),
    case
      when not exists (select 1 from public.profiles) then 'owner'
      else 'customer'
    end
  )
  on conflict (id) do update
  set full_name=excluded.full_name,
      role=case when public.profiles.role='owner' then 'owner' else excluded.role end;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert or update of email on auth.users
  for each row execute procedure public.handle_new_user();

-- Keep one owner for existing installations and assign only the earliest account.
with ranked_profiles as (
  select id, row_number() over (order by created_at asc, id asc) as position
  from public.profiles
)
update public.profiles p
set role = case when r.position = 1 then 'owner' else 'customer' end
from ranked_profiles r
where p.id = r.id;

drop policy if exists "Published products are public" on public.products;
drop policy if exists "Owner manages all products" on public.products;
create policy "Published products are public" on public.products
for select using (published or public.is_owner());
create policy "Owner manages all products" on public.products
for all using (public.is_owner()) with check (public.is_owner());

drop policy if exists "Customers view own orders" on public.orders;
drop policy if exists "Owner views all orders" on public.orders;
drop policy if exists "Customers create own orders" on public.orders;
drop policy if exists "Owner updates orders" on public.orders;
create policy "Customers view own orders" on public.orders
for select using (auth.uid() = user_id or public.is_owner());

drop policy if exists "Customers view own order items" on public.order_items;
drop policy if exists "Owner views all order items" on public.order_items;
drop policy if exists "Customers create own order items" on public.order_items;
create policy "Customers view own order items" on public.order_items
for select using (
  public.is_owner()
  or exists(select 1 from public.orders o where o.id=order_id and o.user_id=auth.uid())
);

drop policy if exists "Customers view own cancellation requests" on public.cancellation_requests;
drop policy if exists "Customers create own cancellation requests" on public.cancellation_requests;
drop policy if exists "Owner manages cancellation requests" on public.cancellation_requests;
drop policy if exists "Read own or owner cancellation requests" on public.cancellation_requests;
create policy "Read own or owner cancellation requests" on public.cancellation_requests
for select using (
  public.is_owner()
  or exists(select 1 from public.orders o where o.id=order_id and o.user_id=auth.uid())
);

drop policy if exists "Owner reads notifications" on public.notifications;
drop policy if exists "Owner updates notifications" on public.notifications;
drop policy if exists "Customers create order notifications" on public.notifications;
drop policy if exists "Read owner or personal notifications" on public.notifications;
drop policy if exists "Update owner or personal notifications" on public.notifications;
create policy "Read owner or personal notifications" on public.notifications
for select using (public.is_owner() or user_id=auth.uid());
create policy "Update owner or personal notifications" on public.notifications
for update using (public.is_owner() or user_id=auth.uid())
with check (public.is_owner() or user_id=auth.uid());

drop policy if exists "Users view own profile" on public.profiles;
drop policy if exists "Owner views profiles" on public.profiles;
drop policy if exists "Users view own or owner views profiles" on public.profiles;
create policy "Users view own or owner views profiles" on public.profiles
for select using (auth.uid()=id or public.is_owner());

grant usage on schema public to anon, authenticated;
grant select on public.products to anon, authenticated;
grant insert, update, delete on public.products to authenticated;
grant select on public.profiles, public.orders, public.order_items,
  public.cancellation_requests, public.notifications to authenticated;
grant update on public.notifications to authenticated;

with seed(name,description,price,category,stock_quantity,image_url) as (
  values
    ('Belgian Chocolate Truffle Cake','Dark chocolate sponge layered with smooth chocolate ganache.',950,'Cakes',8,'https://images.pexels.com/photos/5691261/pexels-photo-5691261.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Red Velvet Celebration Cake','Soft red velvet layers finished with cream cheese frosting.',1100,'Cakes',6,'https://images.pexels.com/photos/10360611/pexels-photo-10360611.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Black Forest Gateau','Chocolate sponge, cherries and whipped cream.',990,'Cakes',7,'https://images.pexels.com/photos/19036040/pexels-photo-19036040.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Vanilla Berry Layer Cake','Vanilla sponge with fresh berries and light cream.',850,'Cakes',8,'https://images.pexels.com/photos/10507819/pexels-photo-10507819.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Mango Mousse Cake','A light mango mousse cake with a soft biscuit base.',880,'Cakes',6,'https://images.pexels.com/photos/863006/pexels-photo-863006.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Caramel Crunch Cake','Caramel cream and crisp praline between tender cake layers.',920,'Cakes',7,'https://images.pexels.com/photos/7966511/pexels-photo-7966511.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Strawberry Cream Cake','Fresh strawberries, vanilla sponge and whipped cream.',980,'Cakes',6,'https://images.pexels.com/photos/19651273/pexels-photo-19651273.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Chocolate Drip Cake','Rich chocolate cake finished with a glossy ganache drip.',1150,'Cakes',5,'https://images.pexels.com/photos/1983592/pexels-photo-1983592.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Coffee Walnut Cake','Coffee buttercream and toasted walnuts in a classic layer cake.',1020,'Cakes',6,'https://images.pexels.com/photos/18613262/pexels-photo-18613262.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Rainbow Sprinkle Cake','Colorful vanilla layers topped with cheerful sprinkles.',890,'Cakes',8,'https://images.pexels.com/photos/37748387/pexels-photo-37748387.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Chocolate Chip Cookies','Golden cookies filled with generous chocolate chips.',120,'Cookies',30,'https://images.pexels.com/photos/35156663/pexels-photo-35156663.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Double Chocolate Cookies','Soft cocoa cookies with dark chocolate chunks.',140,'Cookies',24,'https://images.pexels.com/photos/5847103/pexels-photo-5847103.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Oatmeal Raisin Cookies','Chewy oat cookies with raisins and a touch of cinnamon.',110,'Cookies',25,'https://images.pexels.com/photos/39632184/pexels-photo-39632184.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Classic Butter Cookies','Crisp, buttery cookies baked until lightly golden.',100,'Cookies',30,'https://images.pexels.com/photos/310575/pexels-photo-310575.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Peanut Butter Cookies','Rich peanut butter cookies with a tender crumb.',130,'Cookies',20,'https://images.pexels.com/photos/14839145/pexels-photo-14839145.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Almond Biscotti','Twice-baked almond biscuits made for coffee breaks.',150,'Cookies',18,'https://images.pexels.com/photos/8478048/pexels-photo-8478048.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Jam Thumbprint Cookies','Buttery cookies filled with bright fruit jam.',125,'Cookies',22,'https://images.pexels.com/photos/5847092/pexels-photo-5847092.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Cocoa Crinkle Cookies','Soft chocolate cookies with a delicate sugar crust.',115,'Cookies',22,'https://images.pexels.com/photos/5846039/pexels-photo-5846039.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Cinnamon Sugar Cookies','Warm cinnamon cookies with a lightly crisp edge.',135,'Cookies',20,'https://images.pexels.com/photos/10243944/pexels-photo-10243944.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Assorted Cookie Box','A box of twelve assorted freshly baked cookies.',450,'Cookies',12,'https://images.pexels.com/photos/31116125/pexels-photo-31116125.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Rustic Sourdough Boule','Naturally leavened loaf with a crisp crust and open crumb.',290,'Breads',12,'https://images.pexels.com/photos/40321541/pexels-photo-40321541.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Multigrain Sandwich Loaf','Soft sliced loaf baked with wholesome mixed grains.',240,'Breads',14,'https://images.pexels.com/photos/20106930/pexels-photo-20106930.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Garlic Herb Focaccia','Olive oil focaccia topped with garlic and garden herbs.',260,'Breads',10,'https://images.pexels.com/photos/6195/bread-food-baking-homemade.jpg?cs=tinysrgb&dpr=1&w=800'),
    ('French Baguette','A crisp, slender baguette with a soft airy centre.',180,'Breads',16,'https://images.pexels.com/photos/40756952/pexels-photo-40756952.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Brioche Loaf','Enriched, tender brioche with a delicate golden crust.',320,'Breads',10,'https://images.pexels.com/photos/27418961/pexels-photo-27418961.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Olive Sourdough','Slow-fermented sourdough with olives folded through.',340,'Breads',8,'https://images.pexels.com/photos/39575614/pexels-photo-39575614.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Rustic Dinner Rolls','A pack of six soft, freshly baked dinner rolls.',220,'Breads',15,'https://images.pexels.com/photos/2924872/pexels-photo-2924872.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Country Wheat Bread','Hearty wheat loaf with a wholesome flavour.',260,'Breads',12,'https://images.pexels.com/photos/7543099/pexels-photo-7543099.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Artisan Bakery Loaf','A daily-baked country loaf with a crisp, flour-dusted crust.',300,'Breads',10,'https://images.pexels.com/photos/38959004/pexels-photo-38959004.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Ciabatta Loaf','An airy Italian-style loaf with a crisp, rustic crust.',270,'Breads',10,'https://images.pexels.com/photos/1383908/pexels-photo-1383908.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Classic Glazed Donut','Light ring donut coated in a smooth vanilla glaze.',120,'Donuts',18,'https://images.pexels.com/photos/34565248/pexels-photo-34565248.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Chocolate Frosted Donut','Soft donut topped with rich chocolate icing.',140,'Donuts',16,'https://images.pexels.com/photos/30822876/pexels-photo-30822876.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Strawberry Sprinkle Donut','Strawberry icing and colorful sprinkles on a fluffy donut.',150,'Donuts',14,'https://images.pexels.com/photos/590771/pexels-photo-590771.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Boston Cream Donut','A soft donut filled with vanilla custard and chocolate.',170,'Donuts',12,'https://images.pexels.com/photos/7440369/pexels-photo-7440369.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Cinnamon Sugar Donut','Warm cinnamon sugar over a tender, freshly fried donut.',130,'Donuts',16,'https://images.pexels.com/photos/3338681/pexels-photo-3338681.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Mini Donut Assortment','A box of twelve mini donuts with assorted toppings.',420,'Donuts',10,'https://images.pexels.com/photos/34491951/pexels-photo-34491951.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Chocolate Sprinkle Donut','Chocolate-glazed ring finished with crunchy sprinkles.',160,'Donuts',14,'https://images.pexels.com/photos/18580208/pexels-photo-18580208.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Powdered Sugar Donut','A pillowy donut dusted with fine powdered sugar.',145,'Donuts',15,'https://images.pexels.com/photos/40987119/pexels-photo-40987119.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Chocolate Custard Donut','A filled donut with smooth chocolate custard.',155,'Donuts',12,'https://images.pexels.com/photos/38638101/pexels-photo-38638101.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Caramel Glaze Donut','Soft donut with a buttery caramel glaze.',180,'Donuts',12,'https://images.pexels.com/photos/40867473/pexels-photo-40867473.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Vanilla Buttercream Cupcake','Vanilla sponge crowned with silky buttercream.',120,'Cupcakes',18,'https://images.pexels.com/photos/11128671/pexels-photo-11128671.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Red Velvet Cupcake','Red velvet sponge with a cream cheese swirl.',140,'Cupcakes',16,'https://images.pexels.com/photos/4981623/pexels-photo-4981623.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Chocolate Ganache Cupcake','Chocolate cupcake with a rich ganache topping.',150,'Cupcakes',15,'https://images.pexels.com/photos/585581/pexels-photo-585581.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Lemon Frosted Cupcake','Bright lemon sponge with a smooth citrus frosting.',135,'Cupcakes',16,'https://images.pexels.com/photos/6781767/pexels-photo-6781767.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Blueberry Cupcake','Vanilla cupcake with blueberry pieces and cream.',145,'Cupcakes',14,'https://images.pexels.com/photos/8964308/pexels-photo-8964308.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Salted Caramel Cupcake','Caramel-filled sponge finished with salted caramel icing.',150,'Cupcakes',14,'https://images.pexels.com/photos/8210523/pexels-photo-8210523.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Rainbow Sprinkle Cupcake','Vanilla buttercream and bright rainbow sprinkles.',125,'Cupcakes',18,'https://images.pexels.com/photos/8605045/pexels-photo-8605045.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Double Chocolate Cupcake','Deep cocoa sponge topped with chocolate frosting.',140,'Cupcakes',16,'https://images.pexels.com/photos/1028704/pexels-photo-1028704.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Celebration Cupcake','A decorated vanilla cupcake for a special treat.',160,'Cupcakes',12,'https://images.pexels.com/photos/9501359/pexels-photo-9501359.jpeg?cs=tinysrgb&dpr=1&w=800'),
    ('Mini Cupcake Box','A box of six mini cupcakes with assorted frosting.',600,'Cupcakes',8,'https://images.pexels.com/photos/36885265/pexels-photo-36885265.jpeg?cs=tinysrgb&dpr=1&w=800')
)
insert into public.products(name,description,price,category,stock_quantity,published,is_sample,image_url)
select s.name,s.description,s.price,s.category,s.stock_quantity,true,false,s.image_url
from seed s
where not exists(
  select 1 from public.products p where lower(p.name)=lower(s.name)
);

insert into storage.buckets(id,name,public) values ('bakery-images','bakery-images',true)
on conflict (id) do update set public=true;

drop policy if exists "Product images are public" on storage.objects;
drop policy if exists "Owner uploads product images" on storage.objects;
drop policy if exists "Owner updates product images" on storage.objects;
drop policy if exists "Owner deletes product images" on storage.objects;
create policy "Product images are public" on storage.objects
for select using (bucket_id='bakery-images');
create policy "Owner uploads product images" on storage.objects
for insert with check (bucket_id='bakery-images' and public.is_owner());
create policy "Owner updates product images" on storage.objects
for update using (bucket_id='bakery-images' and public.is_owner())
with check (bucket_id='bakery-images' and public.is_owner());
create policy "Owner deletes product images" on storage.objects
for delete using (bucket_id='bakery-images' and public.is_owner());

create or replace function public.place_order(
  p_customer_name text,
  p_phone text,
  p_fulfilment text,
  p_address text,
  p_notes text,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_order public.orders;
  product public.products;
  line record;
  calculated_total numeric(12,2) := 0;
  item_count integer := 0;
begin
  if auth.uid() is null then raise exception 'Login required'; end if;
  if coalesce(btrim(p_customer_name),'')='' or coalesce(btrim(p_phone),'')='' then
    raise exception 'Customer name and phone are required';
  end if;
  if p_fulfilment not in ('Delivery','Pickup') then raise exception 'Invalid fulfilment method'; end if;
  if p_fulfilment='Delivery' and coalesce(btrim(p_address),'')='' then
    raise exception 'Delivery address is required';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then
    raise exception 'Your cart is empty';
  end if;

  insert into public.orders(user_id,order_number,customer_name,phone,fulfilment,address,notes,total)
  values(
    auth.uid(),
    'AB-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,10)),
    btrim(p_customer_name), btrim(p_phone), p_fulfilment,
    coalesce(btrim(p_address),''), nullif(btrim(coalesce(p_notes,'')),''), 0
  ) returning * into new_order;

  for line in
    select input.product_id, sum(input.quantity)::integer as quantity
    from jsonb_to_recordset(p_items) as input(product_id uuid, quantity integer)
    group by input.product_id
    order by input.product_id
  loop
    if line.product_id is null or line.quantity is null or line.quantity < 1 then
      raise exception 'Invalid cart item';
    end if;
    select * into product
    from public.products
    where id=line.product_id and published=true
    for update;
    if not found then raise exception 'A product is unavailable'; end if;
    if product.stock_quantity < line.quantity then
      raise exception 'Insufficient stock for %', product.name;
    end if;

    calculated_total := calculated_total + product.price * line.quantity;
    item_count := item_count + 1;
    insert into public.order_items(order_id,product_id,product_name,unit_price,quantity,line_total)
    values(new_order.id,product.id,product.name,product.price,line.quantity,product.price*line.quantity);
    update public.products
    set stock_quantity=stock_quantity-line.quantity, updated_at=now()
    where id=product.id;
  end loop;

  if item_count=0 then raise exception 'No valid products in cart'; end if;
  update public.orders set total=calculated_total,updated_at=now()
  where id=new_order.id returning * into new_order;

  insert into public.notifications(order_id,user_id,type,message)
  values(new_order.id,null,'new_order','NEW ORDER RECEIVED!');

  return jsonb_build_object(
    'order',to_jsonb(new_order),
    'items',(select coalesce(jsonb_agg(to_jsonb(oi) order by oi.product_name),'[]'::jsonb)
             from public.order_items oi where oi.order_id=new_order.id)
  );
end;
$$;

create or replace function public.request_cancellation(p_order_id uuid,p_reason text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare current_order public.orders;
begin
  select * into current_order from public.orders
  where id=p_order_id and user_id=auth.uid()
  for update;
  if not found then raise exception 'Order not found'; end if;
  if current_order.status in ('Completed','Cancelled','Cancellation Requested') then
    raise exception 'This order cannot be cancelled';
  end if;
  if coalesce(btrim(p_reason),'')='' then raise exception 'Cancellation reason is required'; end if;

  insert into public.cancellation_requests(order_id,reason,previous_order_status)
  values(p_order_id,btrim(p_reason),current_order.status);
  update public.orders set status='Cancellation Requested',updated_at=now()
  where id=p_order_id;
  insert into public.notifications(order_id,user_id,type,message)
  values(p_order_id,null,'cancellation_request','NEW CANCELLATION REQUEST');
end;
$$;

create or replace function public.decide_cancellation(p_request_id uuid,p_approve boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  cancellation public.cancellation_requests;
  current_order public.orders;
  item record;
begin
  if not public.is_owner() then raise exception 'Owner access required'; end if;
  select * into cancellation from public.cancellation_requests
  where id=p_request_id for update;
  if not found or cancellation.status<>'Pending' then
    raise exception 'Cancellation request is no longer pending';
  end if;
  select * into current_order from public.orders
  where id=cancellation.order_id for update;
  if not found or current_order.status in ('Completed','Cancelled') then
    raise exception 'This order can no longer be cancelled';
  end if;

  update public.cancellation_requests
  set status=case when p_approve then 'Approved' else 'Rejected' end,decided_at=now()
  where id=p_request_id;
  update public.orders
  set status=case when p_approve then 'Cancelled' else coalesce(cancellation.previous_order_status,'Order Accepted') end,
      updated_at=now()
  where id=current_order.id;

  if p_approve then
    for item in select product_id,quantity from public.order_items
      where order_id=current_order.id and product_id is not null
    loop
      update public.products set stock_quantity=stock_quantity+item.quantity,updated_at=now()
      where id=item.product_id;
    end loop;
  end if;

  insert into public.notifications(order_id,user_id,type,message)
  values(current_order.id,current_order.user_id,'cancellation_decision',
    case when p_approve then 'Your cancellation was approved' else 'Your cancellation was rejected' end);
end;
$$;

create or replace function public.update_owner_order_status(p_order_id uuid,p_status text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare current_order public.orders;
begin
  if not public.is_owner() then raise exception 'Owner access required'; end if;
  if p_status not in ('Order Accepted','Preparing','Ready for Pickup','Out for Delivery','Completed') then
    raise exception 'Use cancellation review to cancel an order';
  end if;
  select * into current_order from public.orders where id=p_order_id for update;
  if not found then raise exception 'Order not found'; end if;
  if current_order.status in ('Cancelled','Completed','Cancellation Requested') then
    raise exception 'This order status cannot be changed';
  end if;
  update public.orders set status=p_status,updated_at=now() where id=p_order_id;
  insert into public.notifications(order_id,user_id,type,message)
  values(p_order_id,current_order.user_id,'order_status','Your order status is now ' || p_status);
end;
$$;

revoke all on function public.place_order(text,text,text,text,text,jsonb) from public;
revoke all on function public.request_cancellation(uuid,text) from public;
revoke all on function public.decide_cancellation(uuid,boolean) from public;
revoke all on function public.update_owner_order_status(uuid,text) from public;
grant execute on function public.place_order(text,text,text,text,text,jsonb) to authenticated;
grant execute on function public.request_cancellation(uuid,text) to authenticated;
grant execute on function public.decide_cancellation(uuid,boolean) to authenticated;
grant execute on function public.update_owner_order_status(uuid,text) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname='supabase_realtime' and schemaname='public' and tablename='notifications'
  ) then
    alter publication supabase_realtime add table public.notifications;
  end if;
end;
$$;
