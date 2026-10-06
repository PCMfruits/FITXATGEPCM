-- PCM FRUITS REGISTRE · CORRECCIÓ DEFINITIVA PER GUARDAR DNI/NIE
-- Executa aquest fitxer una sola vegada a Supabase > SQL Editor.

alter table public.empleats
  add column if not exists dni_nie text;

create unique index if not exists empleats_dni_nie_unique
on public.empleats (upper(trim(dni_nie)))
where dni_nie is not null and trim(dni_nie) <> '';

create or replace function public.admin_guardar_empleat(
  p_id bigint,
  p_nom text,
  p_codi text,
  p_dni_nie text,
  p_actiu boolean
)
returns table (
  id bigint,
  nom text,
  codi text,
  dni_nie text,
  actiu boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id bigint;
begin
  if auth.uid() is null then
    raise exception 'ADMIN_NO_AUTORITZAT';
  end if;

  if nullif(trim(p_nom), '') is null or nullif(trim(p_codi), '') is null then
    raise exception 'DADES_INCOMPLETES';
  end if;

  if p_id is null then
    insert into public.empleats (nom, codi, dni_nie, actiu)
    values (
      trim(p_nom),
      trim(p_codi),
      nullif(upper(trim(p_dni_nie)), ''),
      coalesce(p_actiu, true)
    )
    returning empleats.id into v_id;
  else
    update public.empleats
    set nom = trim(p_nom),
        codi = trim(p_codi),
        dni_nie = nullif(upper(trim(p_dni_nie)), ''),
        actiu = coalesce(p_actiu, true)
    where empleats.id = p_id
    returning empleats.id into v_id;

    if v_id is null then
      raise exception 'EMPLEAT_NO_TROBAT';
    end if;
  end if;

  return query
  select e.id, e.nom, e.codi, e.dni_nie, e.actiu, e.created_at
  from public.empleats e
  where e.id = v_id;
end;
$$;

revoke all on function public.admin_guardar_empleat(bigint,text,text,text,boolean) from public;
grant execute on function public.admin_guardar_empleat(bigint,text,text,text,boolean) to authenticated;

notify pgrst, 'reload schema';
