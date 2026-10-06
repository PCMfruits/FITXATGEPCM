-- PCM FRUITS REGISTRE - ACTUALITZACIO FINAL
-- Executar una sola vegada a Supabase > SQL Editor.

create extension if not exists pgcrypto;
create extension if not exists pg_cron;

-- Origen dels registres i relacio amb processos massius.
alter table public.fitxatges add column if not exists origen text not null default 'manual';
alter table public.fitxatges add column if not exists job_id uuid;

-- Cua de processos que continua al servidor encara que es tanqui l'app.
create table if not exists public.fitxatge_jobs (
  id uuid primary key default gen_random_uuid(),
  tipus text not null check (tipus in ('entrada','sortida')),
  origen text not null default 'grup',
  etapa text,
  estat text not null default 'pendent' check (estat in ('pendent','processant','completat','cancel_lada','error')),
  total integer not null default 0,
  processats integer not null default 0,
  correctes integer not null default 0,
  errors integer not null default 0,
  omesos integer not null default 0,
  creat_el timestamptz not null default now(),
  iniciat_el timestamptz,
  finalitzat_el timestamptz,
  sol_licitat_per text,
  missatge_error text
);

create table if not exists public.fitxatge_job_items (
  id bigint generated always as identity primary key,
  job_id uuid not null references public.fitxatge_jobs(id) on delete cascade,
  empleat_id bigint not null references public.empleats(id),
  codi text not null,
  tipus text not null check (tipus in ('entrada','sortida')),
  estat text not null default 'pendent' check (estat in ('pendent','correcte','error','omes','cancel_lat')),
  programat_per timestamptz,
  processat_el timestamptz,
  error_text text
);
create index if not exists fitxatge_job_items_job_estat_idx on public.fitxatge_job_items(job_id, estat, id);
create index if not exists fitxatge_jobs_estat_idx on public.fitxatge_jobs(estat, creat_el);

alter table public.fitxatge_jobs enable row level security;
alter table public.fitxatge_job_items enable row level security;

-- Funcio auxiliar per crear una cua amb empleats actius.
create or replace function public.crear_job_fitxatge_intern(
  p_tipus text,
  p_origen text,
  p_etapa text default null,
  p_codi_inici integer default null,
  p_codi_fi integer default null,
  p_programat_per timestamptz default null
) returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_job uuid;
  v_total integer;
  v_omesos integer := 0;
begin
  if p_tipus not in ('entrada','sortida') then raise exception 'TIPUS_INCORRECTE'; end if;

  insert into public.fitxatge_jobs(tipus, origen, etapa, sol_licitat_per)
  values (p_tipus, coalesce(p_origen,'grup'), p_etapa, coalesce(auth.jwt()->>'email','sistema'))
  returning id into v_job;

  insert into public.fitxatge_job_items(job_id, empleat_id, codi, tipus, programat_per)
  select v_job, e.id, e.codi, p_tipus, p_programat_per
  from public.empleats e
  where e.actiu = true
    and (p_codi_inici is null or (e.codi ~ '^\d+$' and e.codi::integer >= p_codi_inici))
    and (p_codi_fi is null or (e.codi ~ '^\d+$' and e.codi::integer <= p_codi_fi))
  order by case when e.codi ~ '^\d+$' then e.codi::integer else 2147483647 end, e.id;

  get diagnostics v_total = row_count;

  if p_codi_inici is not null and p_codi_fi is not null then
    v_omesos := greatest((p_codi_fi - p_codi_inici + 1) - v_total, 0);
  end if;

  update public.fitxatge_jobs set total=v_total, omesos=v_omesos where id=v_job;
  return v_job;
end;
$$;

-- Inicia un fitxatge de grup des del navegador. El proces queda al servidor.
create or replace function public.iniciar_fitxatge_grup_servidor(
  p_codi_inici integer,
  p_codi_fi integer,
  p_tipus text
) returns table(job_id uuid, total_actius integer, omitits integer)
language plpgsql
security definer
set search_path = public
as $$
declare v_job uuid;
begin
  if p_codi_inici < 1 or p_codi_fi < p_codi_inici or p_codi_fi-p_codi_inici > 199 then
    raise exception 'RANG_INCORRECTE';
  end if;
  v_job := public.crear_job_fitxatge_intern(p_tipus,'grup',null,p_codi_inici,p_codi_fi,null);
  return query select j.id,j.total,j.omesos from public.fitxatge_jobs j where j.id=v_job;
end;
$$;

grant execute on function public.iniciar_fitxatge_grup_servidor(integer,integer,text) to anon, authenticated;

create or replace function public.estat_fitxatge_grup_servidor(p_job_id uuid)
returns table(estat text,total integer,processats integer,correctes integer,errors integer,omesos integer)
language sql
security definer
set search_path = public
as $$
  select j.estat,j.total,j.processats,j.correctes,j.errors,j.omesos
  from public.fitxatge_jobs j where j.id=p_job_id;
