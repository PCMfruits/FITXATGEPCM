-- ================================================================
-- PCM FITXATGE - FITXATGE AUTOMATIC JORNADA COMPLETA / MITJA
-- Executa aquest SQL UNA SOLA VEGADA al Supabase SQL Editor.
-- Manté la jornada completa existent i afegeix el mode de mitja jornada.
-- ================================================================

alter table public.configuracio_fitxatge_automatic
  add column if not exists jornada_mode text not null default 'completa';

update public.configuracio_fitxatge_automatic
set jornada_mode = case when jornada_mode in ('completa','mitja') then jornada_mode else 'completa' end
where id = 1;

drop function if exists public.admin_guardar_config_fitxatge_automatic_doble(boolean,time,time,time,time);


create or replace function public.admin_obtenir_config_fitxatge_automatic_doble()
returns table(
  actiu boolean,
  jornada_mode text,
  entrada_1 time,
  sortida_1 time,
  entrada_2 time,
  sortida_2 time,
  dies_setmana smallint[],
  retard_minim_segons smallint,
  retard_maxim_segons smallint,
  actualitzat_el timestamptz
)
language plpgsql security definer set search_path=public
as $$
begin
  if lower(coalesce(auth.jwt()->>'email','')) <> 'admin@pcmfruits.com' then
    raise exception 'ADMIN_NO_AUTORITZAT';
  end if;
  return query
  select c.actiu,c.jornada_mode,c.entrada_1,c.sortida_1,c.entrada_2,c.sortida_2,
         c.dies_setmana,c.retard_minim_segons,c.retard_maxim_segons,c.actualitzat_el
  from public.configuracio_fitxatge_automatic c
  where c.id=1;
end $$;

revoke all on function public.admin_obtenir_config_fitxatge_automatic_doble() from public,anon;
grant execute on function public.admin_obtenir_config_fitxatge_automatic_doble() to authenticated;

create or replace function public.admin_guardar_config_fitxatge_automatic_doble(
  p_actiu boolean,
  p_jornada_mode text,
  p_entrada_1 time,
  p_sortida_1 time,
  p_entrada_2 time,
  p_sortida_2 time
)
returns void language plpgsql security definer set search_path=public
as $$
declare
  v_email text:=lower(coalesce(auth.jwt()->>'email',''));
begin
  if v_email <> 'admin@pcmfruits.com' then raise exception 'ADMIN_NO_AUTORITZAT'; end if;
  if p_jornada_mode not in ('completa','mitja') then raise exception 'JORNADA_MODE_INVALID'; end if;
  if p_entrada_1 is null or p_sortida_1 is null or not(p_entrada_1 < p_sortida_1) then raise exception 'HORARI_PRIMERA_JORNADA_INVALID'; end if;
  if p_jornada_mode='completa' and (p_entrada_2 is null or p_sortida_2 is null or not(p_sortida_1 <= p_entrada_2 and p_entrada_2 < p_sortida_2)) then
    raise exception 'HORARI_DOBLE_INVALID';
  end if;
  update public.configuracio_fitxatge_automatic
  set actiu=coalesce(p_actiu,false),
      jornada_mode=p_jornada_mode,
      entrada_1=p_entrada_1,
      sortida_1=p_sortida_1,
      entrada_2=case when p_jornada_mode='completa' then p_entrada_2 else null end,
      sortida_2=case when p_jornada_mode='completa' then p_sortida_2 else null end,
      dies_setmana=array[1,2,3,4,5]::smallint[],
      retard_minim_segons=10,
      retard_maxim_segons=20,
      actualitzat_per=v_email,
      actualitzat_el=now()
  where id=1;
end $$;

revoke all on function public.admin_guardar_config_fitxatge_automatic_doble(boolean,text,time,time,time,time) from public,anon;
grant execute on function public.admin_guardar_config_fitxatge_automatic_doble(boolean,text,time,time,time,time) to authenticated;

-- Versió directa del worker antic, si encara existís algun cron apuntant-hi.
create or replace function public.executar_fitxatge_automatic_doble()
returns void language plpgsql security definer set search_path=public
as $$
declare
  c public.configuracio_fitxatge_automatic%rowtype;
  ara timestamp; dia date; minut int; etapa text; tipus text; hora_obj time;
  exid bigint; emp record; total int; pos int:=0; okc int:=0; omesos int:=0; ultim text; retard int;
