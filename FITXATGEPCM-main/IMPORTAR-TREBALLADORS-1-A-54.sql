-- IMPORTACIO DE TREBALLADORS PCM FRUITS
-- Executa aquest fitxer una sola vegada a Supabase > SQL Editor > Run.
-- Assigna els codis de fitxatge de l'1 al 54 seguint l'ordre del llistat aportat.
-- Si ja existeix algun codi, actualitza el nom i el deixa actiu.

begin;

insert into public.empleats (nom, codi, actiu) values
  ('CALZADA MORE, PERE', '1', true),
  ('BARADAI, MBAREK', '2', true),
  ('EL JMEL, MOUSTAPHA', '3', true),
  ('CALZADA LOPEZ, PERE', '4', true),
  ('AZZOUZI, KHLIFA', '5', true),
  ('JAOUDI, EL MAHFOUD', '6', true),
  ('BAKHSIS, SAID', '7', true),
  ('CALZADA LOPEZ, PAU', '8', true),
  ('BENHAMMOU, BOUSSELHAM', '9', true),
  ('EL BOUKHARI, ABDELAZIZ', '10', true),
  ('LAQSIR, ABDELLAH', '11', true),
  ('ZARROUK, BASSIM', '12', true),
  ('SIDIBE, DJIBRIL', '13', true),
  ('DIAKITE, MADY', '14', true),
  ('DIAKITE, MOUSSA', '15', true),
  ('SIDIBE, MAMADOU', '16', true),
  ('SIDIBE, MAMADOU', '17', true),
  ('ZERIFI, BOUYAKOUB', '18', true),
  ('BOUAZIZ, ABDELHAQ', '19', true),
  ('ELHIBA, FADOUL', '20', true),
  ('NOURI, ABDELLAH', '21', true),
  ('SABRI, AHMED', '22', true),
  ('HABBOUBI, ABDERRAHIM', '23', true),
  ('SIDIBE, BOURAMA', '24', true),
  ('MANSSOURI MENSSOURI, LAKDAR', '25', true),
  ('KENNAB, AHMED', '26', true),
  ('TRAORE, SADIO', '27', true),
  ('MEJNOUN, AHMED', '28', true),
  ('DEROUICH, HOUMMADA', '29', true),
  ('MACALOU, DIBY', '30', true),
  ('BOUDAHMANI MOURAD', '31', true),
  ('DIARRA, BALLAKE', '32', true),
  ('BELGHALEM, SADIQ', '33', true),
  ('EL GHOUL, RACHID', '34', true),
  ('EL KERRAOUI, MOHAMED', '35', true),
  ('DRAZ, AHMED', '36', true),
  ('SIDIBE, YAHIA', '37', true),
  ('MAAGUI, MOHAMED', '38', true),
  ('EZ ZAHIRI, HASSAN', '39', true),
  ('EZZAHIRI, ABDERRAHMAN', '40', true),
  ('DIARRA, HOURO', '41', true),
  ('LAZAAR, ABDELJALIL', '42', true),
  ('EN NASIRI, REDA', '43', true),
  ('EN NASIRI, REDWANE', '44', true),
  ('TANDIA, ISSA', '45', true),
  ('MAKHLOUF, ABDERRAHIM', '46', true),
  ('SIDIBE, TOUMANY', '47', true),
  ('DELLAOUI, AZIZ', '48', true),
  ('EL MOKHTARI, RACHID', '49', true),
  ('BOUMALOUI, BOUSSELHAM', '50', true),
  ('EL ALAOUI, KHALID', '51', true),
  ('COULIBALY LASSINE', '52', true),
  ('EL ANAYA, MBAREK', '53', true),
  ('AZZOUZI, OUSSAMA', '54', true)
on conflict (codi) do update
set nom = excluded.nom,
    actiu = excluded.actiu;

commit;

-- Comprovacio final:
select codi, nom, actiu
from public.empleats
where codi ~ '^[0-9]+$'
  and codi::integer between 1 and 54
order by codi::integer;
