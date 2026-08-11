# HANDOFF — kde jsme

> Tenhle soubor je **zdroj pravdy o aktuálním stavu**. Kdo přebírá práci (člověk i AI), čte nejdřív tohle, pak [README.md](README.md), pak [docs/NAV-LIVE-zalohovani-FINAL.html](docs/NAV-LIVE-zalohovani-FINAL.html).
>
> Poslední aktualizace: **2026-08-11 ráno**

---

## 1. Stav v jedné tabulce

| | Stav |
|---|---|
| RPO Ne–Pá | **15 minut** (bylo 13 h 44 min) ✅ |
| RPO sobota | 5,5 h + 8 h díra ❌ — chybí jeden checkbox |
| Chyba 9002 | zmenšena z hodin na **3 minuty**, ale **vrací se** ⚠ |
| Příčina nočního objemu | **nalezena** — job `1xdenne`, krok 1 `update_index` ✅ |
| Kapacita záloh | **není problém** — komprese 6,4:1 ✅ |
| Notifikace u zálohovacích jobů | pořád **NIKDY** ❌ |
| Obnova k času | **nikdy netestována** ❌ |

---

## 2. Co je hotové

| Kdy | Co | Ověřeno |
|---|---|---|
| 2026-08-10 | `shrink_log` vypnut | `sysjobs.enabled = 0` |
| 2026-08-10 14:48 | `BackupMaintenancePlan.Tlog` okno **05:30–15:46 → 00:00:00–23:59:59** | `date_modified` = 2026-08-10 14:48:34 |
| 2026-08-11 08:25 | Zálohy logu běží **24/7**, 4× v každé hodině včetně 0–5 | `backupset` po hodinách |
| 2026-08-10 | Dokumentace v gitu, repo privátní | commit `cdffb81` |

---

## 3. Co zbývá — v pořadí

### 3.1 Dnes večer — nárazník na noc

```sql
ALTER DATABASE [NAV-LIVE] MODIFY FILE (NAME = N'NAV_LIVE_Log', MAXSIZE = 250GB);
```

Metadatová změna, lze za provozu, okamžitá. F: má 391 GB volných. Bez toho se chyba 9002 dnes v noci zopakuje.

Volitelně kolem 22:00 předrostit soubor, aby v noci neprobíhalo nulování po 4 GB krocích. **Ne za provozu** — nulování 40 GB zastaví zápisy do logu na minuty.

### 3.2 Sobota — jeden checkbox

SQL Agent → Jobs → `BackupMaintenancePlan.Tlog` → Schedules → zaškrtnout **Saturday**.
Kontrola: `freq_interval` musí být **127** (teď je 63). Pak je `Tlog2` nadbytečný a lze vypnout.

### 3.3 Skutečná oprava nočního objemu

Přečíst celý krok 1 jobu `1xdenne`:

```sql
DECLARE @cmd nvarchar(max);
SELECT @cmd = s.command FROM msdb.dbo.sysjobsteps s
JOIN msdb.dbo.sysjobs j ON j.job_id = s.job_id
WHERE j.name = N'1xdenne' AND s.step_id = 1;
PRINT SUBSTRING(@cmd,1,4000); PRINT SUBSTRING(@cmd,4001,4000); PRINT SUBSTRING(@cmd,8001,4000);
```

Cíl: přejít z plošné přestavby na prahovou logiku — `< 5 %` nic, `5–30 %` REORGANIZE, `> 30 %` REBUILD `WITH (ONLINE = ON)` (edice je Enterprise). Očekávaný efekt: −70 až −90 % generovaného logu.

### 3.4 Notifikace zálohovacích jobů

`BackupMaintenancePlan.Tlog`, `.Tlog2` a `Backup_NAV-LIVE_for_TEST_Optimized` mají `notify_level_email = 0`. Skript je v [sql/NAV-LIVE-tlog-nasazeni.sql](sql/NAV-LIVE-tlog-nasazeni.sql), část 9 (hlídač) — nebo rovnou:

```sql
EXEC msdb.dbo.sp_update_job @job_name = N'BackupMaintenancePlan.Tlog',
     @notify_level_email = 2, @notify_email_operator_name = N'AdminOperatorRobot';
```

### 3.5 Rozhodnutí, které čeká

- **`COPY_ONLY`** u denní full ve 02:00 do `G:\Backup\NAV-TEST-USERS` — buď doplnit, nebo zrušit diffy (kap. 11 nasazovacího skriptu)
- **Test obnovy k časovému bodu** — nikdy neproběhl; `Restore-NAV-TEST.ps1` už obnovu 700 GB umí, chybí `STOPAT` varianta
- **RPO a RTO** — má potvrdit vedení, ne IT

---

## 4. Naměřená fakta (nepřepisovat odhady)

### Databáze a stroj

| | |
|---|---|
| NAV_LIVE_Data | 683,6 GB, strop 878,9 GB, využito 565,1 GB, růst 4 GB pevně, E: |
| NAV_LIVE_Log | **97,7 GB = na svém `max_size`**, F: (391 GB volných) |
| VLF | 435 — v pořádku, náprava netřeba |
| Edice | **Enterprise, Core-based** |
| Instant File Initialization | **zapnuto** (datové soubory) |
| Servisní účet | `AXINETWORK\gmsa-SQL$` |
| Disky volné | C: 174 · D: 984 · E: 280 · F: 391 · **G: 1 459** · T: 380 GB |

