grant usage on schema public to authenticated;
grant usage on type public.meal_type to authenticated;
grant select, insert, update, delete on public.food_items to authenticated;

alter table public.food_items enable row level security;

drop policy if exists "food_items_select_own" on public.food_items;
drop policy if exists "food_items_insert_own" on public.food_items;
drop policy if exists "food_items_update_own" on public.food_items;
drop policy if exists "food_items_delete_own" on public.food_items;

create policy "food_items_select_own"
on public.food_items for select
using ((select auth.uid()) = user_id);

create policy "food_items_insert_own"
on public.food_items for insert
with check ((select auth.uid()) = user_id);

create policy "food_items_update_own"
on public.food_items for update
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "food_items_delete_own"
on public.food_items for delete
using ((select auth.uid()) = user_id);
