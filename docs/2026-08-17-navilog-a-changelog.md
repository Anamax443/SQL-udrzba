# NaviLog a Change Log Entry — co se zjistilo (2026-08-17)

> Druhé téma projektu, vedle zálohování NAV-LIVE. Zdroj: exporty Event Logu v
> [evidence/](../evidence/) a dotazy spuštěné operátorem v SSMS na `B-S-W-SQL-01`.
> **Rozpracované** — otevřené body jsou na konci.

---

## 1. Řetěz v jedné větě

Nedávkovaný `DELETE` v kroku 7 přeroste 50GB log databáze `Axi`, job spadne — a
protože kroky se vyhodnocují po sobě, **nedoběhnou ani kroky 8, 9 a 10**, mezi
nimi úklid `Change Log Entry` v NAV-LIVE. Ten proto stojí od jara a tabulka
narostla na 126,5 GB.

---

## 2. Job `Axi_Navilog_a_jine_Jardoviny`

`job_id = 0xD4752DB20260CB4EA69A8FC1C2D7A709` · schedule 30 „Axi" · `enabled = 1`
· beze změny od **2025-10-31**.

| # | Krok | DB | Stav |
|---|---|---|---|
| 1 | `NaviLog_plneni` | Axi | |
| 2 | `6M` | Axi | |
| 3 | `3M` | Axi | |
| 4 | `1M` | Axi | |
| 5 | `6M_clear` | Axi | stejná stavba jako 7 → **stejná vada** |
| 6 | `3M_clear` | Axi | stejná stavba jako 7 → **stejná vada** |
| 7 | `1M_clear` | Axi | **padá** |
| 8 | `optimalizace` | Axi | nedoběhne |
| 9 | `Indexy` | Axi | nedoběhne |
| 10 | `DELETE_ChangeLogEntry_NavLive` | **NAV-LIVE** | nedoběhne |

Krok 7 doslova:

```sql
WAITFOR DELAY '00:00:10'
DELETE FROM [Axi].[dbo].[NaviLog_1M]
WHERE [Date and Time] < CAST(DATEADD(m, -1, GetDate()) AS date)
```

Jedna transakce přes celý rozsah. Běh 2026-08-15 20:01 → 9002 v 06:23 →
rollback → pád v 06:38. **Rollback vrátí i to, co už bylo smazáno, takže
retence nikdy neuspěje** a každý další běh je delší.

Náhrada (dávky + časový strop): [sql/Axi-NaviLog-1M-clear-davkove.sql](../sql/Axi-NaviLog-1M-clear-davkove.sql).
**Nenasazeno** — čeká se na `sp_spaceused` a indexy `NaviLog_1M`.

---

## 3. `Axi` — naměřená fakta

| | |
|---|---|
| Recovery model | **SIMPLE** (zálohy logu neexistují a nepomohly by) |
| `AXI.mdf` | 732 GB, strop 879 GB, `E:` |
| `AXI.ldf` | **50 GB = přesně na svém `max_size`**, `F:` |
| Zálohy | jen plné, denně ~18:42, 654 → 692 GB · **RPO 24 h** |

---

## 4. Change Log Entry v NAV-LIVE

| Tabulka | Řádků | MB |
|---|---|---|
| `AXIMA$Change Log Entry` | **350 867 119** | **129 518** |
| `AXIMA Slovensko$Change Log Entry` | 33 877 129 | 10 599 |
| ostatní firmy | ~42 000 | ~29 |

Dohromady **137 GB ≈ 20 % datového souboru NAV-LIVE** (684 GB).

### Rozsah dat

```
nejstarší:  Entry No_ 2 303 791 123   2026-03-27 00:00:00.017
nejnovější: Entry No_ 2 684 225 319   2026-08-17 08:56:46.257
```

Čas `00:00:00.017` je podpis mazání s hranicí na celý den → krok 10 **naposledy
úspěšně doběhl s hranicí 2026-03-27**. Z toho zpětně:

