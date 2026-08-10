# Oponentura 2 — protinávrh v3 (zálohování NAV-LIVE)

> Datum: 2026-08-10
> Předmět: `Protinávrh: Přepracovaná strategie zálohování a obnovy NAV-LIVE (v3)` (HTML, externí zpracovatel)
> Navazuje na: `NAV-LIVE-zalohovani-navrh-v2.md` → `2026-08-10-oponentura-zalohovani-NAV-LIVE.md` → **v3** → *tento dokument*
> Cílový systém: NAV-LIVE (BC 14), B-S-W-SQL-01, SQL Server 2017
> Stav systému v době psaní: **Fáze 1 stále nenasazena, `Tlog` běží 05:30–15:46**

---

## Obsah

0. [Metoda a návaznost](#0-metoda-a-návaznost)
1. [Verdikt](#1-verdikt)
2. [Co v3 vyřešil správně](#2-co-v3-vyřešil-správně)
3. [Nové vady zavedené v3](#3-nové-vady-zavedené-v3)
4. [Body z oponentury 1, které v3 neuzavřel](#4-body-z-oponentury-1-které-v3-neuzavřel)
5. [Log shipping — co v3 zamlčuje](#5-log-shipping--co-v3-zamlčuje)
6. [Kritika RACI a podpisové doložky](#6-kritika-raci-a-podpisové-doložky)
7. [Status dokumentů — v3 nesmí nahradit v2](#7-status-dokumentů--v3-nesmí-nahradit-v2)
8. [Opravená Fáze 0](#8-opravená-fáze-0)
9. [Konsolidovaný cílový stav](#9-konsolidovaný-cílový-stav)
10. [Verdikt a podmínky přijetí](#10-verdikt-a-podmínky-přijetí)
- [Příloha A — opravený job](#příloha-a--opravený-job-zálohy-logu)
- [Příloha B — mapa nálezů](#příloha-b--mapa-nálezů-oponentura-1--v3)
- [Příloha C — otevřené otázky](#příloha-c--otevřené-otázky-napříč-všemi-koly)
- [Příloha D — co udělat dnes](#příloha-d--co-udělat-dnes)

---

## 0. Metoda a návaznost

### 0.1 Kde jsme v procesu

```
v1  ──►  v2  ──►  Oponentura 1  ──►  v3 (protinávrh)  ──►  Oponentura 2 (tento dokument)
                        │                   │
                   15 nálezů           přijal většinu,
                   O1–O15              zavedl 4 nové vady
```

Tato oponentura má **jiný charakter** než ta první. První oponovala vlastní návrh a hledala hlavně chybějící důkazy. Tato oponuje cizí dokument a hledá především **technické vady v konkrétních příkazech** — protože v3 přešel od úvah k příkazům, které se budou pouštět na produkci.

### 0.2 Proč je to nutné

v3 obsahuje T-SQL, které je určeno k okamžitému nasazení („Fáze 0, dnešek, do 1 hodiny"). U dokumentu, který se má **podepsat a stát závazným**, je každý řádek kódu potenciálně produkční změna.

Přezkum kódu je proto přísnější než přezkum záměru. **Záměr v3 je správný. Kód není.**

### 0.3 Klasifikace

| Značka | Význam |
|---|---|
| 🔴 **BLOKUJÍCÍ** | Nelze nasadit — způsobí škodu |
| 🟠 **ZÁVAŽNÉ** | Nasadit lze, ale s doplněním |
| 🟡 **STŘEDNÍ** | Projeví se později |
| ⚪ **DROBNÉ** | Přesnost, forma |

---

## 1. Verdikt

> **ZÁMĚR PŘIJAT, PROVEDENÍ ZAMÍTNUTO.**
>
> Strukturu a pořadí kroků v3 doporučuji převzít.
> **Kód ve Fázi 0 nesmí být spuštěn v předložené podobě** — způsobil by rozštěpení řetězu záloh a tichý zápis poškozených dat.

| Oblast v3 | Verdikt |
|---|---|
| Fázování *Změřit → Zabezpečit → Rozšířit* | ✅ **PŘIJATO** — správná reakce na oponenturu 1 |
| Vyjmutí log záloh do samostatného jobu | ✅ **PŘIJATO** jako princip |
| Konkrétní `BACKUP LOG` příkaz | 🔴 **ZAMÍTNUTO** — dvě vážné vady |
| Krok 0.2 bez vypnutí starých jobů | 🔴 **ZAMÍTNUTO** — rozštěpí řetěz |
| Fáze 2: denní full + týdenní diff | 🟠 **VRÁCENO** — logicky nekonzistentní |
| Vypuštění `COPY_ONLY` | 🟠 **VRÁCENO** — past zůstává otevřená |
| Akceptační protokol obnovy | ✅ **PŘIJATO** — nejlepší část v3 |
| RACI | 🟡 **ČÁSTEČNĚ** — funkce místo jmen |
| Log shipping jako studie | ✅ **PŘIJATO**, ale srovnávací tabulka je zavádějící |
| „Nahrazuje v2" | 🟠 **ZAMÍTNUTO** — viz kap. 7 |

---

## 2. Co v3 vyřešil správně

Fér ocenění dřív, než začne kritika. v3 přijal většinu nálezů oponentury 1 a přeložil je do plánu:

| Nález oponentury 1 | Jak to v3 řeší | Hodnocení |
|---|---|---|
| O2 — varianta A může zaplnit disk | Zmrazil Fázi 2 do naměření dat | ✅ přesně tak |
| O4 — změna se může vrátit | Samostatný job mimo maintenance plán | ✅ správný princip |
| O7 — chybí vlastník | RACI matice | 🟡 částečně, viz kap. 6 |
| O13 — chybí definice „hotovo" | Akceptační protokol obnovy | ✅ **nejlepší část dokumentu** |
| 5.1 — log shipping nezvážen | Zařazen jako Fáze 3 (studie) | ✅ zařazeno |
| 5.3 — zálohuje se VM? | Audit hypervizoru ve Fázi 1 | ✅ zařazeno |
| 4.1 — oddělit svazky full/log | Svazek A a Svazek B | ✅ zařazeno |
| O9 — obnova ze stovek souborů | „Generátor obnovy" ve Fázi 2 | ✅ zařazeno |
| O1/O3 — neověřené předpoklady | Krok 0.1 diagnostika | ✅ zařazeno |

**Akceptační protokol v kapitole 3 v3 je věc, kterou v2 nemá a mít měl.** Sedmibodový seznam od „databáze je ONLINE" po „testovací zaúčtování prodejní faktury proběhlo bez chyby číselných řad" je přesně ta definice hotového, která v obou předchozích dokumentech chyběla. Doporučuji ho převzít beze změny.

---

## 3. Nové vady zavedené v3

### 3.1 🔴 N1 — Krok 0.2 rozštěpí řetěz záloh

**Co v3 předepisuje:**

> Vytvoření samostatného jobu `BC_Backup_TLog_Continuous` plánovaného na 24/7 každých 15 minut.

**Co v3 neříká:** že se mají zároveň **vypnout** `BackupMaintenancePlan.Tlog` a `BackupMaintenancePlan.Tlog2`.

**Co se stane, když se to udělá podle textu:**

```
05:30–15:46   Tlog  → zálohuje log do stávajícího umístění
00:00–23:59   BC_Backup_TLog_Continuous → zálohuje log do G:\Backup\NAV-LIVE\TLog\
sobota        Tlog2 → zálohuje log do třetího umístění
```

Každá záloha logu **ořízne log**. Transakce tedy skončí v tom souboru, jehož job běžel jako první — a v ostatních chybí. Ani jedno umístění nemá kompletní řadu.

**Důsledek pro obnovu:** je nutné mít **všechny tři sady** a přehrát je v přesném časovém pořadí, prokládaně. To je proveditelné, ale:

| Riziko | Následek |
|---|---|
| Maintenance Cleanup maže jednu sadu podle stáří nezávisle na ostatních | díra v řetězu, za kterou se nedá obnovit |
| Kdokoli později vypne „ten starý job" | díra v řetězu v okamžiku vypnutí |
| Generátor obnovy (Fáze 2) musí umět tři umístění | zbytečná složitost |
| Monitoring „stáří poslední zálohy logu" bude zelený i když nový job padá | **slepé místo detekce** |

Poslední řádek je zákeřný a stojí za rozvedení. Krok 0.3 zavádí alert „poslední úspěšná záloha logu starší než 60 minut". Ten alert se dotazuje `msdb.dbo.backupset`, kde jsou zálohy **ze všech jobů dohromady**. Když nový job selže, ale starý přes den běží, **alert zůstane zelený** a nikdo se nedozví, že nová větev nefunguje.

**Oprava:** vypnutí starých jobů musí být **součástí téhož kroku**, ne samostatný úkol na později. A vypnutí musí následovat až po ověření, že nový job doběhl aspoň jednou úspěšně. Postup je v příloze A.

---

### 3.2 🔴 N2 — Příkaz `BACKUP LOG` má dvě vážné vady

```sql
BACKUP LOG [NAV-LIVE] 
TO DISK = N'G:\Backup\NAV-LIVE\TLog\NAV-LIVE_Log_Current.trn' 
WITH COMPRESSION, CHECKSUM, CONTINUE_AFTER_ERROR;
```

#### a) Pevné jméno souboru

Bez `INIT` se každá záloha **připojuje do téže media sady**. Za den 96 záloh, za 14 dní **1 344 záložních sad v jediném souboru.**

Co to způsobí:

| Problém | Detail |
|---|---|
| Obnova vyžaduje `WITH FILE = n` | čísla je nutné dohledat přes `RESTORE HEADERONLY` nad rostoucím souborem |
| Retence nefunguje | Maintenance Cleanup maže soubory podle stáří — tenhle soubor je vždycky „nový" |
| Jediný bod selhání | poškození nebo ztráta souboru = **ztráta celého řetězu naráz** |
| Soubor roste bez omezení | při ~30 GB logu denně je za týden neúnosný |

A hrozí ještě horší „oprava": někdo si všimne, že soubor roste, a přidá `INIT`. Tím **každá záloha přepíše všechny předchozí** a řetěz je zničený okamžitě a tiše.

> **Správně:** jeden soubor na jednu zálohu, s časovým razítkem v názvu.

#### b) `CONTINUE_AFTER_ERROR` v pravidelné záloze

Tento přepínač říká *„pokračuj v záloze, i když narazíš na poškozená data"*. Jeho jediné legitimní použití je **tail-log záloha z rozbité databáze**, kdy je poškozená záloha lepší než žádná.

V pravidelném jobu znamená:

- poškození dat se **tiše zazálohuje**
- job **nahlásí úspěch**
- poškození se šíří do všech dalších záloh, dokud se retence nepřetočí
- pozná se to až při obnově

**A přímo si odporuje se sousedním `CHECKSUM`:**

| Přepínač | Co dělá |
|---|---|
| `CHECKSUM` | ověřuje kontrolní součty stránek a **při chybě zálohu ukončí** |
| `CONTINUE_AFTER_ERROR` | při chybě **pokračuje dál** |

Napsat je vedle sebe znamená zapnout detekci a v témže dechu jí zakázat reagovat. Je to horší než nemít ani jedno — protože `CHECKSUM` v seznamu budí dojem, že integrita je hlídaná.

> **Správně:** `WITH COMPRESSION, CHECKSUM` a nic víc. `CONTINUE_AFTER_ERROR` patří výhradně do havarijního postupu v runbooku.

---

### 3.3 🟠 N3 — Denní full + týdenní diff je logicky obrácené

Fáze 2 v3:

> **Svazek A (Full & Diff DB):** Denní FULL / Týdenní DIFF

Diferenciální záloha obsahuje změny **od poslední full zálohy**. Když je full denní, obsahuje diff změny za jeden den. Týdenní diff tedy:

- neobsahuje týden změn, ale změny od poslední noci
- neposkytuje žádnou zkratku při obnově (full je vždy novější nebo stejně stará)
- je čistá režie navíc

Smysl dávají jen dvě kombinace:

| Kombinace | Kdy zvolit |
|---|---|
| **Týdenní full + denní diff + log** | úspora místa, delší řetěz obnovy |
| **Denní full + log, bez diffů** | více místa, nejkratší řetěz, nejjednodušší obnova |

Volba mezi nimi závisí na naměřené kapacitě — což v3 správně odkládá. **Ale nemá předepisovat kombinaci, která nedává smysl ani v jednom scénáři.**

---

### 3.4 🟠 N4 — `COPY_ONLY` z dokumentu zmizelo

Oponentura 1 vedla `COPY_ONLY` jako otevřené riziko (T14, nález O3). v3:

- v Kroku 0.1 správně ověřuje **existenci** diff záloh
- ve Fázi 2 **plánuje diff zálohy**
- `COPY_ONLY` **nezmiňuje ani jednou**

Tím zůstává past otevřená a navíc už o ní dokument nemluví, takže při realizaci na ni nikdo nenarazí:

```
denní full pro NAV-TEST (bez COPY_ONLY)
   → posune diff base
      → diff zálohy z plánu se počítají od ní
         → soubor se druhý den přepíše
            → diff zálohy nepoužitelné
```

Pokud Fáze 2 skončí u varianty **bez diffů**, riziko zmizí samo. Pokud u varianty **s diffy**, musí být `COPY_ONLY` explicitní podmínkou. v3 neurčuje ani jedno.

---

### 3.5 🟡 N5 — Fáze 0 a Fáze 2 si odporují v umístění

Fáze 0 zapisuje log zálohy na **`G:\Backup\NAV-LIVE\TLog\`**.
Fáze 2 zavádí **Svazek B** zvlášť pro transakční log, oddělený od full záloh na Svazku A.

Pokud je G: ten svazek s full zálohami (což název `G:\Backup\` naznačuje), pak Fáze 0 zakládá přesně ten stav, který Fáze 2 ruší — a přesun znamená, že řetěz bude rozložený mezi dvě cesty.

To není fatální (soubory zůstávají použitelné), ale je to zbytečné. **Doporučení:** rozhodnout cílové umístění logu **před** Fází 0, i kdyby to mělo znamenat založit adresář na jiném svazku hned. Přesouvat běžící řetěz je zbytečné riziko.

---

### 3.6 🟡 N6 — Alert ve Fázi 0 předpokládá funkční Database Mail

Krok 0.3: *„E-mailový alert při absenci úspěšné zálohy logu déle než 60 minut."*

Aby to fungovalo, musí být na instanci nastaveno:

- Database Mail profil a SMTP účet
- SQL Agent operátor s platnou adresou
- SQL Agent nakonfigurovaný na použití toho profilu (a **restartovaný**, jinak se nastavení neprojeví)

Nic z toho není ověřené. Na serveru, kde je vypnutý jediný existující hlídač (`BC_Jobs_Backup_Monitor_Simple`), je pravděpodobné, že alertování není v provozu vůbec.

> **Krok 0.3 tedy není 25 minut práce.** Buď je Database Mail připravený a je to 25 minut, nebo není a je to půl dne včetně otevření SMTP na firewallu.

**Doporučení:** zařadit ověření Database Mail jako Krok 0.0 a mít připravenou náhradu — třeba zápis do tabulky, kterou čte ITDashboard, který e-maily už umí odesílat.

---

## 4. Body z oponentury 1, které v3 neuzavřel

| # | Nález | Stav ve v3 |
|---|---|---|
| O1 | Strop logu neověřen | ✅ Krok 0.1 |
| O2 | Varianta A může zaplnit disk | ✅ zmrazeno |
| O3 | Existují diff zálohy? | ✅ Krok 0.1 |
| O4 | Změna se může vrátit | ✅ samostatný job |
| O5 | „100 GB za noc" je odhad | ✅ Fáze 1 měření |
| O6 | Obnova aplikace, ne jen DB | ✅ akceptační protokol |
| O7 | Chybí vlastník | 🟡 funkce, ne jména |
| **O8** | **Šifrování a přístup k zálohám** | 🟠 jen zmínka „GDPR" ve Fázi 1, žádné opatření |
| O9 | Obnova ze stovek souborů | ✅ generátor ve Fázi 2 |
| O10 | Falešná přesnost čísel | ⚪ v3 čísla nepřebírá, neutrální |
| **O11** | **Bus factor 1** | ❌ **neřešeno** |
| O12 | Alternativy zamítnuty mlčky | ✅ log shipping zařazen |
| O13 | Definice „hotovo" | ✅ akceptační protokol |
| **O14** | **`DBCC CHECKDB`** | 🟠 jen v akceptačním protokolu, ne jako pravidelná úloha |
| **O15** | **Verzování a uložení dokumentu** | ❌ **neřešeno** — dokument existuje jako HTML v Downloads |

### Rozvedení tří neuzavřených

**O8 — bezpečnost záloh.** v3 to odbývá formulací *„restrikce přístupu k zálohám a řešení šifrování z pohledu GDPR"* jako jednou odrážkou uvnitř Fáze 1. Přitom jde o to, že `.bak` NAV-LIVE je kompletní firemní databáze v jednom souboru a `Restore-NAV-TEST.ps1` z ní denně vyrábí kopii na testovacím serveru. Zaslouží si to vlastní kapitolu s konkrétním opatřením (`BACKUP ... WITH ENCRYPTION`, správa certifikátu, ACL), ne odrážku.

**O11 — bus factor.** v3 zavádí RACI, což je krok správným směrem, ale znalost tím nepřevede. Runbook obnovy použitelný pro někoho, kdo systém nezná, pořád neexistuje ani v jednom dokumentu.

**O15 — kde ten dokument žije.** v3 obsahuje podpisovou doložku a prohlašuje se za závazný podklad. Existuje jako HTML soubor ve složce Downloads jednoho počítače. **Závazný dokument o zálohování, který sám není nikde zálohovaný.**

---

## 5. Log shipping — co v3 zamlčuje

Srovnávací tabulka ve Fázi 3 v3 staví proti sobě *„Pouze zálohy na disk"* a *„Log Shipping"*, jako by to byly alternativy. **Nejsou.** Log shipping zálohy **nenahrazuje** — je na nich postavený.

### 5.1 Co log shipping neřeší

| Hrozba | Zálohy | Log shipping |
|---|---|---|
| Selhání disku / serveru | ✅ | ✅ |
| Selhání celé lokality | ✅ (offsite kopie) | ⚠ jen když je sekundár jinde |
| **Chyba uživatele** | ✅ obnova k času | ❌ **replikuje ji během minut** |
| **Ransomware** | ✅ neměnná kopie | ❌ **replikuje šifrování** |
| **Poškození dat (bit rot)** | ✅ starší záloha | ❌ **replikuje poškození** |
| Potřeba dat z minulého měsíce | ✅ | ❌ sekundár drží jen aktuální stav |

Tři červené řádky jsou podstatné. Log shipping poslušně přehraje i příkaz, kterým někdo smazal půlku zákazníků. Zpožděná obnova (`restore delay`, typicky 15–60 minut) dává úzké okno na zastavení, ale je to reakční doba v řádu minut — v praxi to znamená, že si někdo musí chyby všimnout okamžitě.

> **Log shipping je nástroj pro RTO a pro havárii hardwaru. Není to záloha.**

Doporučuji tabulku v3 přepsat tak, aby to bylo zřejmé — jinak hrozí, že se z ní vyvodí „když nasadíme log shipping, zálohy můžeme zjednodušit". To by byl vážný krok zpět.

### 5.2 RTO 15–30 minut je optimistické

v3 uvádí *„15–30 minut (přepnutí na sekundár)"*. Co se v té době musí stihnout:

1. dohrát zbývající log zálohy na sekundáru
2. převést databázi z `STANDBY` / `NORECOVERY` do `RECOVERY`
3. vyřešit osiřelé loginy (`ALTER USER ... WITH LOGIN`)
4. přesměrovat BC service tier na nový server a restartovat
5. ověřit akceptačním protokolem z kapitoly 3 v3

Bez nacvičeného a zdokumentovaného postupu je reálný odhad **spíš hodina**. S nacvičeným postupem je 15–30 minut dosažitelných — ale ta podmínka musí být v tabulce.

### 5.3 Licence

Pasivní sekundár nevyžaduje licenci **pouze** při platném Software Assurance. Bez SA je to plná licence SQL Serveru. Studie proveditelnosti musí začít u téhle otázky, protože rozhoduje o tom, jestli je řeč o desítkách tisíc nebo o statisících.

---

## 6. Kritika RACI a podpisové doložky

### 6.1 Funkce nejsou jména

Oponentura 1 (O7) žádala vlastníka. v3 dodal matici s funkcemi: *SQL Administrator, Vedoucí IT, Partner BC, BC Specialist, Správce Infra, Finanční ředitel, IT Service Desk, Vývojový tým.*

Osm rolí. Otázka zní, **kolik z nich v této firmě existuje jako samostatný člověk.** Pokud většinu z nich zastává tentýž člověk, matice nic nemění — jen to zakrývá.

> **Doporučení:** doplnit ke každé roli jméno. Kde vyjde totéž jméno na *Responsible* i *Accountable*, je to samo o sobě nález (nikdo nekontroluje toho, kdo to dělá) a má se zaznamenat, ne skrýt.

### 6.2 „Accountable: Finanční ředitel" u schválení varianty DB

Volba mezi denní a týdenní full zálohou je technické rozhodnutí s cenovkou. Finanční ředitel má schvalovat **rozpočet**, ne architekturu záloh.

Co by naopak schvalovat měl a v matici to není: **kolik smí firma ztratit** — tedy cílové RPO a RTO. To je obchodní rozhodnutí, ne technické, a v žádném z dokumentů zatím nikdo nepoložil.

### 6.3 Podpis pod dokument, jehož polovina závisí na neznámých datech

v3 končí větou:

> „stává se závazným podkladem pro realizaci po podpisu odpovědných osob"

Fáze 2 přitom výslovně čeká na data, která zatím nikdo nezměřil. Podepsat dnes celý dokument znamená podepsat i rozhodnutí, jehož podklady neexistují.

> **Doporučení:** podpis rozdělit. Fáze 0 a 1 podepsat teď — jsou konkrétní, levné a vratné. Fáze 2 a 3 nechat jako **návrh k rozhodnutí** s vlastním podpisem po vyhodnocení měření.

---

## 7. Status dokumentů — v3 nesmí nahradit v2

v3 prohlašuje, že nahrazuje `NAV-LIVE-zalohovani-navrh-v2.md`. To by znamenalo zahodit:

| Obsah v2 | Je ve v3? |
|---|---|
| Vysvětlení, proč je log backup jediný mechanismus uvolnění logu | ❌ |
| Model hrozeb | ❌ |
| Postupy obnovy včetně `STOPAT` a `STANDBY` | ❌ |
| Tail-log backup | ❌ |
| VLF a proč byl `shrink_log` škodlivý | ❌ |
| Instant File Initialization a vliv na RTO | ❌ |
| Retenční pravidlo „dva plné cykly" | ❌ |
| 3-2-1 a neměnná kopie | ❌ |
| Ověřovací skripty A1–A7 | ❌ |
| Slovníček | ❌ |
| Původní logika zadání (data od lidí v pracovní době) | ❌ |

v3 je **plánovací a rozhodovací** dokument: fáze, odpovědnosti, akceptace, podpisy. v2 je **technický**: proč, jak, čím ověřit.

> **Doporučená struktura:**
>
> | Dokument | Role | Publikum |
> |---|---|---|
> | v3 (upravený dle této oponentury) | co, kdy, kdo | vedení, schvalovatelé |
> | v2 | proč a jak | ten, kdo to provádí |
> | Oponentury 1 a 2 | co se zvažovalo a zamítlo | budoucí revize |
> | Runbook obnovy | krok za krokem při havárii | kdokoli ve službě |

Poslední řádek zatím neexistuje ani v jednom dokumentu a je z nich nejdůležitější.

---

## 8. Opravená Fáze 0

Kroky přeuspořádané tak, aby žádný z nich nezanechal systém v horším stavu než na začátku. Plný skript je v [příloze A](#příloha-a--opravený-job-zálohy-logu).

| Krok | Co | Riziko | Vratnost |
|---|---|---|---|
| **0.0** | Ověřit Database Mail a operátora | nulové | — |
| **0.1** | Diagnostika: disky, `max_size`, autogrow, existence diff záloh, edice | nulové (čtení) | — |
| **0.2** | Rozhodnout cílové umístění log záloh **před** založením jobu | nulové | — |
| **0.3** | Založit job `BC_Backup_TLog_Continuous` — **vypnutý** | nulové | smazat |
| **0.4** | Spustit ručně jednou, ověřit soubor a záznam v `backupset` | nízké | — |
| **0.5** | Zapnout schedule 24/7 á 15 min | nízké | vypnout |
| **0.6** | Počkat na dva úspěšné automatické běhy | — | — |
| **0.7** | **Teprve teď** vypnout `Tlog` a `Tlog2` | nízké | zapnout |
| **0.8** | Alert na stáří poslední zálohy logu > 60 min | nulové | — |
| **0.9** | Ověřit `log_reuse_wait_desc = NOTHING` | nulové | — |

Rozdíly proti v3:

1. **0.7 existuje** — v3 vypnutí starých jobů neobsahuje vůbec (nález N1)
2. **0.7 je až po 0.6** — nikdy nenastane okamžik bez funkčních záloh logu
3. **0.4 před 0.5** — job se ověří ručně, než se pustí automaticky
4. **0.0 a 0.2 předřazeny** — aby se nezakládalo něco, co se bude hned přesouvat

---

## 9. Konsolidovaný cílový stav

Sjednocení v2, oponentury 1, v3 a této oponentury do jedné tabulky. **Toto je to, co doporučuji podepsat** — jako cíl, jehož parametry se doplní po měření.

### 9.1 Zálohy

| Prvek | Cíl | Zdroj rozhodnutí |
|---|---|---|
| Log zálohy | á 15 min, **24/7, všech 7 dní**, samostatný job | v2 + v3 |
| Umístění log záloh | vlastní svazek, oddělený od full | v3 + opon. 1 |
| Jméno souboru | **jeden soubor na zálohu, s časovým razítkem** | **opon. 2 (N2a)** |
| Přepínače | `COMPRESSION, CHECKSUM` — **bez `CONTINUE_AFTER_ERROR`** | **opon. 2 (N2b)** |
| Full zálohy | denní **nebo** týdenní — dle naměřené kapacity | v3 |
| Diff zálohy | **denní, pouze při týdenní full** — jinak žádné | **opon. 2 (N3)** |
| Full mimo plán (pro test) | **vždy `COPY_ONLY`**, pokud existují diffy | **opon. 2 (N4)** |
| Retence | ≥ 2 plné cykly | v2 |
| Kopie mimo server | povinná | v2 |
| Neměnná / offline kopie | povinná (ransomware) | v2 |
| Šifrování záloh | k rozhodnutí, ne k odbytí odrážkou | opon. 1 (O8) |

### 9.2 Provoz

| Prvek | Cíl |
|---|---|
| Monitoring stáří log zálohy | > 60 min → alert |
| Monitoring volného místa | < 20 % → alert |
| Monitoring `log_reuse_wait_desc` | ≠ `NOTHING` déle než 60 min → alert |
| Monitoring změny schedule | `date_modified` se změnil → alert |
| `DBCC CHECKDB` | týdně nad obnovenou `NAV-TEST` |
| Test obnovy k času | měsíčně, se `STOPAT` |
| Akceptační protokol | 7 bodů dle v3 kap. 3 |
| Runbook obnovy | **chybí — vytvořit** |

### 9.3 Co zůstává nerozhodnuto

Tyto položky **nelze** uzavřít bez dat nebo bez rozhodnutí firmy:

1. denní vs. týdenní full → čeká na kapacitu disků
2. cílové RPO a RTO → **čeká na rozhodnutí vedení, ne IT**
3. log shipping ano/ne → čeká na licenční situaci a cenu serveru
4. šifrování záloh → čeká na posouzení rizika
5. kde budou žít dokumenty → čeká na rozhodnutí (doporučení: git)

---

## 10. Verdikt a podmínky přijetí

### 10.1 Rozhodnutí

> **v3 PŘIJAT S VÝHRADAMI.**
> Struktura, fázování a akceptační protokol se přebírají.
> Kód Fáze 0 se nahrazuje verzí z přílohy A.
> Prohlášení „nahrazuje v2" se ruší.

### 10.2 Podmínky

| # | Podmínka | Nález |
|---|---|---|
| 1 | Vypnutí starých log jobů zařadit do Fáze 0 jako krok 0.7 | N1 |
| 2 | Jméno souboru s časovým razítkem | N2a |
| 3 | Odstranit `CONTINUE_AFTER_ERROR` | N2b |
| 4 | Opravit kombinaci full/diff | N3 |
| 5 | Vrátit `COPY_ONLY` jako podmínku, pokud budou diffy | N4 |
| 6 | Rozhodnout umístění log záloh před Fází 0 | N5 |
| 7 | Ověřit Database Mail před slibem alertu | N6 |
| 8 | Doplnit ke každé roli v RACI jméno | 6.1 |
| 9 | Rozdělit podpis: Fáze 0–1 teď, Fáze 2–3 po měření | 6.3 |
| 10 | Zrušit prohlášení o nahrazení v2 | kap. 7 |
| 11 | Přepsat srovnávací tabulku log shippingu | kap. 5.1 |
| 12 | Uložit všechny dokumenty do gitu | O15 |

### 10.3 Co je pořád nejdůležitější

Tři kola dokumentů, dva protinávrhy, dvě oponentury. Za tu dobu se změnila jedna věc na produkci: **vypnul se `shrink_log`.**

`BackupMaintenancePlan.Tlog` má pořád okno 05:30–15:46. Dnešní noc proběhne stejně jako ta minulá a stejně jako ta z 23. července.

> **Kvalita dokumentace roste rychleji než bezpečnost systému.** To je samo o sobě nález a je nejzávažnější v celé této oponentuře.

Příloha D obsahuje tři kroky na dnešek, které nevyžadují žádné rozhodnutí, žádné měření a žádný podpis.

---

## Příloha A — opravený job zálohy logu

### A1. Vytvoření jobu (vypnutého)

```sql
USE [msdb];
GO

EXEC msdb.dbo.sp_add_job
     @job_name = N'BC_Backup_TLog_Continuous',
     @enabled = 0,                       -- zamerne vypnuty, zapneme az po rucnim testu
     @description = N'Zaloha transakcniho logu NAV-LIVE, 24/7. Mimo maintenance plan zamerne.',
     @category_name = N'Database Maintenance';
GO
```

### A2. Krok zálohy — opravená verze

```sql
EXEC msdb.dbo.sp_add_jobstep
     @job_name   = N'BC_Backup_TLog_Continuous',
     @step_name  = N'Backup TLog',
     @subsystem  = N'TSQL',
     @database_name = N'master',
     @retry_attempts = 2,
     @retry_interval = 1,
     @command = N'
SET NOCOUNT ON;

DECLARE @dir  nvarchar(260) = N''<CILOVA_CESTA>\'';   -- doplnit dle kroku 0.2
DECLARE @file nvarchar(400);

-- 1) Databaze musi byt ve FULL recovery, jinak zaloha logu nedava smysl
IF DATABASEPROPERTYEX(N''NAV-LIVE'', ''Recovery'') <> ''FULL''
BEGIN
    RAISERROR(''NAV-LIVE neni ve FULL recovery - zaloha logu prerusena.'', 16, 1);
    RETURN;
END

-- 2) Jeden soubor na jednu zalohu, s casovym razitkem
SET @file = @dir + N''NAV-LIVE_log_'' +
            REPLACE(REPLACE(REPLACE(CONVERT(varchar(19), GETDATE(), 126), ''-'', ''''), '':'', ''''), ''T'', ''_'') +
            N''.trn'';

-- 3) COMPRESSION + CHECKSUM. Zadny CONTINUE_AFTER_ERROR.
BACKUP LOG [NAV-LIVE]
TO DISK = @file
WITH COMPRESSION, CHECKSUM, STATS = 0;
';
GO
```

> **`<CILOVA_CESTA>`** doplnit až po rozhodnutí z kroku 0.2. Adresář musí existovat a servisní účet SQL Serveru do něj musí mít zápis.

### A3. Schedule 24/7

```sql
EXEC msdb.dbo.sp_add_jobschedule
     @job_name = N'BC_Backup_TLog_Continuous',
     @name = N'Kazdych 15 minut 24/7',
     @freq_type = 4,                  -- denne
     @freq_interval = 1,
     @freq_subday_type = 4,           -- minuty
     @freq_subday_interval = 15,
     @active_start_time = 000000,
     @active_end_time = 235959;
GO

EXEC msdb.dbo.sp_add_jobserver @job_name = N'BC_Backup_TLog_Continuous';
GO
```

> Pozn.: `@freq_type = 4` (denně) je pro tento účel vhodnější než `= 8` (týdně se seznamem dnů), který používá stávající maintenance plán. Odpadá možnost, že někdo omylem odškrtne den.

### A4. Ruční test (krok 0.4)

```sql
EXEC msdb.dbo.sp_start_job @job_name = N'BC_Backup_TLog_Continuous';
GO
WAITFOR DELAY '00:00:20';

SELECT TOP 3 database_name, type,
       CONVERT(varchar(19), backup_finish_date, 120) AS kdy,
       CAST(backup_size/1024.0/1024 AS decimal(10,1)) AS mb,
       LEFT(mf.physical_device_name, 90) AS soubor
FROM msdb.dbo.backupset b
JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = b.media_set_id
WHERE b.database_name = 'NAV-LIVE' AND b.type = 'L'
ORDER BY b.backup_finish_date DESC;
```

Musí se objevit **nový soubor s časovým razítkem** v cílovém adresáři.

### A5. Zapnutí (krok 0.5)

```sql
EXEC msdb.dbo.sp_update_job @job_name = N'BC_Backup_TLog_Continuous', @enabled = 1;
```

### A6. Vypnutí starých jobů (krok 0.7 — **až po dvou úspěšných bězích**)

```sql
-- KONTROLA PRED VYPNUTIM: musi vratit aspon 2 zalohy z noveho umisteni
SELECT COUNT(*) AS pocet_z_noveho_jobu
FROM msdb.dbo.backupset b
JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = b.media_set_id
WHERE b.database_name = 'NAV-LIVE' AND b.type = 'L'
  AND mf.physical_device_name LIKE N'<CILOVA_CESTA>%'
  AND b.backup_finish_date > DATEADD(HOUR, -2, GETDATE());
GO

-- Teprve pokud vyse vyslo >= 2:
EXEC msdb.dbo.sp_update_job @job_name = N'BackupMaintenancePlan.Tlog',  @enabled = 0;
EXEC msdb.dbo.sp_update_job @job_name = N'BackupMaintenancePlan.Tlog2', @enabled = 0;
```

> **Nemazat.** Vypnutý job jde vrátit jedním příkazem, smazaný subplan maintenance plánu se obnovuje složitě.

### A7. Kontrola po nasazení (krok 0.9)

```sql
SELECT log_reuse_wait_desc FROM sys.databases WHERE name = 'NAV-LIVE';   -- ma byt NOTHING

SELECT DATEDIFF(MINUTE, MAX(backup_finish_date), GETDATE()) AS log_stari_min
FROM msdb.dbo.backupset
WHERE database_name = 'NAV-LIVE' AND type = 'L';                          -- ma byt < 20
```

Druhá kontrola **druhý den ráno** — v `backupset` musí být zálohy i z nočních hodin.

---

## Příloha B — mapa nálezů oponentura 1 → v3

| Nález | Závažnost | v3 | Zbývá |
|---|---|---|---|
| O1 strop logu | 🔴 | Krok 0.1 | provést |
| O2 kapacita | 🔴 | zmrazení Fáze 2 | provést |
| O3 diff zálohy | 🔴 | Krok 0.1 | provést |
| O4 přepis schedule | 🟠 | samostatný job | ✅ princip |
| O5 objem logu | 🟠 | Fáze 1 | provést |
| O6 obnova aplikace | 🟠 | akceptační protokol | ✅ |
| O7 vlastník | 🟠 | RACI bez jmen | doplnit jména |
| O8 bezpečnost záloh | 🟠 | odrážka | **rozpracovat** |
| O9 stovky souborů | 🟡 | generátor Fáze 2 | provést |
| O10 falešná přesnost | 🟡 | neutrální | — |
| O11 bus factor | 🟡 | — | **runbook chybí** |
| O12 alternativy | 🟡 | log shipping | ✅ |
| O13 definice hotovo | 🟡 | akceptační protokol | ✅ |
| O14 CHECKDB | ⚪ | jen v protokolu | zavést jako job |
| O15 verzování | ⚪ | — | **do gitu** |

**Nové v této oponentuře:** N1 🔴, N2a 🔴, N2b 🔴, N3 🟠, N4 🟠, N5 🟡, N6 🟡

---

## Příloha C — otevřené otázky napříč všemi koly

Otázky, které visí od první oponentury a **nikdo je zatím nezodpověděl**:

| # | Otázka | Kdo odpoví | Blokuje |
|---|---|---|---|
| 1 | Jaký je `max_size` a aktuální velikost logu? | dotaz | rozhodnutí o naléhavosti |
| 2 | Existují diferenciální zálohy? | dotaz | volbu varianty |
| 3 | Je denní full pro test `COPY_ONLY`? | dotaz | volbu varianty |
| 4 | Kolik je volného místa na kterém svazku? | dotaz | Fázi 2 |
| 5 | Je G: jiné fyzické pole než E: a F:? | správce infra | hodnotu kopie č. 1 |
| 6 | Zálohuje se virtuál na úrovni VMware? | správce infra | **celý návrh** |
| 7 | Existuje jakákoli kopie záloh mimo server? | správce infra | ochranu proti ztrátě serveru |
| 8 | Edice SQL Serveru? | dotaz | `RESTORE PAGE`, AG |
| 9 | Je Database Mail funkční? | dotaz | Krok 0.3 |
| 10 | Co v noci generuje ten objem logu? | měření | Fázi 4 |
| 11 | **Jaké RPO a RTO firma potřebuje?** | **vedení** | **všechno** |
| 12 | Je Software Assurance? | licenční správa | log shipping |

Otázka 11 je položená od prvního dokumentu a je jediná, na kterou nemůže odpovědět IT. Všechny tři návrhy si zatím RPO a RTO **určily samy** — což je v pořádku jako výchozí odhad, ale ne jako trvalý stav.

---

## Příloha D — co udělat dnes

Bez rozhodnutí, bez měření, bez podpisu. Tři kroky, dohromady necelá hodina, všechny vratné.

### 1. Změřit (15 min, jen čtení)

```sql
EXEC master..xp_fixeddrives;
GO
USE [NAV-LIVE];
SELECT name, type_desc,
       CAST(size*8.0/1024/1024 AS decimal(10,1)) AS size_gb,
       CASE max_size WHEN -1 THEN 'neomezeno'
            ELSE CAST(CAST(max_size*8.0/1024/1024 AS decimal(10,1)) AS varchar(20)) END AS max_gb,
       CAST(FILEPROPERTY(name,'SpaceUsed')*8.0/1024/1024 AS decimal(10,1)) AS pouzito_gb,
       growth, is_percent_growth
FROM sys.database_files;
GO
USE [master];
SELECT b.type, CONVERT(varchar(19), b.backup_finish_date,120) AS kdy,
       b.is_copy_only, LEFT(b.user_name,25) AS spustil
FROM msdb.dbo.backupset b
WHERE b.database_name='NAV-LIVE' AND b.type IN ('D','I')
  AND b.backup_finish_date > DATEADD(DAY,-30,GETDATE())
ORDER BY b.backup_finish_date DESC;
```

Odpoví na otevřené otázky 1–4 najednou.

### 2. Rozšířit okno log záloh (5 min)

Buď rychle přes `sp_update_schedule` (příloha A1 návrhu v2), nebo rovnou správně přes samostatný job (příloha A tohoto dokumentu). **Cokoli z toho je lepší než dnešní stav.**

### 3. Ověřit zítra ráno (2 min)

```sql
SELECT TOP 5 CONVERT(varchar(19), backup_finish_date, 120) AS kdy,
       CAST(backup_size/1024.0/1024 AS decimal(10,1)) AS mb
FROM msdb.dbo.backupset
WHERE database_name='NAV-LIVE' AND type='L'
ORDER BY backup_finish_date DESC;
```

Musí tam být zálohy z nočních hodin. Pokud ano, problém, kvůli kterému tohle všechno vzniklo, je vyřešený — a zbytek dokumentace je o tom, jak ho udržet vyřešený.

---

*Konec oponentury 2. Nesouhlas s kteroukoli částí je vítaný a má být zaznamenán jako reakce.*
