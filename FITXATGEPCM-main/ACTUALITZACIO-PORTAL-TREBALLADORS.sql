-- PCM FRUITS REGISTRE · DNI/NIE I PORTAL DEL TREBALLADOR
-- Executa aquest fitxer una sola vegada a Supabase > SQL Editor.

alter table public.empleats
  add column if not exists dni_nie text;

create unique index if not exists empleats_dni_nie_unique
on public.empleats (upper(trim(dni_nie)))
where dni_nie is not null and trim(dni_nie) <> '';

-- El portal només retorna dades de l'empleat identificat pel seu codi.
create or replace function public.portal_obtenir_registres(
  p_codi text,
  p_mes date
)
returns table (
  nom text,
  codi text,
  data_hora timestamptz,
  tipus text
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_empleat_id bigint;
  v_inici date;
  v_fi date;
begin
  select e.id into v_empleat_id
  from public.empleats e
  where e.codi = trim(p_codi)
  limit 1;

  if v_empleat_id is null then
    raise exception 'CODI_INCORRECTE';
  end if;

  v_inici := date_trunc('month', p_mes)::date;
  v_fi := (v_inici + interval '1 month')::date;

  return query
  select e.nom, e.codi, f.data_hora, f.tipus
  from public.empleats e
  left join public.fitxatges f
    on f.empleat_id = e.id
   and (f.data_hora at time zone 'Europe/Madrid')::date >= v_inici
   and (f.data_hora at time zone 'Europe/Madrid')::date < v_fi
  where e.id = v_empleat_id
  order by f.data_hora asc nulls first;
end;
$$;

revoke all on function public.portal_obtenir_registres(text,date) from public;
grant execute on function public.portal_obtenir_registres(text,date) to anon, authenticated;
