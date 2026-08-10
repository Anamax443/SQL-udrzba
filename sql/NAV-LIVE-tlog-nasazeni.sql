/*==============================================================================
  NAV-LIVE — nasazeni nepretrzitych zaloh transakcniho logu
  Server: B-S-W-SQL-01 | Databaze: NAV-LIVE | 2026-08-10

  POSTUP: casti se spousteji POSTUPNE, ne najednou.
  Cast 1-2  = diagnostika a priprava, nic nemeni
  Cast 3-5  = zalozeni jobu, job je zatim VYPNUTY
  Cast 6    = rucni test
  Cast 7    = zapnuti
  Cast 8    = AZ PO DVOU USPESNYCH BEZICH - vypnuti starych jobu
  Cast 9    = alert
  Cast 10   = denni kontrola
  Cast 11   = oprava COPY_ONLY (samostatne rozhodnuti)

  PROMENNE K DOPLNENI:
    <CILOVA_CESTA>  = G:\Backup\NAV-LIVE\TLog
    <MAIL>          = it_admins@axima.cz
    <PROFIL>        = SQLMailForNotification
==============================================================================*/


/*==============================================================================
  CAST 1 — DIAGNOSTIKA DATABASE MAIL           [jen cteni]
==============================================================================*/

-- 1.1 Stav odeslanych mailu (opravena verze - bez ambiguity)
SELECT TOP 10 mailitem_id, LEFT(recipients,40) AS prijemce, LEFT(subject,40) AS predmet,
       sent_status, sent_date
FROM msdb.dbo.sysmail_allitems
ORDER BY mailitem_id DESC;

-- 1.2 Chybovy log Database Mail
SELECT TOP 15 log_date, event_type, LEFT(description, 300) AS popis
FROM msdb.dbo.sysmail_event_log
ORDER BY log_id DESC;

-- 1.3 Pouziva SQL Agent Database Mail?  UseDatabaseMail musi byt 1
--     (vysledek je v zalozce RESULTS, ne Messages)
EXEC master.dbo.xp_instance_regread
     N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent', N'UseDatabaseMail';
EXEC master.dbo.xp_instance_regread
     N'HKEY_LOCAL_MACHINE', N'SOFTWARE\Microsoft\MSSQLServer\SQLServerAgent', N'DatabaseMailProfile';
GO


/*==============================================================================
  CAST 2 — PRIPRAVA CILE                        [jen cteni]
==============================================================================*/

-- 2.1 Existuje cilovy adresar?
--     Vysledek: File Exists=0, File is a Directory=1, Parent Directory Exists=1
EXEC master.dbo.xp_fileexist N'<CILOVA_CESTA>';
GO

