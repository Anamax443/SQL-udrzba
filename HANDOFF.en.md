# HANDOFF — where we are

> This file is the **source of truth for the current state**. Whoever picks up the work (human or AI) reads this first, then [README.en.md](README.en.md), then [docs/NAV-LIVE-backup-FINAL.en.html](docs/NAV-LIVE-backup-FINAL.en.html).
>
> Czech original: [HANDOFF.md](HANDOFF.md) · The Czech version is authoritative.
>
> Last updated: **2026-08-11, morning**

---

## 1. Status in one table

| | State |
|---|---|
| RPO Sun–Fri | **15 minutes** (was 13 h 44 min) ✅ |
| RPO Saturday | 5.5 h + 8 h gap ❌ — one checkbox missing |
| Error 9002 | reduced from hours to **3 minutes**, but **still recurring** ⚠ |
| Cause of nightly log volume | **found** — job `1xdenne`, step 1 `update_index` ✅ |
| Backup capacity | **not a problem** — compression 6.4:1 ✅ |
| Notifications on backup jobs | still **NEVER** ❌ |
| Point-in-time restore | **never tested** ❌ |

---

## 2. Done

| When | What | Verified by |
|---|---|---|
| 2026-08-10 | `shrink_log` disabled | `sysjobs.enabled = 0` |
| 2026-08-10 14:48 | `BackupMaintenancePlan.Tlog` window **05:30–15:46 → 00:00:00–23:59:59** | `date_modified` = 2026-08-10 14:48:34 |
| 2026-08-11 08:25 | Log backups run **24/7**, 4× in every hour including 0–5 | `backupset` grouped by hour |
| 2026-08-10 | Documentation in git, repository private | commit `cdffb81` |

---

## 3. Remaining — in order

### 3.1 Tonight — buffer for the night

```sql
ALTER DATABASE [NAV-LIVE] MODIFY FILE (NAME = N'NAV_LIVE_Log', MAXSIZE = 250GB);
```

Metadata-only change, safe during production, instant. F: has 391 GB free. Without it, error 9002 will recur tonight.

Optionally pre-grow the file around 22:00 so the 4 GB growth increments don't happen during the night. **Not during production hours** — zeroing 40 GB stalls log writes for minutes.

### 3.2 Saturday — one checkbox

SQL Agent → Jobs → `BackupMaintenancePlan.Tlog` → Schedules → tick **Saturday**.
Check: `freq_interval` must be **127** (currently 63). Then `Tlog2` becomes redundant and can be disabled.

### 3.3 The real fix for nightly log volume — proposal ready

Step 1 of job `1xdenne` has been read and analysed. It does this:

```sql
DECLARE @PROCENT AS int = 10;
'ALTER INDEX [...] REBUILD;'
WHERE ips.avg_fragmentation_in_percent > @PROCENT AND ips.page_count > 100
```

| # | Finding | Impact |
|---|---|---|
| 1 | Threshold 10 %, single action = full rebuild | **primary source of the 140 GB** |
| 2 | `page_count > 100` (800 kB) instead of the usual 1000 | a lot of unnecessary small work |
| 3 | `UPDATE STATISTICS` on top, once per **index** of the same table | REBUILD already updates statistics → pure waste |
| 4 | Errors swallowed into a table variable | **the job reports OK even if half of it fails** |
| 5 | No `SORT_IN_TEMPDB`, no `MAXDOP` | sorting inside NAV-LIVE, unbounded parallelism |

**Proposed replacement: [sql/1xdenne-krok1-udrzba-indexu-navrh.sql](sql/1xdenne-krok1-udrzba-indexu-navrh.sql)**

- tiered logic: `< 5 %` nothing · `5–30 %` REORGANIZE · `> 30 %` REBUILD
- `page_count >= 1000`, 90-minute time budget, `SORT_IN_TEMPDB` + `MAXDOP`
- `UPDATE STATISTICS` only for tables not rebuilt, and once per table
- `RAISERROR` at the end → the job **actually fails** when something fails

**Rollout:** first run it with `@JenVypis = 1` (changes nothing, only prints the plan and the volume in GB per category). Only then replace the contents of step 1.

> `ONLINE = ON` does **not** reduce log volume — it adds a version store. It helps availability, not the log. The threshold is the real lever.

### 3.4 Notifications on backup jobs

`BackupMaintenancePlan.Tlog`, `.Tlog2` and `Backup_NAV-LIVE_for_TEST_Optimized` have `notify_level_email = 0`:

```sql
EXEC msdb.dbo.sp_update_job @job_name = N'BackupMaintenancePlan.Tlog',
     @notify_level_email = 2, @notify_email_operator_name = N'AdminOperatorRobot';
```

### 3.5 Decisions pending

- **`COPY_ONLY`** on the daily 02:00 full to `G:\Backup\NAV-TEST-USERS` — either add it, or drop the differentials
- **Point-in-time restore test** — never performed; `Restore-NAV-TEST.ps1` already restores 700 GB, the `STOPAT` variant is missing
- **RPO and RTO** — to be confirmed by management, not by IT

---

## 4. Measured facts (do not replace with estimates)

