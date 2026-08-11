/*==============================================================================
  NAV-LIVE — navrh nahrady kroku 1 jobu "1xdenne" (update_index)
  2026-08-11

  DUVOD
  -----
  Puvodni verze prestavuje (REBUILD) vsechny indexy nad 10 % fragmentace.
  Merenim zjisteno, ze tim vznikne ~140 GB transakcniho logu mezi 04:00 a 06:00,
  coz je 93 % denniho objemu. Log narazi na strop a vznika chyba 9002.

  ZMENY PROTI PUVODNI VERZI
  -------------------------
  1) Prahova logika misto jednoho prahu:
        < 5 %      nedelat nic
        5 - 30 %   REORGANIZE   (prubezna operace, log se mezi kroky uvolnuje)
        > 30 %     REBUILD      (jedna transakce, drahe - jen kdyz je treba)
  2) page_count >= 1000 (8 MB) misto > 100 (800 kB)
  3) UPDATE STATISTICS jen pro tabulky, ktere se NEprestavovaly
     (REBUILD statistiky aktualizuje sam, plnym skenem)
     a jen JEDNOU na tabulku, ne jednou na index
  4) Casovy limit - job nesmi bezet do nekonecna
  5) Chyby se pocitaji a job na konci SELHA, misto aby hlasil OK
  6) SORT_IN_TEMPDB + MAXDOP u prestaveb
  7) Preskakuji se zakazane indexy a systemove objekty

  POZOR
  -----
  - ONLINE = ON objem logu NESNIZI (naopak, udrzuje verzovaci strukturu).
    Pomaha dostupnosti. Zde zamerne nepouzito - v 04:00 nikdo nepracuje.
  - REORGANIZE nelze na indexu s ALLOW_PAGE_LOCKS = OFF -> tam se pouzije REBUILD.
  - Prvni beh muze byt jeste dlouhy (naskok fragmentace). Dalsi uz kratke.

  NASAZENI
  --------
  Nenahrazovat rovnou. Nejdriv spustit s @JenVypis = 1, podivat se, co by delal
  a kolik toho je. Teprve pak nahradit obsah kroku 1.
==============================================================================*/

SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

USE [NAV-LIVE];
GO

-------------------------------------------------------------------------------
-- PARAMETRY
-------------------------------------------------------------------------------
DECLARE @JenVypis      bit   = 1;      -- 1 = nic nedela, jen ukaze plan. Pro ostry beh dat 0.
DECLARE @ReorgOd       float = 5.0;    -- pod timto prahem se nedela nic
DECLARE @RebuildOd     float = 30.0;   -- od tohoto prahu REBUILD, jinak REORGANIZE
DECLARE @MinStran      bigint = 1000;  -- ignorovat indexy mensi nez ~8 MB
DECLARE @CasovyLimitMin int  = 90;     -- po vyprseni skoncit a nahlasit, kde skoncil
DECLARE @Maxdop        int   = 4;

-------------------------------------------------------------------------------
DECLARE @Start   datetime2(0) = SYSDATETIME();
DECLARE @Chyb    int = 0;
DECLARE @Hotovo  int = 0;
DECLARE @Preruseno bit = 0;

DECLARE @Log TABLE (
    Id      int IDENTITY(1,1),
    Cas     datetime2(0) DEFAULT SYSDATETIME(),
    Zprava  nvarchar(max)
);

INSERT INTO @Log (Zprava)
VALUES (N'Start udrzby indexu · databaze ' + DB_NAME()
      + N' · uzivatel ' + SYSTEM_USER
      + N' · rezim ' + CASE @JenVypis WHEN 1 THEN N'JEN VYPIS' ELSE N'OSTRY' END);

-------------------------------------------------------------------------------
-- 1) Sestaveni seznamu prace
-------------------------------------------------------------------------------
DECLARE @Prace TABLE (
    Id       int IDENTITY(1,1),
    Schema_  sysname,
    Tabulka  sysname,
    Index_   sysname,
    Frag     decimal(6,2),
    Stran    bigint,
    Typ      char(4),          -- REBU / REOR
    Prikaz   nvarchar(max)
);

INSERT INTO @Prace (Schema_, Tabulka, Index_, Frag, Stran, Typ, Prikaz)
SELECT
    s.name, o.name, i.name,
    CAST(ips.avg_fragmentation_in_percent AS decimal(6,2)),
    ips.page_count,
    CASE WHEN ips.avg_fragmentation_in_percent >= @RebuildOd
           OR i.allow_page_locks = 0
         THEN 'REBU' ELSE 'REOR' END,
    CASE WHEN ips.avg_fragmentation_in_percent >= @RebuildOd
           OR i.allow_page_locks = 0
         THEN N'ALTER INDEX ' + QUOTENAME(i.name)
            + N' ON ' + QUOTENAME(s.name) + N'.' + QUOTENAME(o.name)
            + N' REBUILD WITH (SORT_IN_TEMPDB = ON, MAXDOP = ' + CAST(@Maxdop AS nvarchar(2)) + N');'
         ELSE N'ALTER INDEX ' + QUOTENAME(i.name)
            + N' ON ' + QUOTENAME(s.name) + N'.' + QUOTENAME(o.name)
            + N' REORGANIZE;'
    END
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ips
JOIN sys.indexes i ON i.object_id = ips.object_id AND i.index_id = ips.index_id
JOIN sys.objects o ON o.object_id = i.object_id
JOIN sys.schemas s ON s.schema_id = o.schema_id
WHERE ips.avg_fragmentation_in_percent >= @ReorgOd
  AND ips.page_count >= @MinStran
  AND i.index_id > 0
  AND i.is_disabled = 0
  AND i.is_hypothetical = 0
  AND o.is_ms_shipped = 0
  AND o.type = 'U'
