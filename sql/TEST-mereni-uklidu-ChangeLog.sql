/* =====================================================================
   MĚŘENÍ na NAV-TEST-USERS — jak rychle jde uklidit Change Log Entry
   Server: B-S-W-SQL-01 · DB: **NAV-TEST-USERS** (kopie produkce)

   POZOR — tohle DATA MĚNÍ. Na testovací kopii schválně: smaže část řádků,
   vypne indexy a zase je postaví. Databáze se pak musí obnovit ze zálohy,
   než se použije k něčemu jinému. Na produkci NIC z tohohle nespouštět.

   POZOR 2 — je to STEJNÁ instance jako produkce. Čtení 250GB tabulky
   vytlačí z paměti stránky NAV-LIVE (PLE už tak není dobré) a sebere IO.
   **Pouštět mimo pracovní dobu**, ideálně večer.

   CO SE MĚŘÍ:
     A) dávkové mazání se všemi indexy      → dnešní stav
     B) dávkové mazání s vypnutými indexy   → kolik získáme
     C) doba přestavby jednoho indexu       → čím se to zaplatí

   Podle výsledku se rozhodne, jak bude vypadat produkční běh.
   ===================================================================== */

USE [NAV-TEST-USERS];
GO
SET NOCOUNT ON;
GO

/* =====================================================================
   ČÁST 0 — kontrola prostředí (jen čte)
   ===================================================================== */

SELECT  db = DB_NAME(),
        d.recovery_model_desc,
        d.log_reuse_wait_desc,
        d.state_desc
FROM    sys.databases AS d
WHERE   d.name = DB_NAME();

/* jak čerstvá kopie to je */
SELECT  TOP (3) rh.restore_date, rh.destination_database_name
FROM    msdb.dbo.restorehistory AS rh
WHERE   rh.destination_database_name = N'NAV-TEST-USERS'
ORDER BY rh.restore_date DESC;

/* místo v souborech — bude se sledovat i po vypnutí indexů */
SELECT  name,
        velikost_MB = size / 128,
        pouzito_MB  = CAST(FILEPROPERTY(name, 'SpaceUsed') AS int) / 128,
        volne_MB    = (size - CAST(FILEPROPERTY(name, 'SpaceUsed') AS int)) / 128
FROM    sys.database_files;

/* velikost jednotlivých struktur */
SELECT  index_nazev = i.name, i.index_id, i.type_desc, i.is_disabled,
        MB = CAST(SUM(ps.reserved_page_count) * 8 / 1024.0 AS decimal(12,1))
FROM    sys.dm_db_partition_stats AS ps
JOIN    sys.indexes               AS i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE   ps.object_id = OBJECT_ID(N'dbo.AXIMA$Change Log Entry')
GROUP BY i.name, i.index_id, i.type_desc, i.is_disabled
ORDER BY MB DESC;
GO

/* =====================================================================
   ČÁST 1 — MĚŘENÍ A: dávkové mazání se všemi indexy
   ===================================================================== */

DECLARE @Cil date = CAST(DATEADD(month, -3, GETDATE()) AS date),
        @lo bigint, @hi bigint, @mid bigint, @d datetime, @Hranice bigint;

SELECT TOP (1) @lo = [Entry No_] FROM dbo.[AXIMA$Change Log Entry] ORDER BY [Entry No_] ASC;
SELECT TOP (1) @hi = [Entry No_] FROM dbo.[AXIMA$Change Log Entry] ORDER BY [Entry No_] DESC;

WHILE @lo < @hi
BEGIN
    SET @mid = (@lo + @hi) / 2;
    SELECT TOP (1) @d = [Date and Time] FROM dbo.[AXIMA$Change Log Entry]
    WHERE [Entry No_] >= @mid ORDER BY [Entry No_];
    IF @d < @Cil SET @lo = @mid + 1; ELSE SET @hi = @mid;
END
SET @Hranice = @lo;
RAISERROR('--- MĚŘENÍ A: se všemi indexy ---', 0, 1) WITH NOWAIT;
RAISERROR(N'Hranice Entry No_ nalezena.', 0, 1) WITH NOWAIT;
PRINT CONCAT('Hranice = ', @Hranice, '   (datum ', CONVERT(varchar(10), @Cil, 120), ')');

DECLARE @Davka int = 25000, @Kolo int = 0, @R int = 1, @Smazano bigint = 0,
        @t0 datetime2(3) = SYSDATETIME(), @s decimal(18,3), @rateA decimal(18,2);

WHILE @Kolo < 10 AND @R > 0
BEGIN
    DELETE TOP (@Davka) FROM dbo.[AXIMA$Change Log Entry] WHERE [Entry No_] < @Hranice;
    SET @R = @@ROWCOUNT; SET @Smazano += @R; SET @Kolo += 1;
END

SET @s     = DATEDIFF(millisecond, @t0, SYSDATETIME()) / 1000.0;
SET @rateA = @Smazano / NULLIF(@s, 0);
PRINT CONCAT('A: smazano ', @Smazano, ' radku za ', @s, ' s = ', CAST(@rateA AS int), ' radku/s');
PRINT CONCAT('A: odhad na 125 mil. = ', CAST(125000000 / NULLIF(@rateA,0) / 3600 AS decimal(6,1)), ' hodin');
GO

/* =====================================================================
   ČÁST 2 — vypnout nonclustered indexy
   NIKDY nevypínat clusterovaný `AXIMA$Change Log Entry$0` — tím se
   tabulka stane nedostupnou.
   ===================================================================== */