-- 2.2 KAM dnes chodi zalohy logu? (odhali vsechny soucasne vetve retezu)
SELECT LEFT(LEFT(mf.physical_device_name,
         LEN(mf.physical_device_name)-CHARINDEX('\',REVERSE(mf.physical_device_name))),70) AS slozka,
       COUNT(*) AS poc,
       CONVERT(varchar(19), MIN(b.backup_finish_date),120) AS od,
       CONVERT(varchar(19), MAX(b.backup_finish_date),120) AS do_
FROM msdb.dbo.backupset b
JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = b.media_set_id
WHERE b.database_name='NAV-LIVE' AND b.type='L'
  AND b.backup_finish_date > DATEADD(DAY,-7,GETDATE())
GROUP BY LEFT(LEFT(mf.physical_device_name,
         LEN(mf.physical_device_name)-CHARINDEX('\',REVERSE(mf.physical_device_name))),70)
ORDER BY do_ DESC;
GO

-- 2.3 Ktery job vyrabi tu full zalohu do NAV-TEST-USERS (kvuli casti 11)
SELECT j.name AS job, s.step_id, s.step_name, LEFT(s.command, 500) AS prikaz
FROM msdb.dbo.sysjobsteps s
JOIN msdb.dbo.sysjobs j ON j.job_id = s.job_id
WHERE s.command LIKE N'%NAV-TEST-USERS%'
   OR s.command LIKE N'%BACKUP DATABASE%';
GO


/*==============================================================================
  CAST 3 — ZALOZENI JOBU                        [meni, job je VYPNUTY]
==============================================================================*/

USE [msdb];
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'BC_Backup_TLog_Continuous')
BEGIN
    RAISERROR('Job uz existuje - nic nedelam. Nejdriv zkontroluj proc.', 16, 1);
    RETURN;
END
GO

EXEC msdb.dbo.sp_add_job
     @job_name    = N'BC_Backup_TLog_Continuous',
     @enabled     = 0,                       -- zamerne vypnuty
     @description = N'Zaloha transakcniho logu NAV-LIVE, kazdych 15 minut 24/7. '
                  + N'Zamerne MIMO maintenance plan - ten pri ulozeni v designeru prepisuje schedule. '
                  + N'Zalozeno 2026-08-10 po incidentu 9002.',
     @notify_level_eventlog = 2,             -- do event logu jen pri selhani
     @notify_level_email    = 2;             -- mail pri selhani
GO


/*==============================================================================
  CAST 4 — KROK ZALOHY
  - jeden soubor na jednu zalohu, casove razitko vc. milisekund
  - COMPRESSION + CHECKSUM
  - ZADNY CONTINUE_AFTER_ERROR (to patri jen do havarijni tail-log zalohy)
  - kontrola FULL recovery pred zalohou
==============================================================================*/

EXEC msdb.dbo.sp_add_jobstep
     @job_name       = N'BC_Backup_TLog_Continuous',
     @step_name      = N'Backup TLog',
     @step_id        = 1,
     @subsystem      = N'TSQL',
     @database_name  = N'master',
     @retry_attempts = 2,
     @retry_interval = 1,
     @on_success_action = 1,                 -- quit reporting success
     @on_fail_action    = 2,                 -- quit reporting failure
     @command = N'
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @dir  nvarchar(260) = N''<CILOVA_CESTA>\'';
DECLARE @file nvarchar(400);
DECLARE @db   sysname       = N''NAV-LIVE'';

/* 1) Databaze musi existovat a byt online */
IF DB_ID(@db) IS NULL
BEGIN
    RAISERROR(''Databaze NAV-LIVE neexistuje.'', 16, 1);
    RETURN;
END

IF DATABASEPROPERTYEX(@db, ''Status'') <> ''ONLINE''
BEGIN
    RAISERROR(''Databaze NAV-LIVE neni ONLINE - zaloha logu preskocena.'', 16, 1);
    RETURN;
END

/* 2) Musi byt ve FULL recovery, jinak zaloha logu nema smysl */
IF DATABASEPROPERTYEX(@db, ''Recovery'') <> ''FULL''
BEGIN
    RAISERROR(''NAV-LIVE neni ve FULL recovery - zaloha logu prerusena.'', 16, 1);
    RETURN;
END

/* 3) Jmeno souboru s casovym razitkem vc. milisekund
      (kolize jmena by se TISE pripojila do tehoz media setu) */
SET @file = @dir + N''NAV-LIVE_log_'' +
            REPLACE(REPLACE(REPLACE(REPLACE(
              CONVERT(varchar(23), GETDATE(), 121), ''-'', ''''), '' '', ''_''), '':'', ''''), ''.'', '''') +
            N''.trn'';

/* 4) Vlastni zaloha */
BACKUP LOG [NAV-LIVE]
TO DISK = @file
WITH COMPRESSION, CHECKSUM, STATS = 0;

PRINT ''OK: '' + @file;
';
GO


/*==============================================================================
  CAST 5 — SCHEDULE A OPERATOR
==============================================================================*/

-- 5.1 Kazdych 15 minut, kazdy den, cely den
EXEC msdb.dbo.sp_add_jobschedule
     @job_name             = N'BC_Backup_TLog_Continuous',
     @name                 = N'Kazdych 15 minut 24/7',
     @enabled              = 1,
     @freq_type            = 4,      -- denne (ne tydne se seznamem dnu - nelze omylem odskrtnout den)
     @freq_interval        = 1,
     @freq_subday_type     = 4,      -- minuty
     @freq_subday_interval = 15,
     @active_start_date    = 20260810,
     @active_start_time    = 000000,
     @active_end_time      = 235959;
GO

-- 5.2 Komu poslat mail pri selhani
EXEC msdb.dbo.sp_update_job
     @job_name                = N'BC_Backup_TLog_Continuous',
     @notify_level_email      = 2,   -- 2 = pri selhani
     @notify_email_operator_name = N'AdminOperatorRobot';
GO

-- 5.3 Registrace na server
EXEC msdb.dbo.sp_add_jobserver @job_name = N'BC_Backup_TLog_Continuous';
GO

-- 5.4 Kontrola, jak to dopadlo
SELECT j.name, j.enabled AS job_zap, s.name AS schedule, s.enabled AS sch_zap,
       s.freq_subday_interval AS interval_min,
       STUFF(STUFF(RIGHT('000000'+CAST(s.active_start_time AS varchar(6)),6),5,0,':'),3,0,':') AS od,
       STUFF(STUFF(RIGHT('000000'+CAST(s.active_end_time   AS varchar(6)),6),5,0,':'),3,0,':') AS do_
FROM msdb.dbo.sysjobs j
LEFT JOIN msdb.dbo.sysjobschedules js ON js.job_id = j.job_id
LEFT JOIN msdb.dbo.sysschedules    s  ON s.schedule_id = js.schedule_id
WHERE j.name = N'BC_Backup_TLog_Continuous';
GO


/*==============================================================================
  CAST 6 — RUCNI TEST                           [job je porad vypnuty]
==============================================================================*/

EXEC msdb.dbo.sp_start_job @job_name = N'BC_Backup_TLog_Continuous';
GO
WAITFOR DELAY '00:00:30';
GO

-- 6.1 Dopadl krok dobre?
SELECT TOP 5
       CASE h.run_status WHEN 0 THEN 'FAILED' WHEN 1 THEN 'OK' ELSE CAST(h.run_status AS varchar(2)) END AS stav,
       h.step_id, h.step_name,
       msdb.dbo.agent_datetime(h.run_date, h.run_time) AS start_,
       LEFT(h.message, 400) AS zprava
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
WHERE j.name = N'BC_Backup_TLog_Continuous'
ORDER BY h.instance_id DESC;
GO

-- 6.2 Vznikl novy soubor na spravnem miste?
SELECT TOP 3 CONVERT(varchar(23), b.backup_finish_date, 121) AS kdy,
       CAST(b.backup_size/1024.0/1024 AS decimal(10,1))            AS raw_mb,
       CAST(b.compressed_backup_size/1024.0/1024 AS decimal(10,1)) AS na_disku_mb,
       b.first_lsn, b.last_lsn,
       mf.physical_device_name AS soubor
FROM msdb.dbo.backupset b
JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = b.media_set_id
WHERE b.database_name = 'NAV-LIVE' AND b.type = 'L'
ORDER BY b.backup_finish_date DESC;
GO

-- 6.3 Je ten soubor skutecne citelny?  (doplnit cestu z 6.2)
-- RESTORE VERIFYONLY FROM DISK = N'<novy_soubor>' WITH CHECKSUM;
-- RESTORE HEADERONLY FROM DISK = N'<novy_soubor>';


/*==============================================================================
  CAST 7 — ZAPNUTI                              [od ted bezi automaticky]
==============================================================================*/

EXEC msdb.dbo.sp_update_job @job_name = N'BC_Backup_TLog_Continuous', @enabled = 1;
GO

SELECT name, enabled FROM msdb.dbo.sysjobs WHERE name = N'BC_Backup_TLog_Continuous';
GO


/*==============================================================================
  CAST 8 — VYPNUTI STARYCH JOBU
  !!! AZ PO DVOU USPESNYCH AUTOMATICKYCH BEZICH — tedy nejdriv za 30 minut !!!
  Duvod: dokud nova vetev neprokaze, ze bezi, nesmi se stara vypnout.
==============================================================================*/

-- 8.1 KONTROLA - musi vratit aspon 2
SELECT COUNT(*) AS uspesnych_behu_dnes
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
WHERE j.name = N'BC_Backup_TLog_Continuous'
  AND h.step_id = 0                      -- 0 = vysledek celeho jobu
  AND h.run_status = 1                   -- 1 = uspech
  AND h.run_date >= CONVERT(int, CONVERT(varchar(8), GETDATE(), 112));
GO

-- 8.2 Teprve kdyz vyslo >= 2:
EXEC msdb.dbo.sp_update_job @job_name = N'BackupMaintenancePlan.Tlog',  @enabled = 0;
EXEC msdb.dbo.sp_update_job @job_name = N'BackupMaintenancePlan.Tlog2', @enabled = 0;
GO

-- 8.3 Kontrola stavu vsech tri
SELECT name, CASE enabled WHEN 1 THEN 'ZAPNUT' ELSE 'vypnut' END AS stav
FROM msdb.dbo.sysjobs
WHERE name IN (N'BC_Backup_TLog_Continuous',
               N'BackupMaintenancePlan.Tlog',
               N'BackupMaintenancePlan.Tlog2');
GO

/* ZPET, kdyby bylo potreba:
EXEC msdb.dbo.sp_update_job @job_name = N'BackupMaintenancePlan.Tlog',  @enabled = 1;
EXEC msdb.dbo.sp_update_job @job_name = N'BackupMaintenancePlan.Tlog2', @enabled = 1;
EXEC msdb.dbo.sp_update_job @job_name = N'BC_Backup_TLog_Continuous',   @enabled = 0;
*/


/*==============================================================================
  CAST 9 — ALERT
  Hlida tri veci najednou: stari zalohy logu, zaplneni logu, log_reuse_wait.
  Bezi kazdych 30 minut. Mail posle jen kdyz je neco spatne.
==============================================================================*/

EXEC msdb.dbo.sp_add_job
     @job_name    = N'BC_Monitor_TLog_Health',
     @enabled     = 1,
     @description = N'Hlidac zaloh transakcniho logu NAV-LIVE. Posila mail jen pri problemu.';
GO

EXEC msdb.dbo.sp_add_jobstep
     @job_name      = N'BC_Monitor_TLog_Health',
     @step_name     = N'Check',
     @step_id       = 1,
     @subsystem     = N'TSQL',
     @database_name = N'master',
     @command = N'
SET NOCOUNT ON;

DECLARE @stari        int,
        @reuse        nvarchar(60),
        @pct          decimal(5,1),
        @potize       nvarchar(2000) = N'''',
        @predmet      nvarchar(200);

/* 1) Stari posledni zalohy logu */
SELECT @stari = DATEDIFF(MINUTE, MAX(backup_finish_date), GETDATE())
FROM msdb.dbo.backupset
WHERE database_name = ''NAV-LIVE'' AND type = ''L'';

IF @stari IS NULL
    SET @potize = @potize + N''- ZADNA zaloha logu v historii!'' + CHAR(13)+CHAR(10);
ELSE IF @stari > 60
    SET @potize = @potize + N''- Posledni zaloha logu je stara '' + CAST(@stari AS nvarchar(20))
                + N'' minut (limit 60).'' + CHAR(13)+CHAR(10);

/* 2) Duvod, proc se log neuvolnuje */
SELECT @reuse = log_reuse_wait_desc FROM sys.databases WHERE name = ''NAV-LIVE'';

IF @reuse NOT IN (''NOTHING'', ''ACTIVE_BACKUP_OR_RESTORE'', ''CHECKPOINT'')
    SET @potize = @potize + N''- log_reuse_wait_desc = '' + @reuse + CHAR(13)+CHAR(10);

/* 3) Zaplneni log souboru */
SELECT @pct = CAST(100.0 * FILEPROPERTY(name, ''SpaceUsed'') / size AS decimal(5,1))
FROM [NAV-LIVE].sys.database_files
WHERE type_desc = ''LOG'';

IF @pct > 70
    SET @potize = @potize + N''- Log je zaplneny na '' + CAST(@pct AS nvarchar(10)) + N'' % (limit 70).''
                + CHAR(13)+CHAR(10);

/* 4) Poslat, jen kdyz je co */
IF LEN(@potize) > 0
BEGIN
    SET @predmet = N''ALERT NAV-LIVE: zalohy transakcniho logu'';
    SET @potize = N''Server: '' + @@SERVERNAME + CHAR(13)+CHAR(10)
                + N''Cas: ''    + CONVERT(varchar(19), GETDATE(), 120) + CHAR(13)+CHAR(10)
                + CHAR(13)+CHAR(10) + @potize
                + CHAR(13)+CHAR(10)
                + N''Postup: viz 2026-08-10-NAV-LIVE-zalohovani-FINAL.html'';

    EXEC msdb.dbo.sp_send_dbmail
         @profile_name = N''<PROFIL>'',
         @recipients   = N''<MAIL>'',
         @subject      = @predmet,
         @body         = @potize;
END
';
GO

EXEC msdb.dbo.sp_add_jobschedule
     @job_name             = N'BC_Monitor_TLog_Health',
     @name                 = N'Kazdych 30 minut',
     @freq_type            = 4,
     @freq_interval        = 1,
     @freq_subday_type     = 4,
     @freq_subday_interval = 30,
     @active_start_time    = 000000,
     @active_end_time      = 235959;
GO

EXEC msdb.dbo.sp_add_jobserver @job_name = N'BC_Monitor_TLog_Health';
GO

-- Test hlidace nanecisto: docasne snizit limit v kroku na 0 a spustit rucne,
-- nebo proste pockat, jestli za 24 h neprijde falesny poplach.
EXEC msdb.dbo.sp_start_job @job_name = N'BC_Monitor_TLog_Health';
GO


/*==============================================================================
  CAST 10 — DENNI KONTROLA                      [jen cteni]
  Spoustet rano. Zitra rano je to zaroven DUKAZ, ze oprava zabrala.
==============================================================================*/

-- 10.1 Prehled
SELECT
    CONVERT(varchar(19), MAX(CASE WHEN type='D' THEN backup_finish_date END),120) AS posl_full,
    CONVERT(varchar(19), MAX(CASE WHEN type='I' THEN backup_finish_date END),120) AS posl_diff,
    CONVERT(varchar(19), MAX(CASE WHEN type='L' THEN backup_finish_date END),120) AS posl_log,
    DATEDIFF(MINUTE, MAX(CASE WHEN type='L' THEN backup_finish_date END), GETDATE()) AS log_stari_min
FROM msdb.dbo.backupset WHERE database_name='NAV-LIVE';

SELECT log_reuse_wait_desc, recovery_model_desc FROM sys.databases WHERE name='NAV-LIVE';

-- 10.2 DUKAZ: jsou zalohy i z nocnich hodin?
SELECT DATEPART(HOUR, backup_finish_date) AS hodina,
       COUNT(*) AS poc_zaloh,
       CAST(SUM(backup_size)/1024.0/1024/1024 AS decimal(10,2)) AS gb_celkem
FROM msdb.dbo.backupset
WHERE database_name='NAV-LIVE' AND type='L'
  AND backup_finish_date > DATEADD(DAY,-1,GETDATE())
GROUP BY DATEPART(HOUR, backup_finish_date)
ORDER BY hodina;

-- 10.3 Zaplneni logu
USE [NAV-LIVE];
SELECT name,
       CAST(size*8.0/1024/1024 AS decimal(10,1)) AS size_gb,
       CAST(FILEPROPERTY(name,'SpaceUsed')*8.0/1024/1024 AS decimal(10,1)) AS pouzito_gb,
       CAST(100.0*FILEPROPERTY(name,'SpaceUsed')/size AS decimal(5,1)) AS pouzito_pct
FROM sys.database_files WHERE type_desc='LOG';
GO
USE [master];
GO


/*==============================================================================
  CAST 11 — OPRAVA COPY_ONLY                    [SAMOSTATNE ROZHODNUTI]

  NALEZ: denni full ve 02:00 do G:\Backup\NAV-TEST-USERS ma is_copy_only = 0,
  takze kazdy den POSOUVA ZAKLAD pro diferencialni zalohy. Diff z ut-so je pak
  pouzitelny jen s full zalohou z predchoziho dne ze slozky pro obnovu testu.

  DVE MOZNOSTI - vybrat jednu, ne obe:
==============================================================================*/

/*------------------------------------------------------------------------------
  MOZNOST A — zachovat diffy, testovaci full udelat COPY_ONLY
  Diffy pak navazuji na nedelni tydenni full a rostou behem tydne.
  V prikazu jobu z casti 2.3 zmenit:

      BACKUP DATABASE [NAV-LIVE]
      TO DISK = N'G:\Backup\NAV-TEST-USERS\...'
      WITH COPY_ONLY, COMPRESSION, CHECKSUM;      <-- pridat COPY_ONLY
------------------------------------------------------------------------------*/

/*------------------------------------------------------------------------------
  MOZNOST B — zrusit diffy, denni full je oficialni kotva
  Nejkratsi retez obnovy: full + logy jednoho dne. G: ma 1 459 GB volnych.
  Podminka: denni full musi mit poradnou retenci a hlidani, ne jen slouzit testu.

      EXEC msdb.dbo.sp_update_job @job_name = N'BackupMaintenancePlan.Diff', @enabled = 0;
------------------------------------------------------------------------------*/

-- 11.1 Podklad pro rozhodnuti: jak velke ty zalohy vlastne jsou
SELECT CAST(backup_finish_date AS date) AS den, type, COUNT(*) AS poc,
       CAST(SUM(backup_size)/1024.0/1024/1024 AS decimal(10,1))            AS raw_gb,
       CAST(SUM(compressed_backup_size)/1024.0/1024/1024 AS decimal(10,1)) AS na_disku_gb
FROM msdb.dbo.backupset
WHERE database_name='NAV-LIVE' AND backup_finish_date > DATEADD(DAY,-14,GETDATE())
GROUP BY CAST(backup_finish_date AS date), type
ORDER BY den DESC, type;
GO