### Profil transakčního logu (2026-08-11)

```
hodina  0–3     ~0,7 GB celkem
hodina  4      94,59 GB   ← 1xdenne
hodina  5      45,99 GB   ← 1xdenne
hodina  6–18   ~0,3–0,5 GB/h  (běžný provoz 57 uživatelů)
hodina 19–22   ~4,4 GB celkem
                          celkem ~151 GB/den
```

**Komprese 6,4 : 1** (měřeno: 29,43 GB raw → 4,57 GB na disku).
→ ~23 GB/den na disku, retence 14 dní ≈ **330 GB**. G: má 1 459 GB. **Kapacita není omezením.**

### Topologie záloh

| Kdy | Typ | Kam | `copy_only` |
|---|---|---|---|
| á 15 min, 24/7 | LOG | `G:\Backup\NAV-LIVE\NAV-LIVE` | — |
| 01:30 denně | DIFF | `G:\Backup\NAV-LIVE\NAV-LIVE` | 0 |
| 02:00 Út–So | FULL | `G:\Backup\NAV-TEST-USERS` | **0 ← past** |
| ~01:30 neděle | FULL | `G:\Backup\NAV-LIVE\NAV-LIVE` | 0 |
| 18:43 denně | FULL | VSS snapshot (GUID) | 1 ✅ |

Úklid starých záloh je **uvnitř SSIS balíčku subplanu `Tlog`** a běží každých 15 minut spolu se zálohou. Vypnutí jobu zastaví i mazání.

---

## 5. Opravy dřívějších závěrů

Nepřebírat starší tvrzení z dokumentů bez porovnání s tímhle seznamem.

| Původně | Skutečnost |
|---|---|
| „Údržba indexů neběží, `Rebuildindex` je vypnutý" | **Běží** — jako krok 1 jobu `1xdenne`. Vypnutý plán je jeho předchůdce. |
| „Varianta A může zaplnit disk, 3–5 TB" | **Neplatí.** Komprese 6,4:1 → 14 dní ≈ 330 GB. |
| „Zvětšení stropu logu je jen odklad" | Platilo, dokud zálohy neběžely v noci. **Teď je to správný nárazník.** |
| „Zkrátit interval na 5 minut sníží RPO" | Sníží, ale **na noční špičku nepomůže** — log drží dlouhá transakce, ne frekvence záloh. |
| „`Tlog2` je redundantní" | Není — kryje sobotu. Nadbytečným se stane až po `freq_interval = 127`. |
| „Incident trval 74 sekund" | Artefakt exportu. ITDashboard exportuje **max 300 řádků** (ověřeno na třech dávkách). |

---

## 6. Incidenty

**2026-07-23** — chyba 9002, diagnóza provedena, oprava navržena, **nikdy nenasazena** (`date_modified` schedule zůstal 2025-01-10).

**2026-08-10 ~05:33** — chyba 9002, běžela hodiny, poslední záznam 05:34:32 když doběhla ranní záloha. Skutečný rozsah neznámý (strop exportu).

**2026-08-11 05:12:18–05:15:35** — chyba 9002 **znovu, ale jen 3 minuty**. Zálohy logu běžely celou noc správně. Příčina: `1xdenne` (04:00, běh 1 h 46 min) drží dlouhou transakci přestavby indexu, log se nemá jak uvolnit. Záloha v 05:31 pak odbavila 29,43 GB naráz.

---

## 7. Věci mimo zálohování, které stojí za pozornost

- **`Emergency_Cache_Warming`** selhává nepřetržitě, desítky × denně, měsíce. Práh PLE zvednutý z 300 na 3000. Běží 6–10 min při 5min intervalu → překrývá se sám se sebou. Nikoho neinformuje. Kandidát na vypnutí.
- **`00_Warming Script pro NAV-LIVE`** běží 36–49 minut a startuje každých 40 minut → prakticky nepřetržitě.
- **`000_kontrola_vykonu_SQL`** každých 5 minut, běh ~3 minuty → taky skoro nepřetržitě.
- Tři úlohy, které serveru neustále čtou data, aby změřily nebo „nahřály" to, co samy vytlačují z cache. Pravděpodobně souvisí s FlowField problémem v NAV (`VarChar` vs `Variant` → dopočet řádek po řádku).
- **`notifikace2@axima.cz`** dostává mail „vždy" od sedmi jobů → únava z upozornění.
- **Event 1511** — opakované přihlašování na produkční SQL s dočasným profilem (2026-08-10 16:41–17:12).
- **Strop exportu ITDashboardu na 300 řádků** — patří do backlogu projektu ITDashboard, ne sem.

---

## 8. Jak pracujeme

- Produkční zásahy provádí **operátor**, ne agent. Skripty se dodávají hotové k vložení do SSMS.
- Každý zásah musí být **vratný** a mít u sebe příkaz na návrat.
- **Maintenance plány neupravovat skriptem** — uložení plánu v designeru přepíše schedule ze své definice.
- Po každé změně **ověřit z dat**, ne z toho, že dialog nehlásil chybu (GUI změna 2026-08-10 dopoledne se tiše neuložila).
- Commitovat jako `mtrnka@axima.cz` (lokální `git config`).