ORDER BY ips.avg_fragmentation_in_percent DESC;

DECLARE @PocetRebu int = (SELECT COUNT(*) FROM @Prace WHERE Typ = 'REBU');
DECLARE @PocetReor int = (SELECT COUNT(*) FROM @Prace WHERE Typ = 'REOR');
DECLARE @GbRebu decimal(10,1) = (SELECT ISNULL(SUM(Stran),0)*8.0/1024/1024 FROM @Prace WHERE Typ='REBU');
DECLARE @GbReor decimal(10,1) = (SELECT ISNULL(SUM(Stran),0)*8.0/1024/1024 FROM @Prace WHERE Typ='REOR');

INSERT INTO @Log (Zprava) VALUES (
    N'K prestavbe: ' + CAST(@PocetRebu AS nvarchar(10)) + N' indexu / ' + CAST(@GbRebu AS nvarchar(20)) + N' GB · ' +
    N'k reorganizaci: ' + CAST(@PocetReor AS nvarchar(10)) + N' indexu / ' + CAST(@GbReor AS nvarchar(20)) + N' GB');

-------------------------------------------------------------------------------
-- 2) Provedeni
-------------------------------------------------------------------------------
IF @JenVypis = 1
BEGIN
    SELECT Id, Typ, Frag AS [fragmentace_%],
           CAST(Stran*8.0/1024 AS decimal(10,1)) AS mb,
           Schema_ + N'.' + Tabulka AS tabulka, Index_ AS index_, Prikaz
    FROM @Prace ORDER BY Id;

    SELECT Zprava FROM @Log ORDER BY Id;
    RETURN;
END

DECLARE @i int = 1, @max int, @cmd nvarchar(max);
SELECT @max = ISNULL(MAX(Id),0) FROM @Prace;

WHILE @i <= @max
BEGIN
    IF DATEDIFF(MINUTE, @Start, SYSDATETIME()) >= @CasovyLimitMin
    BEGIN
        SET @Preruseno = 1;
        INSERT INTO @Log (Zprava) VALUES (
            N'Casovy limit ' + CAST(@CasovyLimitMin AS nvarchar(5)) + N' min vyprsel. '
          + N'Zpracovano ' + CAST(@Hotovo AS nvarchar(10)) + N' z ' + CAST(@max AS nvarchar(10))
          + N'. Zbytek pocka na dalsi beh.');
        BREAK;
    END

    SELECT @cmd = Prikaz FROM @Prace WHERE Id = @i;

    BEGIN TRY
        EXEC sp_executesql @cmd;
        SET @Hotovo += 1;
    END TRY
    BEGIN CATCH
        SET @Chyb += 1;
        INSERT INTO @Log (Zprava)
        VALUES (N'CHYBA · ' + @cmd + N' · ' + ERROR_MESSAGE());
    END CATCH

    SET @i += 1;
END

-------------------------------------------------------------------------------
-- 3) UPDATE STATISTICS jen tam, kde se NEprestavovalo
--    (REBUILD statistiky aktualizuje sam) a jen jednou na tabulku
-------------------------------------------------------------------------------
DECLARE @statsCmd nvarchar(max);

DECLARE stat_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT DISTINCT N'UPDATE STATISTICS ' + QUOTENAME(Schema_) + N'.' + QUOTENAME(Tabulka) + N';'
    FROM @Prace p
    WHERE p.Typ = 'REOR'
      AND NOT EXISTS (SELECT 1 FROM @Prace r
                      WHERE r.Typ = 'REBU' AND r.Schema_ = p.Schema_ AND r.Tabulka = p.Tabulka);

OPEN stat_cur;
FETCH NEXT FROM stat_cur INTO @statsCmd;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF DATEDIFF(MINUTE, @Start, SYSDATETIME()) < @CasovyLimitMin
    BEGIN
        BEGIN TRY
            EXEC sp_executesql @statsCmd;
        END TRY
        BEGIN CATCH
            SET @Chyb += 1;
            INSERT INTO @Log (Zprava) VALUES (N'CHYBA · ' + @statsCmd + N' · ' + ERROR_MESSAGE());
        END CATCH
    END
    FETCH NEXT FROM stat_cur INTO @statsCmd;
END
CLOSE stat_cur;
DEALLOCATE stat_cur;

-------------------------------------------------------------------------------
-- 4) Zaver — job musi SELHAT, kdyz neco selhalo
-------------------------------------------------------------------------------
INSERT INTO @Log (Zprava) VALUES (
    N'Konec · zpracovano ' + CAST(@Hotovo AS nvarchar(10)) + N' z ' + CAST(@max AS nvarchar(10))
  + N' · chyb ' + CAST(@Chyb AS nvarchar(10))
  + N' · trvani ' + CAST(DATEDIFF(MINUTE, @Start, SYSDATETIME()) AS nvarchar(10)) + N' min');

SELECT Cas, Zprava FROM @Log ORDER BY Id;

IF @Chyb > 0
BEGIN
    DECLARE @m nvarchar(500) = N'Udrzba indexu skoncila s ' + CAST(@Chyb AS nvarchar(10))
                             + N' chybami. Detail viz vystup kroku.';
    RAISERROR(@m, 16, 1);
END
ELSE IF @Preruseno = 1
BEGIN
    RAISERROR(N'Udrzba indexu prerusena casovym limitem - nedokoncena.', 16, 1);
END
GO