$$;
grant execute on function public.estat_fitxatge_grup_servidor(uuid) to anon, authenticated;

create or replace function public.cancel_lar_fitxatge_grup_servidor(p_job_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.fitxatge_jobs set estat='cancel_lada',finalitzat_el=now()
  where id=p_job_id and estat in ('pendent','processant');
  update public.fitxatge_job_items set estat='cancel_lat',processat_el=now()
  where job_id=p_job_id and estat='pendent';
end;
$$;
grant execute on function public.cancel_lar_fitxatge_grup_servidor(uuid) to anon, authenticated;

-- Canvi d'estat segur d'empleats. Soluciona el boto Activar/Desactivar.
create or replace function public.admin_canviar_estat_empleat(p_empleat_id bigint,p_actiu boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'ADMIN_NO_AUTORITZAT'; end if;
  update public.empleats set actiu=coalesce(p_actiu,false) where id=p_empleat_id;
  if not found then raise exception 'EMPLEAT_NO_TROBAT'; end if;
end;
$$;
grant execute on function public.admin_canviar_estat_empleat(bigint,boolean) to authenticated;

-- Configuracio fiable del fitxatge automatic doble.
create table if not exists public.configuracio_fitxatge_automatic (
  id integer primary key,
  actiu boolean not null default false,
  entrada_1 time not null default '08:00',
  sortida_1 time not null default '13:00',
  entrada_2 time not null default '15:00',
  sortida_2 time not null default '17:00',
  dies_setmana smallint[] not null default array[1,2,3,4,5]::smallint[],
  actualitzat_el timestamptz not null default now()
);
alter table public.configuracio_fitxatge_automatic add column if not exists entrada_1 time;
alter table public.configuracio_fitxatge_automatic add column if not exists sortida_1 time;
alter table public.configuracio_fitxatge_automatic add column if not exists entrada_2 time;
alter table public.configuracio_fitxatge_automatic add column if not exists sortida_2 time;
alter table public.configuracio_fitxatge_automatic add column if not exists dies_setmana smallint[] default array[1,2,3,4,5]::smallint[];
insert into public.configuracio_fitxatge_automatic(id,actiu,entrada_1,sortida_1,entrada_2,sortida_2,dies_setmana)
values(1,false,'08:00','13:00','15:00','17:00',array[1,2,3,4,5]::smallint[])
on conflict(id) do nothing;
update public.configuracio_fitxatge_automatic set
 entrada_1=coalesce(entrada_1,'08:00'),sortida_1=coalesce(sortida_1,'13:00'),
 entrada_2=coalesce(entrada_2,'15:00'),sortida_2=coalesce(sortida_2,'17:00'),
 dies_setmana=coalesce(dies_setmana,array[1,2,3,4,5]::smallint[])
where id=1;

create table if not exists public.fitxatge_automatic_execucions (
  dia date not null,
  etapa text not null,
  job_id uuid references public.fitxatge_jobs(id),
  creat_el timestamptz not null default now(),
  primary key(dia,etapa)
);

create or replace function public.admin_obtenir_config_fitxatge_automatic_doble()
returns table(actiu boolean,entrada_1 time,sortida_1 time,entrada_2 time,sortida_2 time)
language plpgsql security definer set search_path=public
as $$
begin
  if lower(coalesce(auth.jwt()->>'email','')) <> 'admin@pcmfruits.com' then raise exception 'ADMIN_NO_AUTORITZAT'; end if;
  return query select c.actiu,c.entrada_1,c.sortida_1,c.entrada_2,c.sortida_2 from public.configuracio_fitxatge_automatic c where c.id=1;
end;$$;
grant execute on function public.admin_obtenir_config_fitxatge_automatic_doble() to authenticated;

create or replace function public.admin_guardar_config_fitxatge_automatic_doble(
 p_actiu boolean,p_entrada_1 time,p_sortida_1 time,p_entrada_2 time,p_sortida_2 time)
returns void language plpgsql security definer set search_path=public
as $$
begin
  if lower(coalesce(auth.jwt()->>'email','')) <> 'admin@pcmfruits.com' then raise exception 'ADMIN_NO_AUTORITZAT'; end if;
  if not (p_entrada_1 < p_sortida_1 and p_sortida_1 <= p_entrada_2 and p_entrada_2 < p_sortida_2) then raise exception 'HORARI_INCORRECTE'; end if;
  update public.configuracio_fitxatge_automatic set actiu=coalesce(p_actiu,false),entrada_1=p_entrada_1,sortida_1=p_sortida_1,entrada_2=p_entrada_2,sortida_2=p_sortida_2,dies_setmana=array[1,2,3,4,5]::smallint[],actualitzat_el=now() where id=1;
end;$$;
grant execute on function public.admin_guardar_config_fitxatge_automatic_doble(boolean,time,time,time,time) to authenticated;

-- Programa totes les etapes pendents del dia. Si el cron s'ha retardat, no les perd.
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
  loop
    if v_ara::time >= v_etapa.hora and not exists(select 1 from public.fitxatge_automatic_execucions a where a.dia=v_dia and a.etapa=v_etapa.etapa) then
      v_programat := ((v_dia::text||' '||v_etapa.hora::text)::timestamp at time zone 'Europe/Madrid');
      v_job := public.crear_job_fitxatge_intern(v_etapa.tipus,'automatic',v_etapa.etapa,null,null,v_programat);
      insert into public.fitxatge_automatic_execucions(dia,etapa,job_id) values(v_dia,v_etapa.etapa,v_job) on conflict do nothing;
    end if;
  end loop;
end;$$;

-- Worker independent del navegador. Revalida que l'empleat segueixi actiu.
create or replace function public.processar_cua_fitxatges()
returns void language plpgsql security definer set search_path=public
as $$
declare
  v_job public.fitxatge_jobs%rowtype;
  v_item public.fitxatge_job_items%rowtype;
  v_actiu boolean;
  v_ultim text;
  v_data timestamptz;
  v_delay double precision;
begin
  if not pg_try_advisory_lock(73425019) then return; end if;
  begin
    select * into v_job from public.fitxatge_jobs
    where estat in ('pendent','processant') order by creat_el for update skip locked limit 1;
    if v_job.id is null then perform pg_advisory_unlock(73425019); return; end if;
    update public.fitxatge_jobs set estat='processant',iniciat_el=coalesce(iniciat_el,now()) where id=v_job.id;

    for v_item in select * from public.fitxatge_job_items where job_id=v_job.id and estat='pendent' order by id loop
      if exists(select 1 from public.fitxatge_jobs where id=v_job.id and estat='cancel_lada') then exit; end if;
      select e.actiu into v_actiu from public.empleats e where e.id=v_item.empleat_id;
      if coalesce(v_actiu,false)=false then
        update public.fitxatge_job_items set estat='omes',processat_el=now(),error_text='EMPLEAT_INACTIU' where id=v_item.id;
        update public.fitxatge_jobs set processats=processats+1,omesos=omesos+1 where id=v_job.id;
        continue;
      end if;

      begin
        select f.tipus into v_ultim from public.fitxatges f where f.empleat_id=v_item.empleat_id order by f.data_hora desc limit 1;
        if v_ultim=v_item.tipus then raise exception 'FITXATGE_DUPLICAT'; end if;
        v_data := case when v_item.programat_per is null then clock_timestamp() else greatest(v_item.programat_per,clock_timestamp()) end;
        insert into public.fitxatges(empleat_id,tipus,data_hora,origen,job_id)
        values(v_item.empleat_id,v_item.tipus,v_data,v_job.origen,v_job.id);
        update public.fitxatge_job_items set estat='correcte',processat_el=now() where id=v_item.id;
        update public.fitxatge_jobs set processats=processats+1,correctes=correctes+1 where id=v_job.id;
      exception when others then
        update public.fitxatge_job_items set estat='error',processat_el=now(),error_text=sqlerrm where id=v_item.id;
        update public.fitxatge_jobs set processats=processats+1,errors=errors+1 where id=v_job.id;
      end;

      if exists(select 1 from public.fitxatge_job_items where job_id=v_job.id and estat='pendent') then
        v_delay := 10 + random()*10;
        perform pg_sleep(v_delay);
      end if;
    end loop;

    update public.fitxatge_jobs set
      estat=case when estat='cancel_lada' then estat else 'completat' end,
      finalitzat_el=now()
    where id=v_job.id;
  exception when others then
    update public.fitxatge_jobs set estat='error',finalitzat_el=now(),missatge_error=sqlerrm where id=v_job.id;
  end;
  perform pg_advisory_unlock(73425019);
end;$$;

create or replace function public.tick_fitxatge_backend()
returns void language plpgsql security definer set search_path=public
as $$ begin
  perform public.programar_fitxatges_automatics();
  perform public.processar_cua_fitxatges();
end; $$;

-- Eliminar programacions antigues i crear una sola tasca fiable.
do $$ declare r record; begin
  for r in select jobid from cron.job where jobname in ('pcm-fitxatge-automatic-cada-minut','pcm-fitxatge-automatic-doble','pcm-fitxatge-backend-final') loop
    perform cron.unschedule(r.jobid);
  end loop;
end $$;
select cron.schedule('pcm-fitxatge-backend-final','* * * * *','select public.tick_fitxatge_backend();');

-- Permisos basics.
grant execute on function public.tick_fitxatge_backend() to postgres;
grant execute on function public.processar_cua_fitxatges() to postgres;
grant execute on function public.programar_fitxatges_automatics() to postgres;

-- Diagnosi rapida: executa aquest SELECT si vols comprovar l'estat.
-- select * from cron.job where jobname='pcm-fitxatge-backend-final';
-- select * from public.fitxatge_jobs order by creat_el desc limit 20;
