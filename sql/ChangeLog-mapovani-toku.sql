/* =====================================================================
   Change Log Entry — mapování toku (JEN ČTENÍ, nic nemění)
   Server: B-S-W-SQL-01
   Cíl:    zjistit, KDO do Change Logu píše, CO se z něj kam kopíruje
           a JAK se čistí — ať to není známé jen z jednoho jobu.
   Pozor:  žádný dotaz tu nedělá scan celé 350mil. tabulky. Část 6 čte
           jen posledních 1 000 000 záznamů přes clusterovaný klíč.
   ===================================================================== */

/* --- 1) Celý job `Axi_Navilog_a_jine_Jardoviny` -- to je jádro toku --- */
SELECT  js.step_id, js.step_name, js.subsystem, js.database_name,
        js.on_success_action, js.on_fail_action,
        js.command
FROM    msdb.dbo.sysjobsteps AS js
WHERE   js.job_id = CONVERT(uniqueidentifier, 0xD4752DB20260CB4EA69A8FC1C2D7A709)
ORDER BY js.step_id;
GO

/* --- 2) Sahá na to ještě něco jiného na téhle instanci? -------------- */
SELECT  job = j.name, js.step_id, js.step_name, js.database_name,
        ukazka = LEFT(js.command, 200)
FROM    msdb.dbo.sysjobsteps AS js
JOIN    msdb.dbo.sysjobs     AS j ON j.job_id = js.job_id
WHERE   js.command LIKE N'%Change Log%'
   OR   js.command LIKE N'%NaviLog%'
ORDER BY j.name, js.step_id;
GO

/* --- 3) Procedury / pohledy / funkce, které to jméno obsahují -------- */
USE [NAV-LIVE];
SELECT  db = DB_NAME(), o.name, o.type_desc, o.modify_date
FROM    sys.sql_modules AS m
JOIN    sys.objects     AS o ON o.object_id = m.object_id
WHERE   m.definition LIKE N'%Change Log Entry%';
GO

USE [Axi];
SELECT  db = DB_NAME(), o.name, o.type_desc, o.modify_date
FROM    sys.sql_modules AS m
JOIN    sys.objects     AS o ON o.object_id = m.object_id
WHERE   m.definition LIKE N'%Change Log Entry%'
   OR   m.definition LIKE N'%NaviLog%';
GO

/* --- 4) Triggery přímo na tabulce (neměly by být, ale ověřit) -------- */
SELECT  t.name AS trigger_nazev, t.is_disabled, t.create_date, t.modify_date
FROM    [NAV-LIVE].sys.triggers AS t
WHERE   t.parent_id = OBJECT_ID(N'[NAV-LIVE].[dbo].[AXIMA$Change Log Entry]');
GO

/* --- 5) Kam se to kopíruje: tabulky NaviLog v Axi -------------------- */
SELECT  tabulka = t.name,
        radku   = SUM(p.rows),
        MB      = CAST(SUM(a.total_pages) * 8 / 1024.0 AS decimal(12,1))
FROM    [Axi].sys.tables            AS t
JOIN    [Axi].sys.indexes           AS i ON i.object_id = t.object_id AND i.index_id IN (0,1)
JOIN    [Axi].sys.partitions        AS p ON p.object_id = t.object_id AND p.index_id = i.index_id
JOIN    [Axi].sys.allocation_units  AS a ON a.container_id = p.partition_id
WHERE   t.name LIKE N'NaviLog%'
GROUP BY t.name
ORDER BY radku DESC;
GO

/* --- 6) CO se dnes loguje nejvíc ------------------------------------- */
/*     Profil posledního milionu záznamů = rozsah clusteru, ne scan.     */
DECLARE @Max bigint = (SELECT TOP (1) [Entry No_]
                       FROM [NAV-LIVE].[dbo].[AXIMA$Change Log Entry]
                       ORDER BY [Entry No_] DESC);

SELECT  TOP (25)
        [Table No_],
        radku = COUNT(*),
        podil_pct = CAST(100.0 * COUNT(*) / 1000000 AS decimal(5,2))
FROM    [NAV-LIVE].[dbo].[AXIMA$Change Log Entry]
WHERE   [Entry No_] > @Max - 1000000
GROUP BY [Table No_]
ORDER BY radku DESC;
GO

/* --- 7) Nastavení Change Logu na straně BC --------------------------- */
/*     Co je vůbec zapnuté k logování — tady je skutečná páka.           */
SELECT * FROM [NAV-LIVE].[dbo].[AXIMA$Change Log Setup];

SELECT  [Table No_], [Log Insertion], [Log Modification], [Log Deletion]
FROM    [NAV-LIVE].[dbo].[AXIMA$Change Log Setup (Table)]
ORDER BY [Table No_];

SELECT  pocet_hlidanych_poli = COUNT(*)
FROM    [NAV-LIVE].[dbo].[AXIMA$Change Log Setup (Field)];
GO

/* --- 8) Překlad čísel tabulek na jména (nemusí být na všech verzích) - */
SELECT  o.ID, o.Name
FROM    [NAV-LIVE].[dbo].[Object] AS o
WHERE   o.Type = 0                 -- TableData
  AND   o.ID IN ( /* sem doplnit Table No_ z části 6 */ 0 );
GO