| Okno kroku 10 | Naposledy doběhl |
|---|---|
| 1 měsíc | ~2026-04-27 |
| 3 měsíce | ~2026-06-27 |
| 4 měsíce | ~2026-07-27 |
| 6 měsíců | vyloučeno (vyšlo by na budoucnost) |

**Přírůstek 2,45 mil. řádků/den** (350,9 mil. za 143 dní).

**Slovenská firma se neuklízí vůbec** — začíná na `Entry No_ = 1` z 2016-12-08.
Krok 10 řeší jen firmu AXIMA.

### Indexy

Cluster na `Entry No_`, k tomu **šest nonclustered** ($1–$5 + `IX_ChangeLog_PKField2Value`);
`$4` nese i `New Value`, je tedy široký. Každý smazaný řádek se odstraňuje ze
sedmi struktur.

`[Date and Time]` **není nikde vedoucí sloupec** (v `$2` je až druhý za `Table No_`)
→ mazat podle data nejde efektivně. Správná cesta: najít hraniční `Entry No_`
binárním hledáním (~30 seeků) a mazat po dávkách `WHERE [Entry No_] < @Hranice`,
tedy sekvenčně po clusteru.

### Odhad práce

| Cílová retence | Smazat | Uvolní v souboru |
|---|---|---|
| 1 měsíc | ~275 mil. řádků (78 %) | ~99 GB |
| 3 měsíce | ~125 mil. řádků | ~45 GB |
| 4 měsíce | ~52 mil. řádků | ~19 GB |

---

## 5. Souvislosti mimo tenhle job

**Kapacita `E:`** — disk 1 700 GB, volných 269,7 GB. `NAV_LIVE_Data` 684 GB
(strop 879) + `AXI.mdf` 732 GB (strop 879) = ty dva soubory prakticky *jsou*
ten disk. Do svých stropů potřebují ještě 342 GB, k dispozici je 270 →
**stropy souborů jsou o ~70 GB přeprodané**, dřív než na `MAXSIZE` narazí disk.

**Historie jobů mizí.** `jobhistory_max_rows = 1000`, `max_rows_per_job = 100`.
Pět jobů (mj. `Emergency_Cache_Warming`, který běží 288×/den, a
`BackupMaintenancePlan.Tlog`) drží po 100 řádcích = polovinu stropu. Cokoli, co
běží jednou denně, je do druhého dne z historie venku — proto u
`Axi_Navilog_a_jine_Jardoviny` nebyl po incidentu žádný záznam. Náprava:
SSMS → SQL Server Agent → Properties → History, ~50 000 / 2 000; projeví se po
restartu služby Agenta.

**`Emergency_Cache_Warming`** — 186 pádů za 2,6 dne, trvání dvojvrcholové
(92× 6 min, 93× přesně 10 min = 600 s). Samostatné téma, diagnostika v
[sql/Emergency_Cache_Warming-diagnostika.sql](../sql/Emergency_Cache_Warming-diagnostika.sql).

---

## 6. Otevřené body

1. **Text kroku 10** — bez něj neznáme retenční okno, tedy ani objem mazání.
2. **Text kroků 5 a 6** — podle délky příkazu stejná vada, jen menší tabulky.
3. `on_fail_action` jednotlivých kroků — potvrdit, že pád kroku 7 job opravdu ukončí.
4. `sp_spaceused` a indexy `NaviLog_1M` — velikost dávky a jestli je nutný index.
5. Co se vlastně loguje — *Change Log Setup* v BC; mazání je úklid následku,
   páka je logovat míň polí. Mapování toku: [sql/ChangeLog-mapovani-toku.sql](../sql/ChangeLog-mapovani-toku.sql).
6. Slovenská firma — rozhodnout retenci, dnes žádná.
7. **Pořadí zásahů:** krok 10 přepsat na dávky **dřív**, než se opraví krok 7.
   NAV-LIVE je ve FULL recovery; kdyby se krok 10 odblokoval v dnešní podobě,
   udělal by tam přesně tu 9002, která se v srpnu opravovala.
