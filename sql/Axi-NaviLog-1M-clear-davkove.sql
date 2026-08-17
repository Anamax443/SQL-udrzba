/* =====================================================================
   Axi — náhrada kroku 7 `1M_clear` jobu `Axi_Navilog_a_jine_Jardoviny`
   Server: B-S-W-SQL-01 · DB: Axi (SIMPLE recovery, log 50 GB pevný strop)

   PROČ:
   Původní krok je jeden nedávkovaný DELETE:

       DELETE FROM [Axi].[dbo].[NaviLog_1M]
       WHERE [Date and Time] < CAST(DATEADD(m, -1, GetDate()) AS date)

   = jedna transakce přes celý rozsah. 2026-08-15 20:01 → 2026-08-16 06:23
   přerostla 50GB log (chyba 9002 ACTIVE_TRANSACTION), rollback do 06:38.
   Protože rollback vrátí i to, co už bylo smazáno, retence NIKDY neuspěje
   a tabulka roste dál → každý další běh je delší. A protože krok 7 job
   ukončí, NEDOBĚHNOU ani kroky 8 (optimalizace), 9 (Indexy) a
   10 (DELETE_ChangeLogEntry_NavLive).

   CO DĚLÁ TATO VERZE:
   · maže po dávkách, každá dávka = vlastní transakce → v SIMPLE se log
     po checkpointu recykluje a nikdy nepřeroste pár set MB
   · má tvrdý časový strop — když nedoběhne, skončí čistě a zbytek dobere
     příští běh (žádné desetihodinové běhy)
   · hranici data počítá JEDNOU na začátku, ne v každé dávce
   · průběžně hlásí postup (WITH NOWAIT), takže je v historii jobu vidět,
     kolik se stihlo, i když se skončí na limitu
   · RAISERROR severity 0 → hlášení job neshodí

   NASAZENÍ (v tomhle pořadí):
   1) Ověřit, že na [Date and Time] existuje index. Bez něj je každá dávka
      scan celé tabulky a dávkování situaci ZHORŠÍ — pak nejdřív index.
   2) Zkušební běh ručně v SSMS s @LimitMin = 10 → změřit propustnost
      (kolik řádků za 10 min) a podle toho doladit @Davka.
   3) Teprve pak nahradit obsah kroku 7.
   ===================================================================== */

WAITFOR DELAY '00:00:10';   -- ponecháno z původního kroku

SET NOCOUNT ON;
SET DEADLOCK_PRIORITY LOW;  -- při konfliktu ustupujeme aplikaci, ne naopak

DECLARE @Hranice  date         = CAST(DATEADD(month, -1, GETDATE()) AS date),
        @Davka    int          = 50000,          -- řádků v jedné transakci
        @LimitMin int          = 120,            -- tvrdý strop běhu v minutách
        @Pauza    varchar(12)  = '00:00:00.200', -- oddech mezi dávkami
        @Start    datetime2(0) = SYSDATETIME(),
        @Smazano  bigint       = 0,
        @Kolo     int          = 0,
        @R        int          = 1,
        @Zprava   nvarchar(300);

SET @Zprava = CONCAT(N'Start: mažu z NaviLog_1M záznamy starší než ',
                     CONVERT(varchar(10), @Hranice, 120),
                     N'. Dávka ', @Davka, N' řádků, limit ', @LimitMin, N' min.');
RAISERROR(@Zprava, 0, 1) WITH NOWAIT;

WHILE @R > 0
BEGIN
    DELETE TOP (@Davka)
    FROM [Axi].[dbo].[NaviLog_1M]
    WHERE [Date and Time] < @Hranice;

    SET @R       = @@ROWCOUNT;          -- musí být hned na dalším řádku
    SET @Smazano = @Smazano + @R;
    SET @Kolo    = @Kolo + 1;

    IF @Kolo % 20 = 0
    BEGIN
        CHECKPOINT;                     -- SIMPLE: uvolní log k dalšímu použití
        SET @Zprava = CONCAT(CONVERT(varchar(19), SYSDATETIME(), 120),
                             N'  smazáno ', @Smazano, N' řádků (', @Kolo, N' dávek)');
        RAISERROR(@Zprava, 0, 1) WITH NOWAIT;
    END

    IF @R > 0 AND DATEDIFF(minute, @Start, SYSDATETIME()) >= @LimitMin
    BEGIN
        SET @Zprava = CONCAT(N'Zastaveno na časovém limitu ', @LimitMin,
                             N' min. Smazáno ', @Smazano,
                             N' řádků, zbytek dobere příští běh.');
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

/* =====================================================================
   Kroky 5 (`6M_clear`) a 6 (`3M_clear`) mají podle délky příkazu
   (163 a 148 znaků) stejnou stavbu = stejnou vadu. Až pošleš jejich text,
   doplním sem stejnou dávkovou verzi s jejich tabulkou a retencí.
   Zatím je nepřepisuj — dnes doběhnou, ale rostou do stejné zdi.
   ===================================================================== */