begin
  if not pg_try_advisory_xact_lock(26072902) then return; end if;
  select * into c from public.configuracio_fitxatge_automatic where id=1;
  if not found or not c.actiu then return; end if;
  ara:=clock_timestamp() at time zone 'Europe/Madrid'; dia:=ara::date;
  if extract(isodow from ara)::int<>all(c.dies_setmana::int[]) then return; end if;
  minut:=extract(hour from ara)::int*60+extract(minute from ara)::int;

  if minut between extract(hour from c.entrada_1)::int*60+extract(minute from c.entrada_1)::int and extract(hour from c.entrada_1)::int*60+extract(minute from c.entrada_1)::int+59 then etapa:='entrada_1'; tipus:='entrada'; hora_obj:=c.entrada_1;
  elsif minut between extract(hour from c.sortida_1)::int*60+extract(minute from c.sortida_1)::int and extract(hour from c.sortida_1)::int*60+extract(minute from c.sortida_1)::int+59 then etapa:='sortida_1'; tipus:='sortida'; hora_obj:=c.sortida_1;
  elsif c.jornada_mode='completa' and minut between extract(hour from c.entrada_2)::int*60+extract(minute from c.entrada_2)::int and extract(hour from c.entrada_2)::int*60+extract(minute from c.entrada_2)::int+59 then etapa:='entrada_2'; tipus:='entrada'; hora_obj:=c.entrada_2;
  elsif c.jornada_mode='completa' and minut between extract(hour from c.sortida_2)::int*60+extract(minute from c.sortida_2)::int and extract(hour from c.sortida_2)::int*60+extract(minute from c.sortida_2)::int+59 then etapa:='sortida_2'; tipus:='sortida'; hora_obj:=c.sortida_2;
  else return; end if;

  insert into public.execucions_fitxatge_automatic_doble(data_execucio,etapa) values(dia,etapa)
  on conflict(data_execucio,etapa) do nothing returning id into exid;
  if exid is null then return; end if;
  select count(*) into total from public.empleats where actiu=true;
  for emp in select id from public.empleats where actiu=true order by id loop
    pos:=pos+1; ultim:=null;
    select f.tipus into ultim from public.fitxatges f where f.empleat_id=emp.id order by f.data_hora desc limit 1;
    if ultim is distinct from tipus then
      insert into public.fitxatges(empleat_id,tipus,data_hora) values(emp.id,tipus,clock_timestamp()); okc:=okc+1;
    else omesos:=omesos+1; end if;
    if pos<total then retard:=c.retard_minim_segons+floor(random()*(c.retard_maxim_segons-c.retard_minim_segons+1))::int; perform pg_sleep(retard); end if;
  end loop;
  update public.execucions_fitxatge_automatic_doble set finalitzat_el=clock_timestamp(),empleats_registrats=okc,empleats_omesos=omesos where id=exid;
end $$;

revoke all on function public.executar_fitxatge_automatic_doble() from public,anon,authenticated;

-- Versió del planificador actual amb cua de servidor.
create or replace function public.programar_fitxatges_automatics()
returns void language plpgsql security definer set search_path=public
as $$
declare
  c public.configuracio_fitxatge_automatic%rowtype;
  v_ara timestamp;
  v_dia date;
  v_etapa record;
  v_job uuid;
  v_programat timestamptz;
begin
  select * into c from public.configuracio_fitxatge_automatic where id=1;
  if c.id is null or not c.actiu then return; end if;
  v_ara := clock_timestamp() at time zone 'Europe/Madrid';
  v_dia := v_ara::date;
  if extract(isodow from v_dia)::smallint <> all(c.dies_setmana) then return; end if;

  for v_etapa in
    select * from (values
      ('entrada_1'::text,'entrada'::text,c.entrada_1),
      ('sortida_1','sortida',c.sortida_1),
      ('entrada_2','entrada',c.entrada_2),
      ('sortida_2','sortida',c.sortida_2)
    ) as x(etapa,tipus,hora)
    where v_etapa.etapa is not null
  loop
    if v_etapa.etapa in ('entrada_2','sortida_2') and c.jornada_mode<>'completa' then
      continue;
    end if;
    if v_etapa.hora is not null and v_ara::time >= v_etapa.hora and not exists(
      select 1 from public.fitxatge_automatic_execucions a where a.dia=v_dia and a.etapa=v_etapa.etapa
    ) then
      v_programat := ((v_dia::text||' '||v_etapa.hora::text)::timestamp at time zone 'Europe/Madrid');
      v_job := public.crear_job_fitxatge_intern(v_etapa.tipus,'automatic',v_etapa.etapa,null,null,v_programat);
      insert into public.fitxatge_automatic_execucions(dia,etapa,job_id) values(v_dia,v_etapa.etapa,v_job) on conflict do nothing;
    end if;
  end loop;
end $$;

grant execute on function public.programar_fitxatges_automatics() to postgres;

-- Si el cron final ja existeix, no cal crear-ne un altre. El tick actual farà servir la funció nova.
