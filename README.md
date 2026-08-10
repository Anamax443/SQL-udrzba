# SQL-udrzba

Údržba a provoz SQL Serverů AXIMA — analýzy, návrhy, oponentury a provozní skripty.

> **Repozitář je privátní.** Obsahuje jména serverů, databází, servisních účtů, cesty k zálohám a e-mailové adresy. Nikdy nepřepínat na public.

---

## Aktuální téma: zálohování NAV-LIVE

**Podle čeho se postupuje:** [`docs/NAV-LIVE-zalohovani-FINAL.html`](docs/NAV-LIVE-zalohovani-FINAL.html) — konsolidované zadání, soběstačné, neodkazuje na ostatní soubory.

### Stav

| | |
|---|---|
| Databáze | NAV-LIVE (Business Central 14), 800 GB, 57 uživatelů |
| Server | B-S-W-SQL-01, SQL Server 2017 Enterprise (14.0.2120.1) |
| Problém | Zálohy transakčního logu běží jen 05:30–15:46 → RPO v noci až 13 h 44 min |
| Incident | 2026-08-10 ~05:33 — chyba 9002, log plný, transakce odmítány. Podruhé (poprvé 23. 7.) |
| Hotovo | `shrink_log` vypnut |
| **Nehotovo** | **`BackupMaintenancePlan.Tlog` má stále okno 05:30–15:46** |

### Struktura

```
docs/
  NAV-LIVE-zalohovani-FINAL.html    ← závazné zadání k realizaci
  2026-08-10-navrh-v1.md            první verze, překonaná
  2026-08-10-navrh-v2.md            technický základ — teorie, runbooky, ověřovací skripty
  oponentury/
    2026-08-10-oponentura-1.md                 proti návrhu v2, 15 nálezů (O1–O15)
    2026-08-10-oponentura-2-protinavrh-v3.md   proti externímu protinávrhu, 6 nálezů (N1–N6)
    externi/                                    podklady od jiných nástrojů, nerecenzované
sql/
  NAV-LIVE-tlog-nasazeni.sql        11 částí, postupné nasazení, každý krok vratný
evidence/
  itdashboard-events-*.csv          exporty Event Logu z incidentu
```

### Zjištěné, doložené měřením 2026-08-10

- Log soubor je **97,7 GB a už je na svém `max_size`** — dál růst nemůže
- Za noc vznikne **~94 GB logu**; denní provoz dělá ~0,5 GB/h → patnáctinásobek
- Přestavba indexů (`MaintenancePlan_AXIMA_index.Rebuildindex`) je **vypnutá** → zdroj toho objemu je neznámý
- Denní full ve 02:00 do `G:\Backup\NAV-TEST-USERS` má **`is_copy_only = 0`** → každý den posouvá základ diferenciálních záloh
- Virtuál **se zálohuje** — VSS snapshot denně 18:43, správně `COPY_ONLY`
- `BackupMaintenancePlan.Tlog`, `.Tlog2` a `Backup_NAV-LIVE_for_TEST_Optimized` mají notifikaci **NIKDY** — selhání zálohy logu se nikdo nedozví
- `notifikace2@axima.cz` dostává mail „vždy" od sedmi jobů → únava z upozornění
- Úklid starých záloh je **uvnitř SSIS balíčku subplanu** → vypnutí zálohy vypne i mazání
- Enterprise Edition, Instant File Initialization zapnuto, VLF 435, G: má 1 459 GB volných
- Export z ITDashboardu je **stropovaný na 300 řádků** → skutečný rozsah incidentu nikdo neviděl

### Otevřené otázky

1. Kam ukládá VSS záloha a je fyzicky mimo tento server?
2. Jaká je retence `G:\Backup\NAV-TEST-USERS`, na které visí diff řetěz?
3. Který job vyrábí denní full ve 02:00? (`NAV-LIVE_to_NAV-TEST-USERS` je vypnutý)
4. Je G: jiné fyzické pole než E: a F:?
5. Co v noci generuje 94 GB logu?
6. **Jaké RPO a RTO firma potřebuje?** — jediná otázka, na kterou nemůže odpovědět IT

---

## Zásady

- **Produkční zásahy dělá operátor**, ne automat. Skripty se dodávají hotové k vložení do SSMS.
- **Každý krok musí být vratný** a v `sql/` má mít uvedený příkaz na návrat.
- **Maintenance plány se neupravují skriptem.** Uložení plánu v designeru přepíše schedule ze své definice — pravděpodobná příčina, proč se oprava z 2026-07-23 nikdy neprojevila. Nové úlohy zakládat jako samostatné T-SQL joby, které jsou čitelné a verzovatelné.
- **Do repozitáře nepatří** hesla, connection stringy s hesly, `.bak` soubory ani exporty s osobními údaji.

## Kandidáti k doplnění

V `Downloads` leží další materiály k témuž systému, které zatím nejsou v repozitáři, protože neprošly kontrolou obsahu:

- `BC_INDEX_ANALYSIS-BSWNAV01_NAV-LIVE.txt` — analýza indexů
- `NAV-LIVE_MAXDOP_Change_4to8_WithMeasurement.sql` — změna MAXDOP s měřením
- `Hodnoceni_NAV-LIVE_SQL_2025-10-31.pdf` — posouzení SQL z října 2025
- `Restore-NAV-TEST.ps1` — obnova testovací databáze a demilitarizace

Před přidáním projít, zda neobsahují přihlašovací údaje.
