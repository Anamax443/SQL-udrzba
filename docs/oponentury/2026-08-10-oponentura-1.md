# Oponentura návrhu zálohování NAV-LIVE – detailní recenze

> Datum: 2026-08-10
> Předmět oponentury: `NAV-LIVE-zalohovani-navrh-v2.md`
> Podklad k předmětu: export Event Logu `itdashboard-events-202608100704-filtered.csv`, GUI snímky SQL Server Agenta, výstupy dotazů nad `msdb`
> Oponovaný systém: NAV-LIVE (Dynamics 365 Business Central 14) na B-S-W-SQL-01, SQL Server 2017
> Autor oponentury: tentýž jako autor návrhu — **viz kapitola 0.2, střet zájmů**

---

## 0. Úvod

### 0.1 Co tento dokument je a co není

Tohle **není** validace návrhu. Je to pokus návrh rozbít.

Oponentura vychází z předpokladu, že návrh na zálohování je **nejnebezpečnější druh dokumentu, jaký v IT existuje** — protože jeho selhání se nikdy neprojeví v době, kdy se dá opravit. Špatně napsaná aplikace spadne. Špatně navržené zálohování funguje bezvadně roky a selže přesně jednou, ve chvíli, kdy na něm závisí existence firmy.

Proto se tento dokument záměrně chová nepřátelsky k vlastnímu návrhu:

- každé tvrzení se ptá „**odkud to víme?**"
- každé doporučení se ptá „**co když je to špatně?**"
- každá fáze se ptá „**jak to poznáme, když to nezafunguje?**"

### 0.2 ⚠ Střet zájmů — přiznání

**Autor návrhu i autor této oponentury je tentýž.** To je metodicky vadné a je potřeba to říct nahlas, protože to snižuje hodnotu tohoto dokumentu.

Autor nemůže spolehlivě najít slepá místa vlastního uvažování. Co v takové situaci jde udělat a co bylo uděláno:

| Kompenzace | Provedeno |
|---|---|
| Explicitně vypsat všechna neověřená tvrzení a označit jejich důkazní stav | kap. 2, příloha A |
| Vypsat vlastní chyby udělané během šetření | kap. 3 |
| Aktivně hledat způsoby, jak návrh **uškodí** | kap. 4 |
| Zvážit alternativy, které návrh zamítl mlčky | kap. 5 |
| Formulovat protinávrh proti sobě | kap. 8 |

**Co to nenahradí:** nezávislého čtenáře. Doporučuji nechat návrh i tuto oponenturu přečíst někým, kdo u toho nebyl — ideálně partnerem pro BC nebo externím DBA. Náklad je pár hodin práce, sázka je celá firemní databáze.

### 0.3 Jak číst závažnost nálezů

| Značka | Význam | Reakce |
|---|---|---|
| 🔴 **BLOKUJÍCÍ** | Návrh nelze v této podobě nasadit, případně nasazení může uškodit | vyřešit před nasazením |
| 🟠 **ZÁVAŽNÉ** | Návrh je použitelný, ale stojí na neověřeném předpokladu | ověřit do týdne |
| 🟡 **STŘEDNÍ** | Nedostatek, který se projeví později | zařadit do plánu |
| ⚪ **DROBNÉ** | Přesnost, formulace, kosmetika | při nejbližší revizi |

---

## 1. Shrnutí oponentury

### 1.1 Verdikt

> **PODMÍNĚNĚ PŘIJATO.**
> Návrh je v jádru správný a jeho Fáze 1 je bezpečná a naléhavá.
> Fáze 2 a dál **nelze schválit**, dokud se neověří devět předpokladů, na kterých stojí.

Jádro návrhu — *„zálohy transakčního logu musí běžet nepřetržitě, protože jsou jediným mechanismem uvolňování logu"* — je technicky nezpochybnitelné a řeší doložený, opakující se produkční incident.

Všechno ostatní v návrhu stojí na podkladech, které jsou **buď z jednoho dne pozorování, nebo z poznámek staré tři týdny, nebo z odhadu.**

### 1.2 Přehled nálezů

