-- Executa aquest script a Supabase > SQL Editor.

create table if not exists public.empleats (
  id bigint generated always as identity primary key,
  nom text not null,
  codi text not null unique,
  actiu boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.fitxatges (
  id bigint generated always as identity primary key,
  empleat_id bigint not null references public.empleats(id),
  tipus text not null check (tipus in ('entrada', 'sortida')),
  data_hora timestamptz not null default now()
);

create index if not exists fitxatges_empleat_idx on public.fitxatges (empleat_id);
create index if not exists fitxatges_data_idx on public.fitxatges (data_hora desc);

alter table public.empleats enable row level security;
alter table public.fitxatges enable row level security;

-- La web pública no llegeix directament la taula d'empleats ni la de fitxatges.
-- El fitxatge es registra mitjançant aquesta funció segura.
create or replace function public.registrar_fitxatge(p_codi text, p_tipus text)
returns table (
  fitxatge_id bigint,
  nom text,
  tipus text,
  data_hora timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empleat public.empleats%rowtype;
  v_ultim_tipus text;
  v_fitxatge public.fitxatges%rowtype;
begin
  if p_tipus not in ('entrada', 'sortida') then
    raise exception 'TIPUS_INVALID';
  end if;

  select * into v_empleat
  from public.empleats
  where codi = trim(p_codi) and actiu = true;

  if not found then
    raise exception 'CODI_INCORRECTE';
  end if;

  select f.tipus into v_ultim_tipus
  from public.fitxatges f
  where f.empleat_id = v_empleat.id
  order by f.data_hora desc
  limit 1;

  if v_ultim_tipus = p_tipus then
    raise exception 'FITXATGE_DUPLICAT';
  end if;

  insert into public.fitxatges (empleat_id, tipus)
  values (v_empleat.id, p_tipus)
  returning * into v_fitxatge;

  return query
  select v_fitxatge.id, v_empleat.nom, v_fitxatge.tipus, v_fitxatge.data_hora;
end;
$$;

grant execute on function public.registrar_fitxatge(text, text) to anon, authenticated;

-- Vista només per a administradors autenticats.
create or replace view public.vista_fitxatges
with (security_invoker = true)
as
select
  f.id,
  f.data_hora,
  f.tipus,
  e.nom,
  e.codi
from public.fitxatges f
join public.empleats e on e.id = f.empleat_id;

-- Els usuaris autenticats poden consultar el panell d'administració.
-- Crea només comptes d'administrador a Supabase Auth.
drop policy if exists "Administradors consulten empleats" on public.empleats;
create policy "Administradors consulten empleats"
on public.empleats for select
to authenticated
using (true);

drop policy if exists "Administradors consulten fitxatges" on public.fitxatges;
create policy "Administradors consulten fitxatges"
on public.fitxatges for select
to authenticated
using (true);

-- EXEMPLES. Canvia noms i codis abans d'executar-los.
-- insert into public.empleats (nom, codi) values
-- ('Treballador 1', '1001'),
-- ('Treballador 2', '1002');

-- PERMETRE GESTIONAR EMPLEATS DES DEL PANELL D'ADMINISTRACIO
-- Executa aquest bloc si ja havies executat una versio anterior de l'SQL.
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
