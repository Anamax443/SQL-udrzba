# SQL-udrzba

Maintenance and operations of AXIMA's SQL Servers — analyses, proposals, opposition reviews and operational scripts.

> Czech original: [README.md](README.md) · The Czech version is authoritative.

> **This repository is private.** It contains server names, database names, service accounts, backup paths and e-mail addresses. Never switch it to public.

---

## Current topic: NAV-LIVE backup

> **Current state and next step: [HANDOFF.en.md](HANDOFF.en.md)** — read this first.

**The document we work by:** [`docs/NAV-LIVE-backup-FINAL.en.html`](docs/NAV-LIVE-backup-FINAL.en.html) — consolidated specification, self-contained, no cross-references.

### Status

| | |
|---|---|
| Database | NAV-LIVE (Business Central 14), 800 GB, 57 users |
| Server | B-S-W-SQL-01, SQL Server 2017 Enterprise (14.0.2120.1) |
| Original problem | Transaction log backups ran only 05:30–15:46 → overnight RPO up to 13 h 44 min |
| **Fixed 2026-08-10** | window widened to **00:00–23:59**, verified; RPO Sun–Fri = **15 minutes** |
| **Remaining** | Saturday (`freq_interval` 63 → 127) · log `MAXSIZE` buffer · index maintenance in job `1xdenne` |
| 9002 incidents | Jul 23 · Aug 10 (hours) · Aug 11 (**3 minutes** — residual effect of nightly index rebuilds) |

### Layout

```
docs/
  NAV-LIVE-zalohovani-FINAL.html    ← binding specification (CS)
  NAV-LIVE-backup-FINAL.en.html     ← same document (EN)
  2026-08-10-navrh-v1.md            first draft, superseded
  2026-08-10-navrh-v2.md            technical basis — theory, runbooks, verification scripts
  oponentury/
    2026-08-10-oponentura-1.md                 against proposal v2, 15 findings (O1–O15)
    2026-08-10-oponentura-2-protinavrh-v3.md   against external counter-proposal, 6 findings (N1–N6)
    externi/                                    third-party inputs, not peer-reviewed
sql/
  NAV-LIVE-tlog-nasazeni.sql                 11 parts, staged rollout, every step reversible
  1xdenne-krok1-udrzba-indexu-navrh.sql      proposed replacement for index maintenance
evidence/
  itdashboard-events-*.csv                   Event Log exports from the incidents
```

### Established by measurement (2026-08-10 / 08-11)

- The log file is **97.7 GB and already at its `max_size`** — it cannot grow further
- **~151 GB of log per day**, of which **140 GB between 04:00 and 06:00** (93 %)
- Source: job **`1xdenne`** (starts 04:00, runs 1 h 46 min), step 1 = index maintenance
- **Backup compression 6.4 : 1** → ~23 GB/day on disk, 14-day retention ≈ 330 GB. G: has 1 459 GB free — **capacity is not a constraint**
- The daily 02:00 full backup to `G:\Backup\NAV-TEST-USERS` has **`is_copy_only = 0`** → it shifts the differential base every day
- The VM **is** backed up — VSS snapshot daily at 18:43, correctly `COPY_ONLY`
- `BackupMaintenancePlan.Tlog`, `.Tlog2` and `Backup_NAV-LIVE_for_TEST_Optimized` have notification set to **NEVER** — a failed log backup notifies nobody
- `notifikace2@axima.cz` receives "always" mail from seven jobs → alert fatigue
- Cleanup of old backups lives **inside the subplan's SSIS package** → disabling the backup job also disables the cleanup
- Enterprise Edition, Instant File Initialization enabled, VLF count 435, G: 1 459 GB free
- The ITDashboard export is **capped at 300 rows** → nobody has ever seen the true extent of an incident

### Open questions

1. Where does the VSS backup store its data, and is it off this server?
2. What is the retention of `G:\Backup\NAV-TEST-USERS`, on which the differential chain depends?
3. Which job produces the daily 02:00 full? (`NAV-LIVE_to_NAV-TEST-USERS` is disabled)
4. Is G: a different physical array than E: and F:?
5. **What RPO and RTO does the business actually need?** — the one question IT cannot answer

---

## Working rules

- **Production changes are made by the operator**, not by an automation. Scripts are delivered ready to paste into SSMS.
- **Every step must be reversible** and carry its rollback command in `sql/`.
- **Never edit maintenance plans by script.** Saving a plan in the designer overwrites the schedule from its own definition — the likely reason the 2026-07-23 fix never took effect. New tasks go in as standalone T-SQL jobs, which are readable and versionable.
- **Verify from data**, not from the absence of an error dialog (a GUI change on the morning of 2026-08-10 silently failed to save).
- **Never commit** passwords, connection strings containing credentials, `.bak` files, or exports containing personal data.

## Candidates to add

The following material on the same system is not in the repository yet because its content has not been reviewed for credentials:

- `BC_INDEX_ANALYSIS-BSWNAV01_NAV-LIVE.txt` — index analysis
- `NAV-LIVE_MAXDOP_Change_4to8_WithMeasurement.sql` — MAXDOP change with measurement
- `Hodnoceni_NAV-LIVE_SQL_2025-10-31.pdf` — SQL assessment from October 2025
- `Restore-NAV-TEST.ps1` — test database restore and demilitarisation