| # | Nález | Závažnost |
|---|---|---|
| O1 | Strop logu 100 GB nebyl v tomto šetření nikdy ověřen | 🔴 |
| O2 | Varianta A může zaplnit zálohovací disk a vypnout **všechny** zálohy | 🔴 |
| O3 | Neexistuje jediný důkaz, že diff zálohy vůbec vznikají | 🔴 |
| O4 | Změna přes `sp_update_schedule` se může tiše vrátit | 🟠 |
| O5 | Tvrzení „~100 GB logu za noc" pochází z poznámky, ne z měření | 🟠 |
| O6 | Návrh nepokrývá obnovu **aplikace**, jen databáze | 🟠 |
| O7 | Nikde není určen vlastník procesu | 🟠 |
| O8 | Zálohy nejsou šifrované ani není řešen přístup k nim | 🟠 |
| O9 | Zvýšení frekvence na 5 min má nezmíněné vedlejší účinky | 🟡 |
| O10 | Falešná přesnost čísel („13 h 44 min") | 🟡 |
| O11 | Návrh neřeší personální riziko (bus factor 1) | 🟡 |
| O12 | Alternativy byly zamítnuty mlčky, bez rozboru | 🟡 |
| O13 | Chybí definice, co znamená „obnoveno" | 🟡 |
| O14 | `DBCC CHECKDB` nad kopií není totéž co nad produkcí | ⚪ |
| O15 | Dokument nemá verzování ani schvalovací stopu | ⚪ |

### 1.3 Co by oponent udělal jinak

1. **Fázi 1 nasadit dnes** — v tom je shoda, riziko je minimální a přínos doložený.
2. **Fázi 2 a 3 zmrazit na týden** a místo toho **měřit**. Návrh dnes nemá dost dat na to, aby se podle něj utrácely peníze za úložiště.
3. **Zvážit alternativy** z kapitoly 5, zejména log shipping — řeší současně RPO i havarijní scénář a návrh ho vůbec nezmiňuje.

---

## 2. Neověřené předpoklady

Toto je nejdůležitější kapitola celé oponentury.

Návrh vznikl během jednoho dopoledne z jednoho exportu Event Logu a několika snímků obrazovky. Čte se ale jako výsledek auditu. **Ten rozpor je jeho hlavní slabinou.**

### 2.1 🔴 O1 — Strop logu 100 GB nebyl ověřen

Návrh na několika místech tvrdí:

> „log každou noc naroste na strop 100 GB"

**Odkud to víme?** Z poznámky z 2026-07-23. **V tomto šetření to nikdo neověřil.** Dotaz na `sys.database_files`, který měl vrátit `max_size` log souboru, byl součástí připraveného skriptu — ale ten skript se **nikdy nespustil celý**. Uživatel místo něj poslal snímek Database Properties, kde je jen souhrn (`Size 800 000 MB`, `Space Available 121 486 MB`).

Z toho snímku **nejde odvodit**:
- jaký je `max_size` logu
- jak je log velký teď
- kolik z těch 121 GB volného místa je v logu a kolik v datovém souboru
- jaký je přírůstek při autogrow (`growth`, `is_percent_growth`)

**Proč na tom záleží:** celá argumentace o naléhavosti stojí na tom, že log naráží na tvrdý strop. Kdyby log neměl strop a jen rostl, byl by to jiný problém (došlo by místo na F:) s jinou diagnostikou a jiným pořadím oprav.

**Co s tím:** příloha B1. Dokud tohle není doloženo, je kapitola 5.1 návrhu **tvrzením, ne zjištěním**.

### 2.2 🔴 O3 — Neexistuje důkaz, že diff zálohy vznikají

Návrh věnuje celou kapitolu 6.4 riziku, že `COPY_ONLY` chybí a tím se rozbíjí **diferenciální** řetěz.

Celá ta úvaha je ale postavená na předpokladu, že diferenciální zálohy existují a používají se. **Doklad pro to je jediný:** v seznamu jobů je `BackupMaintenancePlan.Diff` naplánovaný týdně v 01:30.

Nikdy jsme neviděli **ani jeden záznam typu `I` v `msdb.dbo.backupset`.** Dotaz, který to měl ukázat (příloha A2 návrhu), se nespustil.

**Možnosti, které nelze vyloučit:**

| Scénář | Důsledek pro návrh |
|---|---|
| Diff zálohy běží a fungují | kap. 6.4 platí, varianta B je reálná |
| Diff job je naplánovaný, ale selhává | kap. 6.4 je bezpředmětná, ale **je to samostatný nález** |
| Diff job běží nad jinou databází | celá kap. 6.4 je zbytečná |
| Diff se dělají, ale nikdo je nikdy nepoužil při obnově | rizikovější, než návrh tvrdí |

**Ironie:** pokud diff zálohy nefungují, pak návrh varuje před rozbitím něčeho, co je rozbité už dnes — a **skutečný nález (diff nefunguje) mu unikl.**

### 2.3 🟠 O5 — „~100 GB logu za noc" je odhad, ne měření

Návrh v kapitole 8.2 staví významnou úvahu (podezření na údržbu indexů) na tvrzení, že v noci vzniká patnáctinásobek denního objemu logu.

**Řetěz odvození:**

```
poznámka z 07-23: "log nabobtná na 100 GB"
   ↓ (předpoklad: naroste z ~0)
   ↓ (předpoklad: děje se to každou noc)
   ↓ (předpoklad: většina vzniká v noci, ne odpoledne po 15:46)
závěr: "v noci vzniká ~100 GB logu"
```

Tři předpoklady za sebou, žádný ověřený. Přitom mezi 15:46 a půlnocí **taky nikdo nezálohuje**, takže část toho objemu může být klidně odpolední a večerní práce lidí — což by celou úvahu o údržbě indexů obrátilo naruby a naopak potvrdilo, že se pracuje déle, než návrh předpokládá.

**Co s tím:** příloha B4. Po nasazení Fáze 1 bude odpověď k dispozici do 24 hodin zdarma, protože se začne zálohovat průběžně a objemy budou v `backupset` vidět po hodinách.

**Do té doby by kapitola 8.2 neměla být podkladem pro žádné rozhodnutí.**

### 2.4 🟠 Další neověřená tvrzení

| # | Tvrzení návrhu | Důkazní stav |
|---|---|---|
| a | „Chyba běží celou noc, ne 74 s" | odvozeno z poznámky + z toho, že export je useknutý. **Nedoloženo pro tento konkrétní den.** |
| b | „Poslední full 09.08. 18:43 nevznikla z plánu" | plán říká 00:30, ale neznáme dny ani ostatní subplány. Mohl to být jiný job. |
| c | „Denní full pro test se dělá denně" | víme jen, že skript čte z `G:\Backup\NAV-TEST-USERS`. Kdo a jak často tam soubory dává, nevíme. |
| d | „Incident se opakuje každou noc" | máme jeden den + poznámku. Mohl to být důsledek jednorázové noční akce. |
| e | „G: je zálohovací svazek" | odvozeno z názvu složky v cizím skriptu. |
| f | „Údržba indexů generuje ten log" | čirá hypotéza, žádný doklad. |
| g | „57 uživatelů" | z GUI, spolehlivé, ale je to *Number of Users* databáze, ne počet lidí. |
| h | „Komprese záloh je zapnutá" | viděno na jednom snímku u `Tlog2`. O ostatních nevíme. |

**Bod (d) je podceněný.** Pokud incident nastal proto, že v neděli večer někdo pustil reindexaci nebo velkou dávkovou operaci, pak návrh sice pořád platí, ale **naléhavost je jiná** a pořadí kroků by mohlo být jiné.

---

## 3. Chyby udělané během šetření

Tato kapitola je zde kvůli kalibraci: ukazuje, jak spolehlivá byla průběžná analýza, ze které návrh vzešel. Odpověď zní: **středně.**

| # | Tvrzení | Oprava | Kdy odhaleno |
|---|---|---|---|
| 1 | „Výpadek trval 74 sekund" | Export je zespoda useknutý, viděli jsme jen konec | po ~1 h |
| 2 | „V neděli neběží zálohy logu" | Neděle je krytá, `Tlog` ji má | do 10 min, opraveno |
| 3 | „`Tlog2` je redundantní, vypnout" | Je sobotní, vypnutí by odkrylo sobotu | až po dotazu uživatele |
| 4 | „`shrink_log` běží denně v 05:00" | Běží v neděli | při čtení GUI |
| 5 | „Oprava z 23. 7. byla nasazená a někdo ji vrátil" | `date_modified` = 2025-01-10, nikdy nasazená nebyla | až z `msdb` |
| 6 | „~280 chyb 9002" | Ruční počet, neověřený | dosud neověřeno |
| 7 | Pokus připojit se přímo na produkční SQL | Uživatel zamítl, správně | okamžitě |

**Co z toho plyne pro čtenáře návrhu:**

Body 2, 3 a 4 mají společného jmenovatele — **domněnka místo dotazu.** Ve všech třech případech bylo tvrzení vysloveno dřív, než se ověřilo, a ve všech třech případech bylo špatně. To je systematická vada, ne náhoda.

Bod 5 je nejzajímavější: **oponentura vlastní paměti odhalila, že „hotový" úkol hotový nebyl.** Kdyby se `date_modified` nezkontroloval, hledala by se neexistující příčina („kdo nám to přepisuje?") místo skutečné („nikdo to neudělal").

**Poučení do procesu:** každé tvrzení o konfiguraci produkčního systému musí mít vedle sebe dotaz, kterým se dá ověřit. Návrh v2 to částečně dělá (přílohy A1–A7), ale nedůsledně.

---

## 4. Kde návrh může uškodit

Návrh je psaný jako zlepšení. Oponentura se ptá: **kterým krokem si můžeme pohoršit?**

### 4.1 🔴 O2 — Varianta A může vypnout všechny zálohy

Návrh doporučuje variantu A (denní full) a sám spočítal, že s retencí 14 dní to znamená **3–5 TB**.

Pak ale pokračuje, jako by to byl detail k doladění. **Není.** Je to podmínka proveditelnosti.

**Co se stane, když se varianta A nasadí bez ověření kapacity:**

```
den 1–6    full zálohy se vejdou, všechno vypadá dobře
den 7      disk 90 %
den 8      disk plný
           → full záloha selže
           → log zálohy selžou (píšou na stejný svazek)
           → log se přestane uvolňovat
           → chyba 9002
           → jsme ve stejném stavu jako 2026-08-10, ale navíc
             bez použitelných záloh za posledních 8 dní
```

**Tenhle scénář je horší než dnešní stav.** Dnes zálohy aspoň přes den fungují.

**Zmírnění, které v návrhu chybí:**

1. Ověřit volné místo **před** změnou (`xp_fixeddrives`)
2. Nasadit variantu A **nejdřív s retencí 3 dny** a teprve po měření prodloužit
3. Alert na volné místo **zavést dřív než změnu**, ne až ve Fázi 3
4. Log zálohy psát **na jiný svazek než full zálohy**, aby zaplnění jednoho nezastavilo druhé

Bod 4 je zásadní a v návrhu vůbec není. Oddělení svazků pro full a log zálohy je levná a účinná pojistka.

### 4.2 🟠 O4 — Změna schedule se může tiše vrátit

Návrh v příloze A1 mění schedule pomocí `sp_update_schedule` a v poznámce varuje, ať se nejdřív zavře designer maintenance plánu.

**To je nedostatečné.** Designer plánu přepíše schedule kdykoli později — příště, až kdokoli plán otevře a uloží, třeba za půl roku kvůli jiné změně. Nikdo si toho nevšimne.

Reálně se to už jednou stalo: `date_modified` = 2025-01-10 ukazuje, že tam někdo v lednu 2025 sáhl. A hodnota, kterou tam tehdy nastavil, přežila do dneška.

**Zmírnění, které v návrhu chybí:**

| Varianta | Odolnost | Poznámka |
|---|---|---|
| `sp_update_schedule` | 🔴 nízká | přepíše designer |
| Změna v designeru + uložení plánu | 🟡 střední | dnes selhalo, uživatel to zkusil |
| **Vyjmout log zálohy z maintenance plánu do samostatného jobu** | 🟢 vysoká | designer na něj nesahá |
| Denní kontrola schedule + alert při změně | 🟢 vysoká | detekce místo prevence |

**Doporučení oponenta:** zálohu logu z maintenance plánu **vyndat úplně** a udělat z ní samostatný SQL Agent job s vlastním T-SQL. Maintenance plán je pro tuhle úlohu zbytečná abstrakce, která přidává jediné — možnost tiše přepsat nastavení.

Jako minimum pak hlídat `date_modified` u schedule a alertovat na změnu. Vypnutý job `BC_Jobs_Backup_Monitor_Simple` je mimochodem přesně tenhle nástroj a nikdo ho nezapnul.

### 4.3 🟡 O9 — Zvýšení na 5 minut má vedlejší účinky

Návrh doporučuje ve Fázi 3 zkrátit interval na 5 minut a tvrdí, že to „nestojí nic navíc". To je pravda jen na úrovni objemu dat.

**Co návrh nezmiňuje:**

| Důsledek | Dnes (15 min, 10 h) | Návrh (5 min, 15 h) | Faktor |
|---|---|---|---|
| Souborů denně | ~41 | ~198 | 4,8× |
| Souborů při retenci 14 dní | ~574 | ~2 772 | 4,8× |
| Záznamů v `msdb.dbo.backupset` / rok | ~15 000 | ~72 000 | 4,8× |
| Kroků při ruční obnově k času | desítky | **stovky** | — |

Tři konkrétní problémy:

1. **`msdb` roste.** Historie záloh se nemaže sama. Bez `sp_delete_backuphistory` se `msdb` nafoukne a dotazy nad `backupset` (včetně monitoringu z návrhu) se zpomalí. V návrhu o tom není ani slovo.

2. **Obnova se stává neproveditelnou ručně.** Sestavit `RESTORE LOG` pro 300 souborů z ruky je nereálné. Návrh v kapitole 13.1 ukazuje postup se třemi řádky a poznámkou „…". **To je v ostré situaci k ničemu.** Chybí generátor obnovovacího skriptu.

3. **Maintenance Cleanup mazající podle stáří souboru** může u vysokého počtu souborů smazat log zálohu, která je pořád součástí potřebného řetězu — pokud se retence full a log rozejdou.

**Doporučení oponenta:** ke každé změně frekvence dodat i skript, který **vygeneruje `RESTORE` sekvenci z `msdb`**. Bez něj je vysoká frekvence past: zdánlivě lepší RPO, prakticky nepoužitelná obnova.

### 4.4 🟡 Předčasné vypnutí `Tlog2`

Návrh na to upozorňuje správně (nejdřív Fáze 1, pak vypnout). Ale je to zapsané jako odrážka v seznamu úkolů, ne jako závislost.

V seznamu úkolů Fáze 2 to vypadá takhle:

> - [ ] `Tlog2` vypnout — **až po fázi 1**, ne dřív (kryje sobotu)

Kdokoli, kdo bude odškrtávat úkoly a nepřečte závorku, vypne sobotní zálohy. **Doporučení:** doplnit do úkolu podmínku, kterou lze ověřit dotazem — „vypnout `Tlog2` až poté, co dotaz X vrátí `freq_interval = 127`".

### 4.5 ⚪ `shrink_log` byl vypnut bez zjištění proč vznikl

Vypnutí bylo správné. Ale nikdo se nezeptal, **proč ho tam někdo v roce 2021 dal.** Pravděpodobně proto, že docházelo místo na F:.

Pokud je to tak a F: je malý, může se po nasazení Fáze 1 ukázat, že log sice přestane růst, ale prostor na F: bude pořád těsný — a někdo ten job zase zapne. **Doporučení:** zjistit velikost a volné místo na F: a doplnit do dokumentu, proč už `shrink_log` není potřeba.

---

## 5. Alternativy, které návrh zamítl mlčky

Návrh nabízí volbu mezi variantou A a B. Obě jsou variace téhož: *„zálohuj častěji na disk"*. Existují ale i jiné cesty, které návrh vůbec nezmiňuje. To je metodická vada — čtenář neví, jestli byly zváženy a zamítnuty, nebo na ně autor nepomyslel.

### 5.1 Log shipping na druhý server

**Princip:** log zálohy se automaticky kopírují a přehrávají na záložní server, který drží kopii databáze zpožděnou o minuty.

| Pro | Proti |
|---|---|
| RPO v minutách, stejně jako návrh | potřeba druhý server a licence |
| **Navíc řeší i havárii serveru** — RTO v desítkách minut místo hodin | složitější provoz |
| Sekundární kopie použitelná pro čtení a reporty | nutná disciplína při zásazích |
| Funguje ve Standard edici | není automatický failover |
| **Vedlejší efekt: nutí zálohy logu běžet nepřetržitě** | |

**Verdikt oponenta:** tohle mělo v návrhu být. Pro firmu, jejíž existence stojí na jedné 800GB databázi, je log shipping **standardní** opatření, ne luxus. A protože jeho fungování vyžaduje nepřetržité log zálohy, řeší mimochodem i původní problém — a to způsobem, který nikdo omylem nevrátí zpátky, protože by tím rozbil viditelnou věc.

### 5.2 Availability Groups

SQL Server 2017 **Standard** umožňuje *Basic Availability Groups* — jedna databáze, jedna replika, bez čtení ze sekundáru. Enterprise nabízí plnohodnotné AG.

**Verdikt:** zmínit a zamítnout s odůvodněním (cena, složitost, Basic AG má tvrdá omezení). Ale zamítnout **vědomě**, ne mlčky. Rozhoduje o tom edice — kterou jsme dosud nezjistili.

### 5.3 Zálohování na úrovni virtuálního stroje (Veeam a podobné)

Server je VMware VM (doloženo z chyby TPM). Je pravděpodobné, že už dnes existuje nějaká VM-level záloha, o které tento návrh **vůbec neví**.

**To je vážná mezera.** Pokud VM zálohy existují:
- mohou být tou chybějící kopií mimo server
- mohou používat application-aware processing a **samy truncovat log** — což by změnilo celou diagnostiku
- mohou naopak dělat VSS snapshoty, které do zálohovacího řetězu zasahují

**Doporučení oponenta:** dřív než se schválí jakákoli fáze, zjistit, **jestli a jak se ten virtuál zálohuje.** Je to jedna otázka na správce virtualizace a může celý návrh přepsat.

### 5.4 Prosté zvětšení stropu logu

Nejlevnější „řešení": zvednout `max_size` logu z 100 GB na 300 GB.

| Pro | Proti |
|---|---|
| pět minut práce | **neřeší nic** — jen odsouvá problém |
| žádná změna procesů | RPO zůstává 13 h 44 min |
| | práce pořád existuje v jediné kopii |

**Verdikt:** zamítnout, ale **explicitně** — protože je to první věc, kterou někdo navrhne, až uslyší „plný log". Návrh na to musí mít připravenou odpověď: *strop není příčina, je to pojistka, která zafungovala.*

### 5.5 SIMPLE recovery + časté full/diff

**Verdikt:** zamítnout tvrdě. Ruší obnovu k času, tedy přesně to, co je cílem. Uvádím jen proto, že to bývá navrhováno jako „zjednodušení" a je potřeba mít argument po ruce.

### 5.6 Souhrn alternativ

| Alternativa | Řeší RPO | Řeší RTO | Řeší DR | Cena | Verdikt |
|---|---|---|---|---|---|
| Návrh (častější log zálohy) | ✅ | ❌ | ❌ | nulová | **nutné minimum** |
| Log shipping | ✅ | ✅ | ✅ | server + licence | **doplnit do návrhu** |
| Basic AG | ✅ | ✅ | ✅ | vyšší | zvážit po zjištění edice |
| VM-level zálohy | ⚠ | ✅ | ✅ | pravděpodobně už máme | **zjistit stav** |
| Zvětšit strop logu | ❌ | ❌ | ❌ | nulová | zamítnout |
| SIMPLE recovery | ❌ | ⚠ | ❌ | nulová | zamítnout |

---

## 6. Co návrh neřeší vůbec

### 6.1 🟠 O6 — Obnova databáze ≠ obnova provozu

Návrh se jmenuje „zálohování databáze" a tomu odpovídá. Ale zadání znělo **„obnovit firmu"**. Mezi tím je propast.

Co všechno musí fungovat, aby firma po obnově opravdu jela:

| Vrstva | Řeší návrh? |
|---|---|
| Data v SQL | ✅ |
| Service tier BC (`B-S-W-NAV-01`) | ⚠ jen restart |
| Konfigurace service tieru (`CustomSettings.config`) | ❌ |
| Licence BC | ❌ |
| Nasazené objekty / .fob / rozšíření | ❌ |
| Vazby na M-Files | ❌ |
| EDI složky a jejich obsah | ❌ |
| Certifikáty (EET, API) | ❌ |
| Účty a oprávnění (AD, SQL loginy) | ⚠ jen zmínka o `master` |
| Tiskárny, sestavy, doplňky Office | ❌ |

**Nález:** dokument slibuje víc, než pokrývá. Buď se má přejmenovat na *„zálohování a obnova databáze NAV-LIVE"*, nebo se má doplnit kapitola o obnově aplikační vrstvy.

Oponent doporučuje první variantu a založit samostatný dokument *„Havarijní plán obnovy BC"*, kde bude tenhle návrh jednou z kapitol.

### 6.2 🟠 O7 — Nikde není vlastník

Návrh má fáze, úkoly, zaškrtávací políčka. **Nemá jediné jméno.**

Kdo:
- nasadí Fázi 1?
- kontroluje denně, že zálohy proběhly?
- reaguje na alert ve 3 ráno?
- schvaluje variantu A nebo B?
- odpovídá za to, že se test obnovy jednou měsíčně opravdu udělá?

Bez odpovědí na tohle je dokument **přáním, ne plánem.** Historie to potvrzuje: návrh z 23. 7. 2026 nikdo nenasadil, protože nikdo nebyl odpovědný za to, aby se nasadil.

**Doporučení:** doplnit tabulku RACI, byť s jediným jménem u všeho. Jedno jméno je nekonečně víc než žádné.

### 6.3 🟠 O8 — Bezpečnost záloh vůbec není řešena

`.bak` soubor NAV-LIVE obsahuje **kompletní firemní data**: zákazníky, ceny, mzdy v účetnictví, kontakty, obchodní historii. Jeho zkopírování je jednodušší než průnik do databáze.

Návrh neřeší:

| Otázka | Stav |
|---|---|
| Kdo má přístup ke složce se zálohami? | neznámo |
| Jsou zálohy šifrované (`BACKUP ... WITH ENCRYPTION`)? | téměř jistě ne |
| Je záloha na testovacím serveru chráněná stejně jako produkce? | ne — skript ji rozbaluje na `T:` |
| Vede se záznam, kdo zálohu obnovil? | ne |
| GDPR: obsahují zálohy osobní údaje a jaká je jejich retence? | neřešeno |

**Zvlášť ostře:** `Restore-NAV-TEST.ps1` vyrábí **plnou kopii ostrých firemních dat** na testovacím serveru, a demilitarizace řeší jen odpojení od okolních systémů — **ne přístup k datům samotným.** Kdokoli má přístup na `NAV-TEST`, má přístup ke všem firemním datům, jen o den starším.

To může být v pořádku a vědomě přijaté. Ale v dokumentu o tom není řádek.

### 6.4 🟡 O11 — Bus factor 1

Celý tenhle návrh, jeho kontext i historie problému existují v hlavě jednoho člověka a v jeho poznámkách.

Kdyby ten člověk zítra nebyl k dispozici, kdo:
- ví, že `Tlog2` kryje sobotu?
- ví, proč se nemá vypínat dřív?
- ví, že se změna schedule může vrátit uložením designeru?
- umí sestavit `RESTORE` sekvenci ze 300 souborů?

**Doporučení:** ke každému postupu obnovy v kapitole 13 doplnit „runbook" ve formě, kterou provede i někdo, kdo systém nezná — konkrétní příkazy, konkrétní cesty, konkrétní kontrolní body. To, co je tam dnes, je náčrt pro znalého.

### 6.5 🟡 O13 — Chybí definice hotového

Návrh nikde neříká, **jak se pozná, že obnova proběhla úspěšně.**

„Databáze je online" není totéž co „firma může fakturovat". Chybí kontrolní seznam typu:

- [ ] BC service tier běží a přijímá přihlášení
- [ ] poslední zaúčtovaný doklad odpovídá očekávanému času
- [ ] číselné řady navazují a negenerují duplicity
- [ ] job queue běží a nemá viset úlohy ve stavu *In Process*
- [ ] EDI složky nejsou plné neodeslaných zpráv
- [ ] M-Files vazby odpovídají
- [ ] testovací faktura projde celým procesem

Bez toho se po obnově neví, jestli je hotovo, nebo jestli za tři dny vyplave, že něco nesedí.

---

## 7. Metodická kritika

### 7.1 🟡 O10 — Falešná přesnost

Návrh operuje s číslem **13 hodin 44 minut**. Zní to jako výsledek měření. Je to rozdíl dvou hodnot ze schedule (15:46 → 5:30).

Skutečná doba, po kterou práce existuje v jediné kopii, závisí na tom, kdy proběhla **poslední úspěšná** záloha logu — což může být jindy, když job selže. Rozptyl je klidně několik hodin.

Podobně:
- „~226 událostí" vs „~280 chyb 9002" — dva ruční počty, ani jeden ověřený
- „3–5 TB" — odhad postavený na odhadu komprese, postavený na odhadu objemu
- „0,5 GB logu za hodinu" — z pěti vzorků za jedno dopoledne

**Doporučení:** čísla, která nejsou změřená, psát jako intervaly nebo je označit. Rozdíl mezi *„13 h 44 min"* a *„zhruba 14 hodin, dle schedule"* je pro důvěryhodnost dokumentu zásadní — první svádí k tomu, brát celý dokument jako naměřený.

### 7.2 🟡 O12 — Doporučení předchází datům

Návrh doporučuje variantu A. Zároveň přiznává, že neví, kolik je místa. **To je doporučení vydané před tím, než jsou k dispozici data, která o něm rozhodují.**

Správné pořadí by bylo: změřit → rozhodnout. Návrh dělá: doporučit → a mimochodem změřit.

Je to pochopitelné (autor chce být užitečný), ale nebezpečné: doporučení v dokumentu má váhu a někdo ho může vzít a nasadit, aniž by se dostal k otevřeným otázkám na konci.

**Doporučení:** doporučení varianty přesunout **za** kapitolu s měřením a v mezidobí psát „nelze rozhodnout, chybí data X".

### 7.3 ⚪ O15 — Chybí schvalovací stopa

Dokument nemá:
- historii verzí s tím, co se změnilo (jen poznámku „v2 oproti v1")
- kdo návrh schválil a kdy
- kdy má proběhnout revize
- odkaz na to, kde je uložen jako závazná verze

Návrh na zálohování, který sám není verzovaný a uložený tak, aby přežil ztrátu autorova počítače, je drobná, ale pikantní ironie. **Doporučení:** uložit do gitu.

---

## 8. Protinávrh: minimální bezpečná varianta

Kdyby oponent měl rozhodnout dnes a měl na to hodinu, udělal by tohle — a nic víc:

### Krok 1 — Změřit, než se cokoli změní (15 minut)

```sql
EXEC master..xp_fixeddrives;                      -- kolik je místa a kde
```
```sql
USE [NAV-LIVE];
SELECT name, type_desc,
       CAST(size*8.0/1024/1024 AS decimal(10,1))        AS size_gb,
       CASE max_size WHEN -1 THEN NULL
            ELSE CAST(max_size*8.0/1024/1024 AS decimal(10,1)) END AS max_gb,
       CAST(FILEPROPERTY(name,'SpaceUsed')*8.0/1024/1024 AS decimal(10,1)) AS pouzito_gb,
       growth, is_percent_growth
FROM sys.database_files;
```

Bez těchto dvou výstupů se nemá měnit nic. Trvá to minutu a rozhoduje to o tom, jestli je návrh proveditelný.

### Krok 2 — Rozšířit okno log záloh (5 minut)

Jediná změna z celého návrhu, která je bezpečná, levná a doložitelně nutná. Příloha A1 návrhu.

**Bez** zkracování intervalu na 5 minut. **Bez** změny variant. **Bez** rušení diffů.

### Krok 3 — Zapnout jediný alert (30 minut)

Stáří poslední log zálohy > 90 minut → e-mail. To je všechno.

Tenhle jeden alert by odhalil incident z 23. 7., zabránil jeho opakování 10. 8. a odhalí i to, když se změna z kroku 2 někdy v budoucnu tiše vrátí.

### Proč zrovna tyhle tři

| | Krok 1 | Krok 2 | Krok 3 |
|---|---|---|---|
| Riziko | nulové (čtení) | velmi nízké | nulové |
| Vratnost | — | okamžitá | okamžitá |
| Náklad | 15 min | 5 min | 30 min |
| Přínos | umožní rozhodnout | RPO 13 h → 15 min | detekce návratu |

**Všechno ostatní z návrhu** — varianta A/B, retence, 3-2-1, šifrování, log shipping — jsou správné otázky, ale **rozhodnutí, ne úkoly.** Vyžadují data z kroku 1 a odpověď firmy na to, kolik je ochotná zaplatit.

---

## 9. Kritika externí analýzy (Qwen, HTML)

K návrhu byla dodána analýza od jiného nástroje, která hodnotí, zda návrh řeší problémy z Event Logu. Pro úplnost oponentury je i ona předmětem přezkumu.

### 9.1 Faktické chyby

| # | Tvrzení | Skutečnost |
|---|---|---|
| 1 | „05:33:18 = **první** chyba 9002" | Export je zespoda useknutý; je to nejstarší **zachycený** záznam, ne první výskyt |
| 2 | „05:34:32 začíná běžet `Tlog2`" | 10. 8. 2026 bylo pondělí; `Tlog2` běží jen v sobotu |
| 3 | „Interval selhání Cache_Warming ~15 min" | Rozestupy jsou 25/15/25/15 min; míchá časy `Invoked on` s časy zápisu do logu |
| 4 | „213× chyba 9002" | Ruční počet, neověřený (můj vlastní odhad byl ~280 — také neověřený) |
| 5 | „8× job failed" | V CSV je 9 záznamů typu 208 |

Chyba č. 1 je nejzávažnější — dělá z několikahodinového stavu 74sekundový výpadek a tím podhodnocuje závažnost. **Stejnou chybu jsem původně udělal i já** (kap. 3, bod 1).

### 9.2 Metodická vada

Analýza měří návrh **proti Event Logu**, ne proti cíli.

Otázka „řeší návrh chyby z logu?" má odpověď ano. Otázka „umíme obnovit firmu?" v ní není položená. Přitom čtyři největší rizika **nedělají v Event Logu žádný záznam**:

| Riziko | Vidět v logu? |
|---|---|
| Denní full není `COPY_ONLY` | ne |
| Retence smaže kotvu řetězu | ne |
| Neexistuje kopie mimo server | ne |
| Obnova k času nikdy netestovaná | ne |

Systém může mít dokonale čistý Event Log a být zcela neobnovitelný. **Procentní skóre („Kvalita diagnózy 100 %") tedy měří pokrytí logu, ne pokrytí rizika** — a nejsou z ničeho spočítaná.

### 9.3 Co má analýza správně

- Jádro (9002 je hlavní problém a návrh na něj míří) — správně
- Klasifikace GPO a TPM jako mimo scope — správně
- **Upozornění na chybějící monitoring PLE** — oprávněné, v návrhu skutečně chybí

Poslední bod má jednu ironickou vrstvu: analýza doporučuje práh PLE `< 300 s`, zatímco v kódu toho jobu stojí `@Threshold INT = 3000; -- Zvýšeno z 300!`. Doporučuje tedy návrat k hodnotě, kterou už někdo vědomě opustil. Bez znalosti kódu jobu to vědět nemohla — ilustruje to, jak snadno vzniká sebejisté doporučení z neúplného kontextu. **Platí to i pro tento dokument.**

### 9.4 Technické poznámky

- Načítá Mermaid z veřejné CDN — na firemním počítači za TLS inspekcí se nemusí vykreslit, a za rok tam nemusí být vůbec. Pro archivovaný dokument nevhodné.
- Ve zdroji je rozsypaná diakritika; může jít o artefakt přenosu, ověřit v prohlížeči.

---

## 10. Verdikt a podmínky přijetí

### 10.1 Rozhodnutí

> **PODMÍNĚNĚ PŘIJATO**

| Část návrhu | Verdikt |
|---|---|
| Diagnóza příčiny (log backup = jediný mechanismus uvolnění) | ✅ **PŘIJATO** — technicky nezpochybnitelné |
| Fáze 1 (rozšíření okna log záloh) | ✅ **PŘIJATO** — nasadit neprodleně |
| Fáze 2 (varianta A/B, retence) | 🔴 **ODLOŽENO** — chybí data |
| Fáze 3 (5 min, offsite, alerty) | 🟠 **ČÁSTEČNĚ** — alerty ano, zbytek po měření |
| Fáze 4 (indexy, úklid) | ✅ **PŘIJATO** jako záměr |
| Doporučení varianty A | 🔴 **NEPŘIJATO** — vydáno před daty, která o něm rozhodují |

### 10.2 Podmínky pro schválení Fáze 2 a dál

1. Doložit `max_size` a aktuální velikost log souboru (O1)
2. Doložit existenci a funkčnost diferenciálních záloh (O3)
3. Doložit volné místo na všech svazcích včetně zálohovacího (O2)
4. Zodpovědět, zda a jak se zálohuje virtuální stroj (5.3)
5. Změřit skutečné objemy záloh za 7 dní běhu po Fázi 1 (O5)
6. Určit vlastníka procesu (O7)
7. Doplnit rozbor log shippingu jako alternativy (5.1)
8. Doplnit generátor `RESTORE` sekvence před zvýšením frekvence (O9)

### 10.3 Co považuji za nejnebezpečnější bod celého návrhu

Ne chybu 9002. Ta je hlučná, viditelná a teď už i pochopená.

**Nejnebezpečnější je, že obnova k časovému bodu nebyla nikdy vyzkoušena.** Všechno ostatní v tomto dokumentu i v návrhu je spekulace o tom, jak by to fungovalo. Jediný způsob, jak zjistit pravdu, je jednou to udělat.

A vzhledem k tomu, že `Restore-NAV-TEST.ps1` už dnes běží a obnovu 700GB databáze zvládá, je vzdálenost od „nevíme" k „víme" **jedno odpoledne práce.**

Kdyby z celé této oponentury měl zůstat jediný úkol, je to tenhle.

---

## Příloha A — Rejstřík tvrzení a jejich důkazní stav

| # | Tvrzení | Zdroj | Stav | Ověří |
|---|---|---|---|---|
| T01 | Log má strop 100 GB | poznámka 07-23 | ❌ neověřeno | B1 |
| T02 | Log naroste na strop každou noc | poznámka + 1 den | ⚠ částečně | B4 |
| T03 | `Tlog` běží 05:30–15:46, Ne+Po–Pá | GUI + `msdb` | ✅ doloženo | — |
| T04 | `Tlog2` běží jen v sobotu | GUI | ✅ doloženo | — |
| T05 | `date_modified` = 2025-01-10 | `msdb` | ✅ doloženo | — |
| T06 | `shrink_log` dělá `SHRINKFILE(...,10)` v neděli 5:00 | GUI | ✅ doloženo | — |
| T07 | `shrink_log` je vypnutý | `msdb` | ✅ doloženo | — |
| T08 | Chyby 9002 dne 10. 8. | Event Log | ✅ doloženo | — |
| T09 | Počet chyb 9002 = ~280 | ruční počet | ❌ neověřeno | B7 |
| T10 | Chyby běžely celou noc | odvození | ❌ neověřeno | B7 |
| T11 | Diff zálohy existují a fungují | název jobu | ❌ **neověřeno** | B2 |
| T12 | Poslední full 09. 8. 18:43 | GUI | ✅ doloženo | — |
| T13 | Ta full nevznikla z plánu | odvození | ⚠ pravděpodobné | B2 |
| T14 | Denní full pro test je `COPY_ONLY` | — | ❌ **neznámo** | B2 |
| T15 | V noci vzniká ~100 GB logu | odvození | ❌ neověřeno | B4 |
| T16 | Příčinou je údržba indexů | hypotéza | ❌ neověřeno | B5 |
| T17 | G: je zálohovací svazek | název složky | ⚠ pravděpodobné | B3 |
| T18 | G: je jiné fyzické pole než E:/F: | — | ❌ neznámo | B3 |
| T19 | Existuje kopie záloh mimo server | — | ❌ **neznámo** | dotaz na správce |
| T20 | Virtuál se zálohuje na úrovni VM | — | ❌ **neznámo** | dotaz na správce |
| T21 | Edice SQL Serveru | — | ❌ neznámo | B6 |
| T22 | Komprese záloh je zapnutá | 1 snímek | ⚠ částečně | B2 |
| T23 | Obnova k času funguje | — | ❌ **nikdy netestováno** | test |

**Souhrn: z 23 tvrzení je 8 doloženo, 5 pravděpodobných, 10 neověřených.** Z toho 5 označených tučně může změnit závěry návrhu.

---

## Příloha B — Ověřovací dotazy

### B1 — Strop a stav logu

```sql
USE [NAV-LIVE];
SELECT name, type_desc,
       CAST(size*8.0/1024/1024 AS decimal(10,1)) AS size_gb,
       CASE max_size WHEN -1 THEN 'neomezeno'
            ELSE CAST(CAST(max_size*8.0/1024/1024 AS decimal(10,1)) AS varchar(20)) END AS max_gb,
       CAST(FILEPROPERTY(name,'SpaceUsed')*8.0/1024/1024 AS decimal(10,1)) AS pouzito_gb,
       CAST(100.0*FILEPROPERTY(name,'SpaceUsed')/size AS decimal(5,1)) AS pouzito_pct,
       growth, is_percent_growth, physical_name
FROM sys.database_files;

SELECT COUNT(*) AS vlf_count FROM sys.dm_db_log_info(DB_ID());
```

### B2 — Existují diff zálohy? Je full `COPY_ONLY`?

```sql
SELECT b.type,
       CONVERT(varchar(19), b.backup_finish_date,120) AS kdy,
       CAST(b.backup_size/1024.0/1024/1024 AS decimal(10,1))            AS raw_gb,
       CAST(b.compressed_backup_size/1024.0/1024/1024 AS decimal(10,1)) AS na_disku_gb,
       b.is_copy_only, LEFT(b.user_name,25) AS spustil,
       LEFT(mf.physical_device_name,70) AS soubor
FROM msdb.dbo.backupset b
JOIN msdb.dbo.backupmediafamily mf ON mf.media_set_id = b.media_set_id
WHERE b.database_name='NAV-LIVE' AND b.type IN ('D','I')
  AND b.backup_finish_date > DATEADD(DAY,-30,GETDATE())
ORDER BY b.backup_finish_date DESC;
```

Prázdný výsledek pro typ `I` = **diff zálohy nevznikají** → nález sám o sobě.

### B3 — Disky

```sql
EXEC master..xp_fixeddrives;
```

Fyzické rozložení svazků nutno ověřit mimo SQL — na úrovni VMware / diskového pole.

### B4 — Skutečné objemy podle hodin a dnů

```sql
SELECT CAST(backup_finish_date AS date) AS den, type, COUNT(*) AS poc,
       CAST(SUM(backup_size)/1024.0/1024/1024 AS decimal(10,1)) AS raw_gb,
       CAST(SUM(compressed_backup_size)/1024.0/1024/1024 AS decimal(10,1)) AS na_disku_gb
FROM msdb.dbo.backupset
WHERE database_name='NAV-LIVE' AND backup_finish_date > DATEADD(DAY,-14,GETDATE())
GROUP BY CAST(backup_finish_date AS date), type
ORDER BY den DESC, type;
```

### B5 — Co běží v noci

```sql
SELECT LEFT(j.name,45) AS job,
       msdb.dbo.agent_datetime(h.run_date,h.run_time) AS start_,
       STUFF(STUFF(RIGHT('000000'+CAST(h.run_duration AS varchar(6)),6),5,0,':'),3,0,':') AS trvani
FROM msdb.dbo.sysjobhistory h
JOIN msdb.dbo.sysjobs j ON j.job_id = h.job_id
WHERE h.step_id = 0
  AND h.run_time BETWEEN 200000 AND 235959
  AND h.run_date >= CONVERT(int, CONVERT(varchar(8), DATEADD(DAY,-7,GETDATE()), 112))
ORDER BY start_ DESC;
```

Doplnit dotazem na job queue v samotném BC — noční provoz nemusí být v SQL Agentu.

### B6 — Edice a IFI

```sql
SELECT SERVERPROPERTY('Edition') AS edice,
       SERVERPROPERTY('ProductVersion') AS verze,
       SERVERPROPERTY('ProductLevel') AS uroven;

SELECT servicename, service_account, instant_file_initialization_enabled
FROM sys.dm_server_services;
```

### B7 — Přesný počet chyb v exportu

```powershell
Get-ChildItem C:\Users\trnkam\Downloads\itdashboard-events-*filtered.csv |
  ForEach-Object { Import-Csv $_.FullName -Delimiter ';' } |
  Group-Object 'Event ID' | Sort-Object Count -Descending |
  Format-Table Count, Name -AutoSize
```

Pro rozsah incidentu je ale nutný **nový export bez limitu řádků**, za okno 20:00–06:00.

---

## Příloha C — Chronologie šetření 2026-08-10

| Čas | Co se zjistilo | Jak |
|---|---|---|
| ~09:15 | Export Event Logu z NAV-01: výkonnostní varování, nula chyb | CSV |
| ~09:30 | Export z SQL-01: dávka 9002 | CSV |
| ~09:40 | Repo ITDashboard čisté, deploy v pořádku — nesouvisí | git, gh |
| ~09:45 | `Tlog` = 05:30–15:46, chybí sobota | GUI |
| ~09:50 | `Tlog2` = jen sobota → není redundantní | GUI |
| ~09:52 | `shrink_log` = `SHRINKFILE(...,10)`, neděle 5:00 | GUI |
| ~09:55 | `shrink_log` vypnut | operátor |
| ~09:58 | `date_modified` = 2025-01-10 → oprava z 23. 7. **nikdy nenasazena** | `msdb` |
| ~09:58 | Pokus o změnu schedule přes GUI **se neuložil** | `msdb` |
| ~10:05 | Zadavatel doplnil původní logiku návrhu (data od lidí v pracovní době) | rozhovor |
| ~10:12 | Návrh v1 | dokument |
| ~10:30 | Návrh v2 | dokument |
| — | **Fáze 1 stále nenasazena** | — |

Poslední řádek je podstatný: **v době psaní této oponentury je systém ve stejném stavu jako v okamžiku incidentu.**

---

## Příloha D — Kontrolní otázky pro nezávislého recenzenta

Pokud návrh i oponenturu bude číst někdo třetí, tohle jsou otázky, na kterých by se měl zastavit:

1. Je diagnóza „log backup = jediný mechanismus uvolnění logu ve FULL recovery" správná? *(oponent tvrdí ano, je to základ všeho ostatního)*
2. Dá se obhájit, že se něco mění na produkci na základě jednodenního pozorování?
3. Je log shipping pro firmu této velikosti přiměřený, nebo přestřelený?
4. Je přijatelné, že kompletní firemní data leží den stará na testovacím serveru bez dalších opatření?
5. Je RPO 15 minut dost, nebo je pro firmu i patnáctiminutová ztráta zadaných dat vážný problém?
6. Kdo v této firmě rozhoduje o tom, kolik smí obnova stát?
7. Není celý návrh příliš zaměřený na SQL a málo na to, co znamená „firma zase funguje"?

---

## Příloha E — Slovníček

| Pojem | Význam |
|---|---|
| **RPO** | kolik práce se ztratí při havárii |
| **RTO** | jak dlouho trvá obnovení provozu |
| **Log chain** | nepřerušená řada log záloh; bez ní není obnova k času |
| **Diff base** | full záloha, od které se počítají diferenciální zálohy |
| **`COPY_ONLY`** | záloha, která neovlivní řetěz — pro zálohy mimo plán |
| **Tail-log backup** | záloha konce logu po havárii |
| **`STOPAT`** | okamžik, ke kterému se obnovuje |
| **VLF** | vnitřní části transakčního logu |
| **IFI** | Instant File Initialization |
| **Log shipping** | automatické přehrávání log záloh na záložní server |
| **Basic AG** | omezená Availability Group ve Standard edici |
| **Bus factor** | kolik lidí musí vypadnout, aby se znalost ztratila |
| **9002** | chyba „transakční log je plný" |

---

*Konec oponentury. Dokument je určen k rozporování — nesouhlas s kteroukoli částí je vítaný a má být zaznamenán jako reakce.*
