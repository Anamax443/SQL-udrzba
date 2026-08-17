/* =====================================================================
   Axi — chyba 9002 „ACTIVE_TRANSACTION" (JEN ČTENÍ, nic nemění)
   Server:  B-S-W-SQL-01, default instance
   Nález:   2026-08-16 06:23:03 (místní čas)
            „The transaction log for database 'Axi' is full due to 'ACTIVE_TRANSACTION'."
            2026-08-16 06:38:00 job `Axi_Navilog_a_jine_Jardoviny` (schedule 30 „Axi")
            spuštěný 2026-08-15 20:01:00 selhal v kroku 7 `1M_clear`
            → běžel 10 h 37 min a teprve pak spadl.
   Pozn.:   ACTIVE_TRANSACTION ≠ případ NAV-LIVE. Tady log NELZE uvolnit
            ani zálohou logu, dokud transakce žije. Zálohy nepomůžou,
            pomůže jen dávkování mazání (a commit po každé dávce).
   Spustit: SSMS jako admintrnka, výstup je krátký.
   ===================================================================== */

/* --- 1) Stav databáze a jejího logu --------------------------------- */
SELECT  d.name,
        d.recovery_model_desc,
        d.log_reuse_wait_desc,          -- co PRÁVĚ teď brání uvolnění logu
        d.state_desc,
        d.is_auto_shrink_on
FROM    sys.databases AS d
WHERE   d.name = N'Axi';

SELECT  soubor      = f.name,
        typ         = f.type_desc,
        velikost_MB = f.size / 128,
        max_MB      = CASE f.max_size WHEN -1 THEN -1 ELSE f.max_size / 128 END,
        rust        = CASE f.is_percent_growth WHEN 1 THEN CAST(f.growth AS varchar(10)) + ' %'
                                               ELSE CAST(f.growth / 128 AS varchar(10)) + ' MB' END,
        f.physical_name
FROM    Axi.sys.database_files AS f;
GO

USE Axi;
SELECT  log_celkem_MB  = total_log_size_in_bytes  / 1048576.0,
        log_pouzito_MB = used_log_space_in_bytes  / 1048576.0,
        log_pouzito_pct= used_log_space_in_percent
FROM    sys.dm_db_log_space_usage;
GO

/* --- 2) Zálohuje se log Axi vůbec? ---------------------------------- */
USE msdb;
SELECT  TOP (5)
        typ = b.type,                    -- D = full, I = diff, L = log
        b.backup_start_date, b.backup_finish_date,
        velikost_MB = b.backup_size / 1048576.0
FROM    dbo.backupset AS b
WHERE   b.database_name = N'Axi'
ORDER BY b.backup_set_id DESC;
GO

/* --- 3) Co dělá krok 7 `1M_clear` ----------------------------------- */
SELECT  js.step_id, js.step_name, js.subsystem, js.database_name,
        delka_prikazu = LEN(js.command)
FROM    msdb.dbo.sysjobs     AS j
JOIN    msdb.dbo.sysjobsteps AS js ON js.job_id = j.job_id
WHERE   j.name = N'Axi_Navilog_a_jine_Jardoviny'
ORDER BY js.step_id;

/* text kroku 7 zvlášť — pošli jako text */
SELECT  js.command
FROM    msdb.dbo.sysjobs     AS j
JOIN    msdb.dbo.sysjobsteps AS js ON js.job_id = j.job_id
WHERE   j.name = N'Axi_Navilog_a_jine_Jardoviny' AND js.step_id = 7;
GO

/* --- 4) Jak dlouho kroky běhaly (run_duration = HHMMSS) ------------- */
SELECT  TOP (15)
        h.step_id, h.step_name,
        h.run_date, h.run_time, h.run_duration,
        stav = CASE h.run_status WHEN 0 THEN 'Failed' WHEN 1 THEN 'Succeeded'
                                 WHEN 2 THEN 'Retry'  WHEN 3 THEN 'Canceled' ELSE 'In progress' END,
        zprava = LEFT(h.message, 300)
FROM    msdb.dbo.sysjobhistory AS h
JOIN    msdb.dbo.sysjobs       AS j ON j.job_id = h.job_id
WHERE   j.name = N'Axi_Navilog_a_jine_Jardoviny'
ORDER BY h.instance_id DESC;
GO

/* --- 5) Neběží to zrovna teď? (dlouhá otevřená transakce) ----------- */
SELECT  session_id      = s.session_id,
        db              = DB_NAME(t.database_id),
        zacatek         = t.database_transaction_begin_time,
        log_zaznamu     = t.database_transaction_log_record_count,
        log_MB          = t.database_transaction_log_bytes_used / 1048576.0,
        prikaz          = SUBSTRING(st.text, 1, 200)
FROM    sys.dm_tran_database_transactions AS t
JOIN    sys.dm_tran_session_transactions  AS s  ON s.transaction_id = t.transaction_id
OUTER APPLY (SELECT TOP (1) r.sql_handle FROM sys.dm_exec_requests r WHERE r.session_id = s.session_id) AS req
OUTER APPLY sys.dm_exec_sql_text(req.sql_handle) AS st
WHERE   DB_NAME(t.database_id) = N'Axi'
ORDER BY t.database_transaction_begin_time;
GO
