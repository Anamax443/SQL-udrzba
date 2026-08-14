/* =====================================================================
   Emergency_Cache_Warming — diagnostika (JEN ČTENÍ, nic nemění)
   Server:  B-S-W-SQL-01, default instance
   Důvod:   185 chyb 208 v Application logu za 2026-08-11 18:42 .. 2026-08-14 08:55
            (~3/hod), job spouštěný schedulem Every_5_Min_PLE_Check,
            padá vždy v kroku 1 (Check_PLE_And_Warm2).
            Doba běhu je dvojvrcholová: ~5,9–6,0 min (78×) a PŘESNĚ 10,0 min (93×).
            10,0 min = 600 s = default 'remote query timeout (s)' → část 4.
            Při 5min schedule a 6–10min běhu se job překrývá sám se sebou.
   Spustit: SSMS jako admintrnka, výsledky poslat zpět (jsou malé).
   ===================================================================== */

USE msdb;
GO

/* --- 1) Definice jobu a kroků ------------------------------------- */
SELECT  j.name                AS job,
        j.enabled             AS job_zapnut,
        j.notify_level_email,
        js.step_id,
        js.step_name,
        js.subsystem,
        js.database_name,
        js.retry_attempts,
        js.retry_interval,
        js.on_fail_action,
        js.output_file_name,
        LEN(js.command)       AS delka_prikazu
FROM    dbo.sysjobs      AS j
JOIN    dbo.sysjobsteps  AS js ON js.job_id = j.job_id
WHERE   j.name = N'Emergency_Cache_Warming'
ORDER BY js.step_id;
GO

/* --- 2) Schedule ---------------------------------------------------- */
SELECT  s.name                AS schedule_nazev,
        s.enabled             AS schedule_zapnut,
        s.freq_type, s.freq_interval, s.freq_subday_type, s.freq_subday_interval,
        s.active_start_time, s.active_end_time,
        s.date_created, s.date_modified
FROM    dbo.sysschedules       AS s
JOIN    dbo.sysjobschedules    AS jsch ON jsch.schedule_id = s.schedule_id
JOIN    dbo.sysjobs            AS j    ON j.job_id = jsch.job_id
WHERE   j.name = N'Emergency_Cache_Warming';
GO

/* --- 3) SKUTEČNÁ chyba kroku (eventlog má jen souhrn) --------------- */
/*     Seskupeno, ať je výstup krátký: unikátní texty chyb + počet.     */
SELECT  TOP (10)
        pocet          = COUNT(*),
        posledni_datum = MAX(h.run_date),
        prum_trvani    = MAX(h.run_duration),          -- HHMMSS
        chyba          = LEFT(h.message, 400)
FROM    dbo.sysjobhistory AS h
JOIN    dbo.sysjobs       AS j ON j.job_id = h.job_id
WHERE   j.name    = N'Emergency_Cache_Warming'
  AND   h.step_id = 1
  AND   h.run_status <> 1                              -- 1 = Succeeded
GROUP BY LEFT(h.message, 400)
ORDER BY pocet DESC;
GO

/* --- 4) Timeouty a paměť (proč job vůbec existuje) ------------------ */
SELECT  name, value_in_use
FROM    sys.configurations
WHERE   name IN (N'remote query timeout (s)', N'max server memory (MB)',
                 N'min server memory (MB)', N'max degree of parallelism');

SELECT  ram_serveru_MB   = physical_memory_kb / 1024,
        sql_target_MB    = committed_target_kb / 1024,
        sql_pouziva_MB   = committed_kb / 1024
FROM    sys.dm_os_sys_info;

SELECT  PLE_sekund = cntr_value
FROM    sys.dm_os_performance_counters
WHERE   counter_name = N'Page life expectancy'
  AND   object_name LIKE N'%Buffer Manager%';
GO

/* --- 5) Text kroku 1 (pošli zvlášť, může být dlouhý) ---------------- */
SELECT  js.command
FROM    dbo.sysjobs      AS j
JOIN    dbo.sysjobsteps  AS js ON js.job_id = j.job_id
WHERE   j.name = N'Emergency_Cache_Warming' AND js.step_id = 1;
GO
