-- PCM FRUITS · DUES JORNADES I FITXATGE AUTOMATIC
-- Executa aquest fitxer a Supabase > SQL Editor després de les actualitzacions anteriors.

alter table public.configuracio_fitxatge_automatic
  add column if not exists entrada_1 time default '08:00',
  add column if not exists sortida_1 time default '13:00',
  add column if not exists entrada_2 time default '15:00',
  add column if not exists sortida_2 time default '17:00';

update public.configuracio_fitxatge_automatic
set entrada_1=coalesce(entrada_1,'08:00'), sortida_1=coalesce(sortida_1,'13:00'),
    entrada_2=coalesce(entrada_2,'15:00'), sortida_2=coalesce(sortida_2,'17:00')
where id=1;

create table if not exists public.execucions_fitxatge_automatic_doble (
  id bigint generated always as identity primary key,
  data_execucio date not null,
  etapa text not null check (etapa in ('entrada_1','sortida_1','entrada_2','sortida_2')),
  iniciat_el timestamptz not null default now(),
  finalitzat_el timestamptz,
  empleats_registrats integer not null default 0,
  empleats_omesos integer not null default 0,
  unique(data_execucio, etapa)
);
alter table public.execucions_fitxatge_automatic_doble enable row level security;
revoke all on public.execucions_fitxatge_automatic_doble from anon, authenticated;

drop policy if exists "Admin principal consulta execucions automatic doble" on public.execucions_fitxatge_automatic_doble;
create policy "Admin principal consulta execucions automatic doble"
on public.execucions_fitxatge_automatic_doble for select to authenticated
using (lower(coalesce(auth.jwt()->>'email',''))='admin@pcmfruits.com');

create or replace function public.admin_obtenir_jornada_doble(p_empleat_id bigint, p_data date)
returns table (entrada_1 time, sortida_1 time, entrada_2 time, sortida_2 time)
language plpgsql security definer set search_path=public
as $$
begin
  if not public.es_admin_principal() then raise exception 'ADMIN_NO_AUTORITZAT'; end if;
  return query
  with x as (
    select f.tipus, (f.data_hora at time zone 'Europe/Madrid')::time as hora,
      row_number() over(partition by f.tipus order by f.data_hora) as rn
    from public.fitxatges f
    where f.empleat_id=p_empleat_id
      and (f.data_hora at time zone 'Europe/Madrid')::date=p_data
  )
  select
    max(hora) filter(where tipus='entrada' and rn=1),
    max(hora) filter(where tipus='sortida' and rn=1),
    max(hora) filter(where tipus='entrada' and rn=2),
    max(hora) filter(where tipus='sortida' and rn=2)
  from x;
end;
$$;
revoke all on function public.admin_obtenir_jornada_doble(bigint,date) from public,anon;
grant execute on function public.admin_obtenir_jornada_doble(bigint,date) to authenticated;

create or replace function public.admin_guardar_jornada_doble(
  p_empleat_id bigint, p_data date,
  p_entrada_1 time, p_sortida_1 time, p_entrada_2 time, p_sortida_2 time,
  p_motiu text
) returns void
language plpgsql security definer set search_path=public
as $$
declare
  v_email text:=lower(coalesce(auth.jwt()->>'email',''));
  v_abans jsonb;
  v_e1 timestamptz; v_s1 timestamptz; v_e2 timestamptz; v_s2 timestamptz;
