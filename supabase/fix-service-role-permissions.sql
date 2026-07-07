grant usage on schema public to service_role;
grant usage on type public.meal_type to service_role;
grant select, insert, update, delete on public.food_items to service_role;

grant usage on schema storage to service_role;
grant select, insert, update, delete on storage.objects to service_role;
