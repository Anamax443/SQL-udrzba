/* =====================================================================
   NAV-LIVE — dávkový úklid `AXIMA$Change Log Entry`
   Náhrada kroku 10 jobu `Axi_Navilog_a_jine_Jardoviny`
   Server: B-S-W-SQL-01 · DB: NAV-LIVE (**FULL recovery**)

   PROČ:
   Původní krok je jeden nedávkovaný DELETE přes celý rozsah:

       DELETE FROM [NAV-LIVE].[dbo].[AXIMA$Change Log Entry]
       WHERE [Date and Time] <= CAST(DATEADD(m, -3, GetDate()) AS date)

   Dokud běžel denně, mazal malý přírůstek a prošel. Od 2026-06-27 ale
   nedoběhl (job končí dřív, na kroku 7), takže je dnes k smazání
   ~125 mil. řádků. V téhle podobě by to byla jedna transakce přes 125 mil.
   řádků a 7 indexových struktur = jistá chyba 9002, tentokrát v NAV-LIVE.

   ROZDÍLY PROTI PŮVODNÍ VERZI:
   1. Maže se podle `[Entry No_]`, ne podle `[Date and Time]`.
      Na datu NENÍ použitelný index (v `$2` je až druhý za `Table No_`),
      takže filtr podle data = scan. `Entry No_` je clusterovaný klíč a
      roste s časem → hranice se najde jednou binárním hledáním (~29 seeků)
      a pak se maže souvislý rozsah clusteru, tedy sekvenčně.
   2. Dávky s commitem místo jedné transakce.
   3. Tvrdý časový strop — co se nestihne, dobere příští běh.
   4. Pojistka na log: když zaplnění přeroste práh, počká se na zálohu logu
      (běží á 15 min). Bez ní by první úklid mohl log utrhnout i po dávkách.

   PRVNÍ NASAZENÍ:
   Nejdřív ručně s @LimitMin = 15 a sledovat výstup — změří se propustnost.
   Celkem je k smazání ~125 mil. řádků; podle rychlosti to bude 2–4 noci.
   Teprve až se tabulka dostane na svoje okno, nahradit tímhle krok 10 —
   od té chvíle bude denně mazat jen přírůstek (~2,45 mil. řádků).

   PO DOKONČENÍ:
   Smazání 125 mil. řádků nechá indexy roztříštěné → zvážit REBUILD
   (mimo provoz, generuje log). Uvolněné místo zůstane uvnitř
   NAV_LIVE_Data — což je přesně cíl: soubor přestane růst ke svému stropu.
   ===================================================================== */

SET NOCOUNT ON;
SET DEADLOCK_PRIORITY LOW;

DECLARE @Mesicu    int          = 3,              -- retence, shodná s původním krokem
        @Davka     int          = 25000,
        @LimitMin  int          = 120,
        @LogPrahPct decimal(5,2) = 60.0,          -- nad tímhle se čeká na zálohu logu
        @Pauza     varchar(12)  = '00:00:00.200',
        @Start     datetime2(0) = SYSDATETIME(),
        @Smazano   bigint       = 0,
        @Kolo      int          = 0,
        @R         int          = 1,
        @LogPct    decimal(5,2),
        @Zprava    nvarchar(300);

/* --- hranice: binární hledání Entry No_ odpovídajícího datu ---------- */
DECLARE @Cil date = CAST(DATEADD(month, -@Mesicu, GETDATE()) AS date),
        @lo bigint, @hi bigint, @mid bigint, @d datetime, @Hranice bigint;

SELECT TOP (1) @lo = [Entry No_] FROM [NAV-LIVE].[dbo].[AXIMA$Change Log Entry] ORDER BY [Entry No_] ASC;
SELECT TOP (1) @hi = [Entry No_] FROM [NAV-LIVE].[dbo].[AXIMA$Change Log Entry] ORDER BY [Entry No_] DESC;

IF @lo IS NULL
BEGIN
    RAISERROR('Tabulka je prazdna, neni co mazat.', 0, 1) WITH NOWAIT;
    RETURN;
END

WHILE @lo < @hi
BEGIN
    SET @mid = (@lo + @hi) / 2;
    SELECT TOP (1) @d = [Date and Time]
    FROM [NAV-LIVE].[dbo].[AXIMA$Change Log Entry]
    WHERE [Entry No_] >= @mid ORDER BY [Entry No_];

    IF @d < @Cil SET @lo = @mid + 1; ELSE SET @hi = @mid;
END
SET @Hranice = @lo;

SET @Zprava = CONCAT(N'Hranice: mažu Entry No_ < ', @Hranice,
                     N' (datum ', CONVERT(varchar(10), @Cil, 120),
                     N'). Dávka ', @Davka, N', limit ', @LimitMin, N' min.');
RAISERROR(@Zprava, 0, 1) WITH NOWAIT;

/* --- vlastní mazání --------------------------------------------------- */
WHILE @R > 0
BEGIN
    DELETE TOP (@Davka)
    FROM [NAV-LIVE].[dbo].[AXIMA$Change Log Entry]
    WHERE [Entry No_] < @Hranice;

    SET @R       = @@ROWCOUNT;
    SET @Smazano = @Smazano + @R;
    SET @Kolo    = @Kolo + 1;

    /* pojistka na transakční log — čekáme, až ho záloha uvolní */
    IF @Kolo % 10 = 0
    BEGIN
        SELECT @LogPct = used_log_space_in_percent FROM sys.dm_db_log_space_usage;

        WHILE @LogPct > @LogPrahPct
        BEGIN
            SET @Zprava = CONCAT(N'Log na ', @LogPct, N' % — čekám na zálohu logu…');
            RAISERROR(@Zprava, 0, 1) WITH NOWAIT;
            WAITFOR DELAY '00:01:00';
            SELECT @LogPct = used_log_space_in_percent FROM sys.dm_db_log_space_usage;
        END
    END

    IF @Kolo % 40 = 0
    BEGIN
        SET @Zprava = CONCAT(CONVERT(varchar(19), SYSDATETIME(), 120),
                             N'  smazáno ', @Smazano, N' řádků (', @Kolo, N' dávek), log ',
                             ISNULL(@LogPct, 0), N' %');
        RAISERROR(@Zprava, 0, 1) WITH NOWAIT;
    END

    IF @R > 0 AND DATEDIFF(minute, @Start, SYSDATETIME()) >= @LimitMin
    BEGIN
        SET @Zprava = CONCAT(N'Zastaveno na časovém limitu ', @LimitMin,
                             N' min. Smazáno ', @Smazano, N' řádků, zbytek dobere příští běh.');
        RAISERROR(@Zprava, 0, 1) WITH NOWAIT;
        BREAK;
    END

    IF @R > 0
        WAITFOR DELAY @Pauza;
END

SET @Zprava = CONCAT(N'Hotovo. Smazáno ', @Smazano, N' řádků ve ', @Kolo,
                     N' dávkách za ', DATEDIFF(second, @Start, SYSDATETIME()), N' s.');
RAISERROR(@Zprava, 0, 1) WITH NOWAIT;
GO
