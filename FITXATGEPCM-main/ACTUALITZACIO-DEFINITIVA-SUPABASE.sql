-- PCM FRUITS · ACTUALITZACIO DEFINITIVA
-- Executa aquest fitxer UNA SOLA VEGADA a Supabase > SQL Editor.
-- Afegeix edicio segura de jornades, alta en dies passats i auditoria.

create table if not exists public.auditoria_fitxatges (
  id bigint generated always as identity primary key,
  empleat_id bigint not null references public.empleats(id),
  data_jornada date not null,
  accio text not null check (accio in ('crear_o_reemplaçar','eliminar')),
  dades_anteriors jsonb,
  dades_noves jsonb,
  motiu text not null,
  admin_email text not null,
  created_at timestamptz not null default now()
);

alter table public.auditoria_fitxatges enable row level security;

drop policy if exists "Admin principal consulta auditoria" on public.auditoria_fitxatges;
create policy "Admin principal consulta auditoria"
on public.auditoria_fitxatges for select
to authenticated
using (lower(coalesce(auth.jwt() ->> 'email','')) = 'admin@pcmfruits.com');

create or replace function public.es_admin_principal()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select lower(coalesce(auth.jwt() ->> 'email','')) = 'admin@pcmfruits.com';
$$;

grant execute on function public.es_admin_principal() to authenticated;

create or replace function public.admin_obtenir_jornada(p_empleat_id bigint, p_data date)
returns table (hora_entrada time, hora_sortida time)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.es_admin_principal() then raise exception 'ADMIN_NO_AUTORITZAT'; end if;
  return query
  select
    (min(f.data_hora at time zone 'Europe/Madrid') filter (where f.tipus='entrada'))::time,
    (max(f.data_hora at time zone 'Europe/Madrid') filter (where f.tipus='sortida'))::time
  from public.fitxatges f
  where f.empleat_id=p_empleat_id
    and (f.data_hora at time zone 'Europe/Madrid')::date=p_data;
end;
$$;

grant execute on function public.admin_obtenir_jornada(bigint,date) to authenticated;

create or replace function public.admin_guardar_jornada(
  p_empleat_id bigint,
  p_data date,
  p_hora_entrada time,
  p_hora_sortida time,
  p_motiu text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(coalesce(auth.jwt() ->> 'email',''));
  v_abans jsonb;
  v_entrada timestamptz;
  v_sortida timestamptz;
begin
  if v_email <> 'admin@pcmfruits.com' then raise exception 'ADMIN_NO_AUTORITZAT'; end if;
  if p_data > (now() at time zone 'Europe/Madrid')::date then raise exception 'DATA_FUTURA_NO_PERMESA'; end if;
  if trim(coalesce(p_motiu,'')) = '' then raise exception 'MOTIU_OBLIGATORI'; end if;
  if not exists(select 1 from public.empleats where id=p_empleat_id) then raise exception 'EMPLEAT_INEXISTENT'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'tipus',f.tipus,'data_hora',f.data_hora) order by f.data_hora),'[]'::jsonb)
  into v_abans
  from public.fitxatges f
  where f.empleat_id=p_empleat_id and (f.data_hora at time zone 'Europe/Madrid')::date=p_data;

  v_entrada := make_timestamptz(extract(year from p_data)::int, extract(month from p_data)::int, extract(day from p_data)::int,
    extract(hour from p_hora_entrada)::int, extract(minute from p_hora_entrada)::int, 0, 'Europe/Madrid');
  v_sortida := make_timestamptz(extract(year from p_data)::int, extract(month from p_data)::int, extract(day from p_data)::int,
    extract(hour from p_hora_sortida)::int, extract(minute from p_hora_sortida)::int, 0, 'Europe/Madrid');
  if v_sortida < v_entrada then v_sortida := v_sortida + interval '1 day'; end if;
  if v_sortida - v_entrada > interval '24 hours' then raise exception 'JORNADA_INVALIDA'; end if;

  delete from public.fitxatges
  where empleat_id=p_empleat_id and (data_hora at time zone 'Europe/Madrid')::date=p_data;

  insert into public.fitxatges(empleat_id,tipus,data_hora)
  values (p_empleat_id,'entrada',v_entrada),(p_empleat_id,'sortida',v_sortida);

  insert into public.auditoria_fitxatges(empleat_id,data_jornada,accio,dades_anteriors,dades_noves,motiu,admin_email)
  values (p_empleat_id,p_data,'crear_o_reemplaçar',v_abans,
    jsonb_build_array(jsonb_build_object('tipus','entrada','data_hora',v_entrada),jsonb_build_object('tipus','sortida','data_hora',v_sortida)),
    trim(p_motiu),v_email);
end;
$$;

grant execute on function public.admin_guardar_jornada(bigint,date,time,time,text) to authenticated;

create or replace function public.admin_esborrar_jornada(p_empleat_id bigint, p_data date, p_motiu text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_email text := lower(coalesce(auth.jwt() ->> 'email',''));
  v_abans jsonb;
begin
  if v_email <> 'admin@pcmfruits.com' then raise exception 'ADMIN_NO_AUTORITZAT'; end if;
  if trim(coalesce(p_motiu,'')) = '' then raise exception 'MOTIU_OBLIGATORI'; end if;

  select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'tipus',f.tipus,'data_hora',f.data_hora) order by f.data_hora),'[]'::jsonb)
  into v_abans from public.fitxatges f
  where f.empleat_id=p_empleat_id and (f.data_hora at time zone 'Europe/Madrid')::date=p_data;

  delete from public.fitxatges
  where empleat_id=p_empleat_id and (data_hora at time zone 'Europe/Madrid')::date=p_data;

  insert into public.auditoria_fitxatges(empleat_id,data_jornada,accio,dades_anteriors,dades_noves,motiu,admin_email)
  values (p_empleat_id,p_data,'eliminar',v_abans,'[]'::jsonb,trim(p_motiu),v_email);
end;
$$;

grant execute on function public.admin_esborrar_jornada(bigint,date,text) to authenticated;