### Database and machine

| | |
|---|---|
| NAV_LIVE_Data | 683.6 GB, cap 878.9 GB, used 565.1 GB, growth 4 GB fixed, E: |
| NAV_LIVE_Log | **97.7 GB = at its `max_size`**, F: (391 GB free) |
| VLF count | 435 — fine, no remediation needed |
| Edition | **Enterprise, Core-based** |
| Instant File Initialization | **enabled** (data files) |
| Service account | `AXINETWORK\gmsa-SQL$` |
| Free disk space | C: 174 · D: 984 · E: 280 · F: 391 · **G: 1 459** · T: 380 GB |

### Transaction log profile (2026-08-11)

```
hour  0–3     ~0.7 GB total
hour  4      94.59 GB   ← 1xdenne
hour  5      45.99 GB   ← 1xdenne
hour  6–18   ~0.3–0.5 GB/h  (normal load, 57 users)
hour 19–22   ~4.4 GB total
                         total ~151 GB/day
```

**Compression 6.4 : 1** (measured: 29.43 GB raw → 4.57 GB on disk).
→ ~23 GB/day on disk, 14-day retention ≈ **330 GB**. G: has 1 459 GB. **Capacity is not a constraint.**

### Backup topology

| When | Type | Where | `copy_only` |
|---|---|---|---|
| every 15 min, 24/7 | LOG | `G:\Backup\NAV-LIVE\NAV-LIVE` | — |
| 01:30 daily | DIFF | `G:\Backup\NAV-LIVE\NAV-LIVE` | 0 |
| 02:00 Tue–Sat | FULL | `G:\Backup\NAV-TEST-USERS` | **0 ← the trap** |
| ~01:30 Sunday | FULL | `G:\Backup\NAV-LIVE\NAV-LIVE` | 0 |
| 18:43 daily | FULL | VSS snapshot (GUID) | 1 ✅ |

Cleanup of old backups lives **inside the SSIS package of subplan `Tlog`** and runs every 15 minutes alongside the backup. Disabling the job also stops the cleanup.

---

## 5. Corrections to earlier conclusions

Do not carry older statements over from the documents without checking this list.

| Previously | Reality |
|---|---|
| "Index maintenance doesn't run, `Rebuildindex` is disabled" | **It does run** — as step 1 of job `1xdenne`. The disabled plan is its predecessor. |
| "Variant A may fill the disk, 3–5 TB" | **Wrong.** Compression 6.4:1 → 14 days ≈ 330 GB. |
| "Raising the log cap is merely a delay" | True while backups didn't run overnight. **Now it is the correct buffer.** |
| "Shortening the interval to 5 minutes lowers RPO" | It does, but **it does not help the nightly peak** — the log is held by a long transaction, not by backup frequency. |
| "`Tlog2` is redundant" | It is not — it covers Saturday. It becomes redundant only after `freq_interval = 127`. |
| "The incident lasted 74 seconds" | An export artefact. ITDashboard exports **at most 300 rows** (verified on three batches). |

---

## 6. Incidents

**2026-07-23** — error 9002, diagnosed, fix proposed, **never deployed** (schedule `date_modified` remained 2025-01-10).

**2026-08-10 ~05:33** — error 9002, ran for hours, last record 05:34:32 when the morning backup completed. True extent unknown (export cap).

**2026-08-11 05:12:18–05:15:35** — error 9002 **again, but only 3 minutes**. Log backups ran correctly all night. Cause: `1xdenne` (04:00, 1 h 46 min) holds a long index-rebuild transaction, so the log cannot be released. The 05:31 backup then carried 29.43 GB at once.

---

## 7. Outside the backup scope, but worth attention

- **`Emergency_Cache_Warming`** fails continuously, dozens of times a day, for months. PLE threshold raised from 300 to 3000. Runs 6–10 min on a 5-minute schedule → overlaps itself. Notifies nobody. A candidate for disabling.
- **`00_Warming Script pro NAV-LIVE`** runs 36–49 minutes and starts every 40 minutes → effectively continuously.
- **`000_kontrola_vykonu_SQL`** every 5 minutes, ~3 minutes each → also near-continuous.
- Three jobs constantly reading data to measure or "warm" what those same jobs evict from cache. Likely related to the NAV FlowField issue (`VarChar` vs `Variant` → row-by-row evaluation).
- **`notifikace2@axima.cz`** receives "always" mail from seven jobs → alert fatigue.
- **Event 1511** — repeated interactive logons to the production SQL host with a temporary profile (2026-08-10 16:41–17:12).
- **ITDashboard export capped at 300 rows** — belongs in the ITDashboard project backlog, not here.

---

## 8. How we work

- Production changes are performed by the **operator**, not the agent. Scripts are delivered ready to paste into SSMS.
- Every change must be **reversible** and carry its rollback command.
- **Never edit maintenance plans by script** — saving the plan in the designer overwrites the schedule from its own definition.
- After every change, **verify from data**, not from the absence of an error dialog (the GUI change on the morning of 2026-08-10 silently failed to save).
- Commit as `mtrnka@axima.cz` (local `git config`).