begin
  if v_email<>'admin@pcmfruits.com' then raise exception 'ADMIN_NO_AUTORITZAT'; end if;
  if p_data>(now() at time zone 'Europe/Madrid')::date then raise exception 'DATA_FUTURA_NO_PERMESA'; end if;
  if trim(coalesce(p_motiu,''))='' then raise exception 'MOTIU_OBLIGATORI'; end if;
  if not exists(select 1 from public.empleats where id=p_empleat_id) then raise exception 'EMPLEAT_INEXISTENT'; end if;
  if not (p_entrada_1<p_sortida_1 and p_sortida_1<=p_entrada_2 and p_entrada_2<p_sortida_2) then
    raise exception 'HORARI_DOBLE_INVALID';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'tipus',f.tipus,'data_hora',f.data_hora) order by f.data_hora),'[]'::jsonb)
  into v_abans from public.fitxatges f
  where f.empleat_id=p_empleat_id and (f.data_hora at time zone 'Europe/Madrid')::date=p_data;

  v_e1:=make_timestamptz(extract(year from p_data)::int,extract(month from p_data)::int,extract(day from p_data)::int,extract(hour from p_entrada_1)::int,extract(minute from p_entrada_1)::int,0,'Europe/Madrid');
  v_s1:=make_timestamptz(extract(year from p_data)::int,extract(month from p_data)::int,extract(day from p_data)::int,extract(hour from p_sortida_1)::int,extract(minute from p_sortida_1)::int,0,'Europe/Madrid');
  v_e2:=make_timestamptz(extract(year from p_data)::int,extract(month from p_data)::int,extract(day from p_data)::int,extract(hour from p_entrada_2)::int,extract(minute from p_entrada_2)::int,0,'Europe/Madrid');
  v_s2:=make_timestamptz(extract(year from p_data)::int,extract(month from p_data)::int,extract(day from p_data)::int,extract(hour from p_sortida_2)::int,extract(minute from p_sortida_2)::int,0,'Europe/Madrid');

  delete from public.fitxatges where empleat_id=p_empleat_id and (data_hora at time zone 'Europe/Madrid')::date=p_data;
  insert into public.fitxatges(empleat_id,tipus,data_hora) values
    (p_empleat_id,'entrada',v_e1),(p_empleat_id,'sortida',v_s1),
    (p_empleat_id,'entrada',v_e2),(p_empleat_id,'sortida',v_s2);

  insert into public.auditoria_fitxatges(empleat_id,data_jornada,accio,dades_anteriors,dades_noves,motiu,admin_email)
  values(p_empleat_id,p_data,'crear_o_reemplaçar',v_abans,
    jsonb_build_array(
      jsonb_build_object('tipus','entrada','data_hora',v_e1),jsonb_build_object('tipus','sortida','data_hora',v_s1),
      jsonb_build_object('tipus','entrada','data_hora',v_e2),jsonb_build_object('tipus','sortida','data_hora',v_s2)
    ),trim(p_motiu),v_email);
end;
$$;
revoke all on function public.admin_guardar_jornada_doble(bigint,date,time,time,time,time,text) from public,anon;
grant execute on function public.admin_guardar_jornada_doble(bigint,date,time,time,time,time,text) to authenticated;

create or replace function public.admin_guardar_jornades_massives_dobles(
  p_empleat_id bigint, p_tots_actius boolean, p_data_inici date, p_data_fi date,
  p_dies_setmana integer[], p_entrada_1 time, p_sortida_1 time, p_entrada_2 time, p_sortida_2 time, p_motiu text
) returns table(empleats_processats integer,jornades_creades integer)
language plpgsql security definer set search_path=public
as $$
declare v_email text:=lower(coalesce(auth.jwt()->>'email','')); v_emp record; v_data date; v_ec int:=0; v_jc int:=0;
begin
  if v_email<>'admin@pcmfruits.com' then raise exception 'ADMIN_NO_AUTORITZAT'; end if;
  if p_data_inici is null or p_data_fi is null or p_data_inici>p_data_fi then raise exception 'DATES_INVALIDES'; end if;
  if p_data_fi>(now() at time zone 'Europe/Madrid')::date then raise exception 'DATA_FUTURA_NO_PERMESA'; end if;
  if not(p_entrada_1<p_sortida_1 and p_sortida_1<=p_entrada_2 and p_entrada_2<p_sortida_2) then raise exception 'HORARI_DOBLE_INVALID'; end if;
  if trim(coalesce(p_motiu,''))='' then raise exception 'MOTIU_OBLIGATORI'; end if;
  if coalesce(array_length(p_dies_setmana,1),0)=0 then raise exception 'DIES_SETMANA_OBLIGATORIS'; end if;
  if not coalesce(p_tots_actius,false) and p_empleat_id is null then raise exception 'EMPLEAT_OBLIGATORI'; end if;

  for v_emp in select e.id from public.empleats e
    where (coalesce(p_tots_actius,false) and e.actiu=true)
       or (not coalesce(p_tots_actius,false) and e.id=p_empleat_id)
    order by e.id
  loop
    v_ec:=v_ec+1; v_data:=p_data_inici;
    while v_data<=p_data_fi loop
      if extract(dow from v_data)::integer=any(p_dies_setmana) then
        perform public.admin_guardar_jornada_doble(v_emp.id,v_data,p_entrada_1,p_sortida_1,p_entrada_2,p_sortida_2,
          trim(p_motiu)||case when coalesce(p_tots_actius,false) then ' · alta massiva empleats actius' else '' end);
        v_jc:=v_jc+1;
      end if;
      v_data:=v_data+1;
    end loop;
  end loop;
  return query select v_ec,v_jc;
