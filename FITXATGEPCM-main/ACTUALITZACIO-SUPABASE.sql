-- Executa aquest SQL una sola vegada a Supabase > SQL Editor.
-- Afegeix permisos per crear, editar, activar i desactivar empleats des de l'app.

alter table public.empleats enable row level security;

drop policy if exists "Administradors creen empleats" on public.empleats;
create policy "Administradors creen empleats"
on public.empleats for insert
to authenticated
with check (true);

drop policy if exists "Administradors actualitzen empleats" on public.empleats;
create policy "Administradors actualitzen empleats"
on public.empleats for update
to authenticated
using (true)
with check (true);
