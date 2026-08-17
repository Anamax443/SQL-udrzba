# NaviLog a Change Log Entry — co se zjistilo (2026-08-17)

> Druhé téma projektu, vedle zálohování NAV-LIVE. Zdroj: exporty Event Logu v
> [evidence/](../evidence/) a dotazy spuštěné operátorem v SSMS na `B-S-W-SQL-01`.
> Diagnostika **uzavřená**, zásahy zatím žádné.

---

## 1. K čemu to celé je

V produkci (NAV-LIVE) se `Change Log Entry` drží krátký — okno 3 měsíce — aby
Navision nebyl zahlcený. Historie se před smazáním kopíruje do databáze `Axi`,
kde se v ní dá hledat, aniž by to zatěžovalo produkci. Stupně `_6M`, `_3M`, `_1M`
jsou zmenšené kopie pro běžné dotazy „co bylo nedávno".

**Ten mechanismus dnes nefunguje.** Kopírování do `Axi` běží, ale mazání
v produkci stojí od 2026-06-27.

---

## 2. Řetěz v jedné větě

Nedávkovaný `DELETE` v kroku 7 přeroste 50GB log databáze `Axi`, job spadne — a
protože `on_fail_action = 2` („Quit the job reporting failure"), **nedoběhnou
kroky 8, 9 ani 10**. Krok 10 je právě to mazání v NAV-LIVE.

---

## 3. Job `Axi_Navilog_a_jine_Jardoviny`

`job_id = 0xD4752DB20260CB4EA69A8FC1C2D7A709` · schedule 30 „Axi" · `enabled = 1`
· beze změny od **2025-10-31**. Všechny kroky `on_fail_action = 2`.

| # | Krok | DB | Co dělá | Stav |
|---|---|---|---|---|
| 1 | `NaviLog_plneni` | Axi | NAV-LIVE Change Log → `NaviLog`, inkrementálně podle `Entry No_` | běží |
| 2 | `6M` | Axi | `NaviLog` → `NaviLog_6M` (< 6 měsíců) | běží |
| 3 | `3M` | Axi | `NaviLog_6M` → `NaviLog_3M` (< 3 měsíce) | běží |
| 4 | `1M` | Axi | `NaviLog_3M` → `NaviLog_1M` (< 1 měsíc) | běží |
| 5 | `6M_clear` | Axi | `DELETE` z `_6M` starší 6 měsíců | běží, stejná vada |
| 6 | `3M_clear` | Axi | `DELETE` z `_3M` starší 3 měsíců | běží, stejná vada |
| 7 | `1M_clear` | Axi | `DELETE` z `_1M` starší 1 měsíce | **padá** |
| 8 | `optimalizace` | Axi | **celý zakomentovaný** (jsou v něm `DBCC SHRINKFILE`) | nedoběhne |
| 9 | `Indexy` | Axi | zakládání indexů | nedoběhne |
| 10 | `DELETE_ChangeLogEntry_NavLive` | **NAV-LIVE** | `DELETE` Change Logu starší 3 měsíců | **nedoběhne** |

Krok 7 doslova:

```sql
WAITFOR DELAY '00:00:10'
DELETE FROM [Axi].[dbo].[NaviLog_1M]
WHERE [Date and Time] < CAST(DATEADD(m, -1, GetDate()) AS date)
```

Běh 2026-08-15 20:01 → 9002 v 06:23 → rollback → pád v 06:38 (10 h 37 min).
**Rollback vrátí i to, co už bylo smazáno, takže retence nikdy neuspěje.**

> Krok 8 nechat zakomentovaný. `SHRINKFILE` po každém běhu je anti-pattern —
> stejný, jaký se v srpnu vypínal u jobu `shrink_log`.

---

## 4. `Axi` — naměřená fakta

| | |
|---|---|
| Recovery model | **SIMPLE** (zálohy logu neexistují a nepomohly by) |
| `AXI.mdf` | 750 GB, **použito 676 GB, volno 56 GB**, strop 879 GB, `E:` |
| `AXI.ldf` | 50 GB = přesně na `max_size`, aktuálně použito 25 MB, `F:` |
| Zálohy | jen plné, denně ~18:42, 654 → 692 GB · **RPO 24 h** |

### Tabulky rodiny NaviLog

| Tabulka | Řádků | GB (data) | Struktura |
|---|---|---|---|
| `NAVILOG_ARCHIVE` | 686 701 029 | 64,9 | **halda** + 1 NC index |
| `NaviLog` | 404 396 993 | 56,2 | clustered PK na `Entry No_` + NC |
| `NaviLog_6M` | 374 584 804 | 52,3 | **halda** + 2 NC indexy |
| `NaviLog_3M` | 236 666 549 | 33,5 | **halda** + 2 NC indexy |
| `NaviLog_1M` | 120 250 104 | 16,8 | **halda** + 2 NC indexy |

Data ~224 GB, ale soubor je použitý na 676 GB → **~450 GB jsou nonclustered
indexy**. Sedí to: index `idx_*_TableNo_UserID_OldNewValue` nese `Old Value`
a `New Value`, tedy nejširší sloupce — je to prakticky druhá kopie dat.

### Dvě vady, které brání jednoduché opravě

1. **Haldy.** `DELETE` z haldy neuvolní stránky. Kroky 5 a 6 tedy mažou řádky,
   ale místo v souboru nevracejí.
2. **Na `[Date and Time]` není index** — nikde, všechny vedou přes `Table No_`.
   Každý `DELETE` podle data je tedy full scan. Dávkovaná verze by scan dělala
   v každé dávce → **dávkování samo o sobě situaci zhorší**, dokud není index.

### Kontrolní výpočet

`NaviLog_1M` má 120,3 mil. řádků = při 2,45 mil./den **49 dní** místo 30.
Nezávisle potvrzuje, že krok 7 přestal mazat na přelomu června.

---

## 5. Change Log Entry v NAV-LIVE

| Tabulka | Řádků | GB (jen cluster) |
|---|---|---|
| `AXIMA$Change Log Entry` | **350 867 119** | 126,5 |
| `AXIMA Slovensko$Change Log Entry` | 33 877 129 | 10,4 |
| ostatní firmy | ~42 000 | ~0,03 |

**Pozor, tohle jsou jen clustery.** S indexy je `AXIMA$Change Log Entry`
podstatně větší:

| Struktura | GB |
|---|---|
| clustered (`$0`) | 126,5 |
| `$4` | 33,5 |
| `$5` | 30,0 |
| `$3` | 23,5 |
| `$1` | 17,7 |
| `$2` | 10,8 |
| `IX_ChangeLog_PKField2Value` | 7,4 |
| **celkem** | **249,5** |

Nonclustered indexy = **123 GB**, tedy skoro tolik co data. Se slovenskou
firmou dělá Change Log dohromady ~270 GB = **zhruba 47 % obsazeného místa
v NAV-LIVE**. Smazání 125 mil. z 350 mil. řádků (36 %) uvolní ~90 GB.

### Soubory NAV-LIVE (2026-08-17)

| Soubor | Velikost | Použito | Volno |
|---|---|---|---|
| `NAV_LIVE_Data` | 687,6 GB | 581,1 GB | **106,5 GB** |
| `NAV_LIVE_Log` | 109,7 GB | 4,7 GB | 105,0 GB |

Log má oproti srpnu zvednutý strop a je téměř prázdný — spolu se zálohami
logu á 15 minut (od 2026-08-17 sedm dní v týdnu) je prostor pro dávkový úklid
bezpečný.

```
nejstarší:  Entry No_ 2 303 791 123   2026-03-27 00:00:00.017
nejnovější: Entry No_ 2 684 225 319   2026-08-17 08:56:46.257
```

Čas `00:00:00.017` je podpis mazání s hranicí na celý den. Krok 10 má okno
3 měsíce → **naposledy doběhl 2026-06-27**, tedy je mrtvý 51 dní. Za tu dobu
přibylo ~125 mil. řádků / ~45 GB. **Přírůstek 2,45 mil. řádků ≈ 0,9 GB/den.**

**Nic jiného tu tabulku nemaže** — ověřeno třemi způsoby:
zamrzlé dno na hranici 2026-03-27 · hledání přes všechny kroky všech jobů
(vrátí jen kroky 1 a 10) · 48 položek BC Job Queue, mezi nimi **žádný report 510**
„Delete Change Log Entries".

**Slovenská firma se neuklízí vůbec** — začíná na `Entry No_ = 1` z 2016-12-08.
Krok 10 řeší jen firmu AXIMA.

### Co se loguje

Profil posledního milionu záznamů:

| Table No_ | Podíl |
|---|---|
| **60105** | **39,0 %** |
| **60030** | **31,2 %** |
| 39 (Purchase Line) | 5,1 % |
| 5407 | 4,7 % |
| zbytek (21 tabulek) | ~20 % |

**Dvě vlastní tabulky (ID > 50000) dělají 70 % objemu.** Vypnutí logování u nich
v *Change Log Setup* by srazilo přírůstek z 2,45 mil. na ~730 tis. řádků denně —
to je větší páka než jakékoli mazání. Za pozornost stojí i položky 110–123
(zaúčtované doklady), které se z principu nemění.

---

## 6. Kdo ta data čte

Job **`BusinessCentral_info`** — rozbor licencí. Kroky 1, 2 a 4 čtou
**výhradně `[Axi].[dbo].[NaviLog]`** a plní `LicenceUsageSummary`,
`UserTableUsageSummary`, `UserTableUsageDetailed` v databázi **`AXI_DEV`**.
Kroky 5 a 6 čtou `Report Activity Log` z NAV-LIVE.

Stupně `_6M`, `_3M`, `_1M` a `NAVILOG_ARCHIVE` **nečte žádný job ani procedura** —
slouží k ručním dotazům uživatelů. Reálné využití ukáže
`sys.dm_db_index_usage_stats` (zatím nezměřeno).

### Vedlejší nálezy

- Kroky 5 a 6 jobu `BusinessCentral_info` jsou **znak po znaku totožné**.
- Výsledky licenčního rozboru se ukládají do **vývojové** databáze `AXI_DEV`.
- Licenční statistika počítá `GROUP BY YEAR(...)` nad `NaviLog`, která drží jen
  ~165 dní. Přes `MERGE` se hodnota za aktuální rok při každém běhu přepíše →
  **číslo za rok během roku klesá**, jak starší měsíce vypadávají z okna.
- `NAVILOG_ARCHIVE` nikdo neplní ani nečte — vypadá na jednorázový ruční odklad.

---

## 7. Plán

**Pořadí je dané tím, že pád kroku 7 je zároveň pojistka:** dokud padá, krok 10
se sám nespustí a doháněcí mazání v produkci máme plně pod kontrolou ručně.

1. **NAV-LIVE Change Log — doháněcí běhy ručně.**
   [sql/NAV-LIVE-ChangeLog-uklid-davkove.sql](../sql/NAV-LIVE-ChangeLog-uklid-davkove.sql):
   maže podle `Entry No_` (hranice binárním hledáním), dávky s commitem, časový
   strop, pojistka na zaplnění logu. Nejdřív `@LimitMin = 15` na změření
   propustnosti; celkem ~125 mil. řádků, odhad 2–4 noci.
   *Před prvním během ověřit, že `NaviLog` obsahuje vše, co se v produkci maže.*
2. **Nahradit krok 10** tímtéž skriptem — od té chvíle jen denní přírůstek.
3. **Tiery v `Axi`**: dát jim clusterovaný index na `[Date and Time]`. Vyřeší to
   naráz tři věci — dotazy uživatelů budou seek místo scanu, `DELETE` přestane
   být scan, a zmizí problém haldy. Teprve pak dávkovat kroky 5–7
   ([sql/Axi-NaviLog-1M-clear-davkove.sql](../sql/Axi-NaviLog-1M-clear-davkove.sql)).
   Kvůli 56 GB volného místa začít od nejmenší `_1M`, tím se uvolní prostor pro `_3M`, pak `_6M`.
4. **Change Log Setup** — vypnout logování u 60105 a 60030, pokud je nikdo nečte.
5. Rozhodnout o `NAVILOG_ARCHIVE` (65 GB) a o retenci slovenské firmy.

---

## 8. Otevřené body

- `sp_spaceused` a přesné rozložení indexů u `NaviLog%` (kde přesně leží těch 450 GB).
- `sys.dm_db_index_usage_stats` — čte někdo tiery a archiv?
- Co jsou tabulky **60105** a **60030** (překlad přes `[NAV-LIVE].[dbo].[Object]`).
- Kolik místa je uvnitř `NAV_LIVE_Data` (obdoba `FILEPROPERTY` dotazu pro `Axi`).
- **Historie jobů mizí**: `jobhistory_max_rows = 1000`, `max_rows_per_job = 100`;
  pět jobů drží po 100 řádcích. `Emergency_Cache_Warming` běží 288×/den a průběžně
  vymazává historii všech ostatních. Náprava: SSMS → SQL Server Agent → Properties
  → History, ~50 000 / 2 000, projeví se po restartu služby Agenta.