end;
$$;
revoke all on function public.admin_guardar_jornades_massives_dobles(bigint,boolean,date,date,integer[],time,time,time,time,text) from public,anon;
grant execute on function public.admin_guardar_jornades_massives_dobles(bigint,boolean,date,date,integer[],time,time,time,time,text) to authenticated;

create or replace function public.admin_obtenir_config_fitxatge_automatic_doble()
returns table(actiu boolean,entrada_1 time,sortida_1 time,entrada_2 time,sortida_2 time,dies_setmana smallint[],retard_minim_segons smallint,retard_maxim_segons smallint,actualitzat_el timestamptz)
language plpgsql security definer set search_path=public
as $$ begin
  if lower(coalesce(auth.jwt()->>'email',''))<>'admin@pcmfruits.com' then raise exception 'ADMIN_NO_AUTORITZAT'; end if;
  return query select c.actiu,c.entrada_1,c.sortida_1,c.entrada_2,c.sortida_2,c.dies_setmana,c.retard_minim_segons,c.retard_maxim_segons,c.actualitzat_el
  from public.configuracio_fitxatge_automatic c where c.id=1;
end $$;
revoke all on function public.admin_obtenir_config_fitxatge_automatic_doble() from public,anon;
grant execute on function public.admin_obtenir_config_fitxatge_automatic_doble() to authenticated;

create or replace function public.admin_guardar_config_fitxatge_automatic_doble(p_actiu boolean,p_entrada_1 time,p_sortida_1 time,p_entrada_2 time,p_sortida_2 time)
returns void language plpgsql security definer set search_path=public
as $$ declare v_email text:=lower(coalesce(auth.jwt()->>'email','')); begin
  if v_email<>'admin@pcmfruits.com' then raise exception 'ADMIN_NO_AUTORITZAT'; end if;
  if not(p_entrada_1<p_sortida_1 and p_sortida_1<=p_entrada_2 and p_entrada_2<p_sortida_2) then raise exception 'HORARI_DOBLE_INVALID'; end if;
  update public.configuracio_fitxatge_automatic set actiu=coalesce(p_actiu,false),entrada_1=p_entrada_1,sortida_1=p_sortida_1,entrada_2=p_entrada_2,sortida_2=p_sortida_2,
    dies_setmana=array[1,2,3,4,5]::smallint[],retard_minim_segons=10,retard_maxim_segons=20,actualitzat_per=v_email,actualitzat_el=now() where id=1;
end $$;
revoke all on function public.admin_guardar_config_fitxatge_automatic_doble(boolean,time,time,time,time) from public,anon;
grant execute on function public.admin_guardar_config_fitxatge_automatic_doble(boolean,time,time,time,time) to authenticated;

create or replace function public.executar_fitxatge_automatic_doble()
returns void language plpgsql security definer set search_path=public
as $$
declare
  c public.configuracio_fitxatge_automatic%rowtype; ara timestamp; dia date; minut int; etapa text; tipus text; hora_obj time;
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
  elsif minut between extract(hour from c.entrada_2)::int*60+extract(minute from c.entrada_2)::int and extract(hour from c.entrada_2)::int*60+extract(minute from c.entrada_2)::int+59 then etapa:='entrada_2'; tipus:='entrada'; hora_obj:=c.entrada_2;
  elsif minut between extract(hour from c.sortida_2)::int*60+extract(minute from c.sortida_2)::int and extract(hour from c.sortida_2)::int*60+extract(minute from c.sortida_2)::int+59 then etapa:='sortida_2'; tipus:='sortida'; hora_obj:=c.sortida_2;
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

create extension if not exists pg_cron;
do $$ declare j record; begin
  for j in select jobid from cron.job where jobname in ('pcm-fitxatge-automatic-cada-minut','pcm-fitxatge-automatic-doble') loop perform cron.unschedule(j.jobid); end loop;
end $$;
select cron.schedule('pcm-fitxatge-automatic-doble','* * * * *','select public.executar_fitxatge_automatic_doble();');
