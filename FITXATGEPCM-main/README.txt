PROJECTE CONNECTAT A SUPABASE

Aquest paquet ja porta configurada la URL i la clau publica del projecte Supabase. No hi ha cap clau secreta dins del projecte.

PCM FRUITS · FITXATGE

1. Executa supabase-setup.sql a Supabase (si ja ho has fet, no cal repetir-ho).
2. Obre app.js i posa:
   - SUPABASE_URL: URL del projecte (https://....supabase.co)
   - SUPABASE_ANON_KEY: clau pública sb_publishable_... (MAI sb_secret_...)
3. Crea l'administrador a Supabase > Authentication > Users.
4. Afegeix empleats a Table Editor > empleats.
5. Obre index.html amb Live Server o publica la carpeta a GitHub Pages.

NOVETATS DEL PANELL ADMIN:
- Buscador per nom o codi.
- Filtres per empleat, mes, dia i tipus.
- Exportació CSV dels registres filtrats.
- Exportació d'un resum diari per empleat amb primera entrada, última sortida i hores emparellades.
- Llista separable d'empleats actius i inactius.

NOVA GESTIO D'EMPLEATS
----------------------
1. A Supabase, obre SQL Editor.
2. Executa el fitxer ACTUALITZACIO-SUPABASE.sql una sola vegada.
3. Entra a l'admin de l'app.
4. Des de Gestio d'empleats podras crear, editar, activar i desactivar empleats.

No s'eliminen empleats per conservar l'historial. Quan un treballador marxa, desactiva'l.


NOVETATS V4
- En seleccionar un empleat al filtre de fitxatges, es mostra el total d'hores del mes.
- Calendari mensual amb els dies que tenen fitxatges marcats.
- Taula diària amb primera entrada, última sortida, hores calculades i nombre de fitxatges.
- No cal executar cap SQL nou.


IMPORTAR ELS 54 TREBALLADORS
----------------------------
1. Ves a Supabase > SQL Editor > New query.
2. Obre el fitxer IMPORTAR-TREBALLADORS-1-A-54.sql.
3. Copia tot el contingut, enganxa'l i prem Run.
4. Es crearan o actualitzaran els treballadors amb codis consecutius de l'1 al 54.
5. Tots quedaran marcats com a actius. Des de l'admin pots desactivar els que no treballin.

NOVETAT V6
- La gestió d'empleats incorpora un selector per ordenar per ID ascendent o descendent, o per nom.

VERSIO DEFINITIVA
-----------------
1. Executa ACTUALITZACIO-DEFINITIVA-SUPABASE.sql a Supabase > SQL Editor.
2. L'editor de jornades nomes es mostra i funciona per al compte admin@pcmfruits.com.
3. Les correccions substitueixen la jornada del dia i guarden una copia a auditoria_fitxatges.
4. Les categories de l'admin es poden obrir i tancar.
5. Al camp de fitxatge pots escriure un codi individual o un rang, per exemple 1-35.
6. Els rangs es processen un a un amb una espera aleatoria de 10 a 20 segons. La pagina ha de romandre oberta.
7. Per veure el logo a la pantalla d'inici, publica tots els fitxers (manifest.json, service-worker.js i assets) en HTTPS. Elimina l'acces directe antic i torna'l a crear.
8. En iPhone: Safari > Compartir > Afegir a la pantalla d'inici.
9. En Android: Chrome > menu > Afegir a la pantalla d'inici o Instal·lar aplicacio.

PORTAL DEL TREBALLADOR I DNI/NIE
--------------------------------
1. Executa ACTUALITZACIO-PORTAL-TREBALLADORS.sql a Supabase > SQL Editor.
2. La gestió d'empleats permet guardar i editar el DNI o NIE.
3. El Portal del treballador s'obre amb el codi de fitxatge i mostra només el calendari i registres del mes d'aquell treballador.
4. El DNI/NIE no es mostra al portal del treballador.
5. L'accés només amb codi és una identificació bàsica. Per a més seguretat, es recomana afegir un PIN personal diferent del codi de fitxatge.

FITXATGE MASSIU I AUTOMATIC
---------------------------
1. Executa ACTUALITZACIO-FITXATGE-AUTOMATIC.sql a Supabase > SQL Editor.
2. Aquesta actualitzacio permet crear jornades passades per a tots els empleats actius.
3. L'horari automatic nomes es pot configurar amb admin@pcmfruits.com.
4. Quan esta activat, Supabase fa l'entrada i la sortida de dilluns a divendres encara que la web estigui tancada.
5. Cada empleat actiu es processa amb una pausa aleatoria de 10 a 20 segons.
6. Els empleats inactius queden exclosos.
7. Si un empleat ja te el mateix ultim tipus de fitxatge, el sistema l'omet per evitar duplicats consecutius.
8. Per tornar al funcionament manual, desmarca "Activar fitxatge automatic" i guarda la configuracio.


ACTUALITZACIO DUES JORNADES
---------------------------
1. Executa ACTUALITZACIO-DUES-JORNADES-AUTOMATIC.sql a Supabase.
2. L'editor permet entrada 1, sortida 1, entrada 2 i sortida 2.
3. L'alta massiva de dies passats pot aplicar les dues jornades a un empleat o a tots els actius.
4. L'automatisme executa quatre tandes de dilluns a divendres, amb 10-20 segons entre empleats.
5. El fitxatge automàtic només afecta els empleats actius i només es configura amb admin@pcmfruits.com.
