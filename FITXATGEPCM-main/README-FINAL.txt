PCM FRUITS REGISTRE - VERSIO FINAL VERIFICADA

PASSOS OBLIGATORIS
1. A Supabase > SQL Editor, executa completament:
   ACTUALITZACIO-FINAL-CUA-AUTOMATIC.sql
2. A GitHub, substitueix tots els fitxers del projecte pels d'aquesta carpeta.
3. Espera que GitHub Pages es publiqui.
4. Tanca completament l'app i torna-la a obrir. Si manté la versió antiga, elimina l'accés directe i torna'l a crear.

CANVIS INCLOSOS
- Els fitxatges de grup es processen en una cua de Supabase i continuen amb l'app tancada.
- Pausa real de 10 a 20 segons entre treballadors.
- Els inactius s'ometen en crear la cua i es tornen a comprovar abans de cada fitxatge.
- Fitxatge automàtic doble de dilluns a divendres, executat al servidor.
- El cron comprova cada minut les etapes pendents i evita perdre una tanda.
- Botó Activar/Desactivar empleat reparat amb una funció segura.
- Codi ocult amb punts i botó per mostrar/amagar.
- Editor manual amb calendari mensual clicable.
- Es mantenen el fitxatge de diversos dies i l'opció de tots els actius.
- El gris del requadre del logotip coincideix amb el fons de la imatge (#454545).
- Notificacions locals quan l'app està oberta o en segon pla.

NOTIFICACIONS
El botó "Activar notificacions" demana permís al mòbil. L'avís de finalització pot arribar mentre la PWA segueix oberta o en segon pla. Per rebre avisos amb l'app completament tancada caldria afegir Web Push amb una Edge Function i claus VAPID; això no queda activat automàticament en aquest paquet perquè necessita secrets del teu projecte.

COMPROVACIO DEL CRON
Executa a Supabase:
select jobid,jobname,schedule,active from cron.job where jobname='pcm-fitxatge-backend-final';

Ha de sortir una fila activa amb schedule: * * * * *

COMPROVACIO DE CUES
select id,origen,etapa,estat,total,processats,correctes,errors,omesos,creat_el,finalitzat_el
from public.fitxatge_jobs
order by creat_el desc
limit 20;

COMPROVACIO DELS FITXATGES AUTOMATICS
select * from public.fitxatge_automatic_execucions order by dia desc,creat_el desc;

IMPORTANT
- No tornis a executar els SQL antics d'automatització després del SQL final, perquè podrien substituir la programació nova.
- La funció automàtica només inclou empleats actius.
- El compte exclusiu de l'editor i de l'automatització continua sent admin@pcmfruits.com.