ALTER INDEX [$1] ON dbo.[AXIMA$Change Log Entry] DISABLE;
ALTER INDEX [$2] ON dbo.[AXIMA$Change Log Entry] DISABLE;
ALTER INDEX [$3] ON dbo.[AXIMA$Change Log Entry] DISABLE;
ALTER INDEX [$4] ON dbo.[AXIMA$Change Log Entry] DISABLE;
ALTER INDEX [$5] ON dbo.[AXIMA$Change Log Entry] DISABLE;
ALTER INDEX [IX_ChangeLog_PKField2Value] ON dbo.[AXIMA$Change Log Entry] DISABLE;
GO

/* kolik místa se tím uvolnilo */
SELECT  name,
        pouzito_MB = CAST(FILEPROPERTY(name, 'SpaceUsed') AS int) / 128,
        volne_MB   = (size - CAST(FILEPROPERTY(name, 'SpaceUsed') AS int)) / 128
FROM    sys.database_files;
GO

/* =====================================================================
   ČÁST 3 — MĚŘENÍ B: dávkové mazání bez nonclustered indexů
   ===================================================================== */

DECLARE @Cil date = CAST(DATEADD(month, -3, GETDATE()) AS date),
        @lo bigint, @hi bigint, @mid bigint, @d datetime, @Hranice bigint;

SELECT TOP (1) @lo = [Entry No_] FROM dbo.[AXIMA$Change Log Entry] ORDER BY [Entry No_] ASC;
SELECT TOP (1) @hi = [Entry No_] FROM dbo.[AXIMA$Change Log Entry] ORDER BY [Entry No_] DESC;

WHILE @lo < @hi
BEGIN
    SET @mid = (@lo + @hi) / 2;
    SELECT TOP (1) @d = [Date and Time] FROM dbo.[AXIMA$Change Log Entry]
    WHERE [Entry No_] >= @mid ORDER BY [Entry No_];
    IF @d < @Cil SET @lo = @mid + 1; ELSE SET @hi = @mid;
END
SET @Hranice = @lo;
RAISERROR('--- MĚŘENÍ B: bez nonclustered indexu ---', 0, 1) WITH NOWAIT;

DECLARE @Davka int = 25000, @Kolo int = 0, @R int = 1, @Smazano bigint = 0,
        @t0 datetime2(3) = SYSDATETIME(), @s decimal(18,3), @rateB decimal(18,2);

WHILE @Kolo < 10 AND @R > 0
BEGIN
    DELETE TOP (@Davka) FROM dbo.[AXIMA$Change Log Entry] WHERE [Entry No_] < @Hranice;
    SET @R = @@ROWCOUNT; SET @Smazano += @R; SET @Kolo += 1;
END

SET @s     = DATEDIFF(millisecond, @t0, SYSDATETIME()) / 1000.0;
SET @rateB = @Smazano / NULLIF(@s, 0);
PRINT CONCAT('B: smazano ', @Smazano, ' radku za ', @s, ' s = ', CAST(@rateB AS int), ' radku/s');
PRINT CONCAT('B: odhad na 125 mil. = ', CAST(125000000 / NULLIF(@rateB,0) / 3600 AS decimal(6,1)), ' hodin');
GO

/* =====================================================================
   ČÁST 4 — kolik stojí přestavba
   Měří se NEJMENŠÍ index (IX_ChangeLog_PKField2Value, na produkci 7,4 GB)
   a z něj se extrapoluje na zbývajících ~123 GB. Nemá smysl čekat hodiny
   na všech šest, když poměr velikostí známe.
   ===================================================================== */

DECLARE @t0 datetime2(3) = SYSDATETIME(), @s decimal(18,3);

ALTER INDEX [IX_ChangeLog_PKField2Value] ON dbo.[AXIMA$Change Log Entry]
      REBUILD WITH (SORT_IN_TEMPDB = ON, MAXDOP = 4);

SET @s = DATEDIFF(millisecond, @t0, SYSDATETIME()) / 1000.0;
PRINT CONCAT('C: rebuild IX_ChangeLog_PKField2Value trval ', @s, ' s');
PRINT '   Extrapolace na vsech 6 indexu: nasobit pomerem velikosti (produkce: 123 GB / 7,4 GB = 16,6x).';
GO

/* velikost po přestavbě jednoho indexu */
SELECT  index_nazev = i.name, i.is_disabled,
        MB = CAST(SUM(ps.reserved_page_count) * 8 / 1024.0 AS decimal(12,1))
FROM    sys.dm_db_partition_stats AS ps
JOIN    sys.indexes               AS i ON i.object_id = ps.object_id AND i.index_id = ps.index_id
WHERE   ps.object_id = OBJECT_ID(N'dbo.AXIMA$Change Log Entry')
GROUP BY i.name, i.is_disabled
ORDER BY MB DESC;
GO

/* =====================================================================
   ÚKLID PO MĚŘENÍ
   Zbylé indexy nechat VYPNUTÉ nemá smysl — buď je postavit zpátky:

       ALTER INDEX [$1] ON dbo.[AXIMA$Change Log Entry] REBUILD WITH (SORT_IN_TEMPDB = ON, MAXDOP = 4);
       ... a tak dál pro $2 až $5

   nebo (rychlejší) databázi prostě obnovit ze zálohy.
   ===================================================================== */
