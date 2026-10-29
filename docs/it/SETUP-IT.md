# Setup manuale di uno stack LAMP+LAPP su Windows 11 con WSL2, Debian 13 o Ubuntu 24.04/26.04, servizi nativi e VS Code

> Ultimo aggiornamento: _29/10/2026_. Distribuzioni supportate: **Debian 13 (trixie)** (consigliata), **Ubuntu 24.04 (noble)** e **Ubuntu 26.04 (resolute)**.
>
> Verificata dalla CI: gli installer girano su un vero WSL2 e su macchine normali a ogni modifica e ogni settimana, e i risultati vengono confrontati con quanto scritto in questa pagina. Vedi [cosa verifica la CI](/tests/README.md).

Questa guida installa WSL2 e una distribuzione Linux su Windows 11 senza Microsoft Store, poi costruisce uno stack **LAMP+LAPP** multi-PHP con servizi _systemd_ nativi e ci collega Visual Studio Code. Ogni passaggio descritto qui è quello che fanno gli installer automatici ([win11.ps1](/install/win11.ps1) e [lamp-lapp-stack.sh](/install/lamp-lapp-stack.sh)): puoi seguirlo a mano, controllare cosa modificano gli script o rifare un singolo passaggio.

## Requisiti di sistema

1. **Windows 11**, aggiornato tramite Windows Update (funziona anche Windows 10 1903 o successivo)
2. 16 GB di RAM (32 GB consigliati se usi insieme molte versioni di PHP e i database)
3. Almeno 50 GB liberi su C:\\ per il disco virtuale di Linux
4. Un SSD, meglio se NVMe, come disco principale di Windows
5. Conoscenza di base del terminale Linux (`cd`, `cp`, `mv`, `sudo`, `nano`, ...)
6. Un PC **protetto da password**, con **BitLocker** e **TPM 2.0**: la home di Linux contiene codice sorgente, database e chiavi. Conta soprattutto se tratti dati per conto di altri.

Cosa ottieni:

| Componente | Versione | Origine |
|---|---|---|
| PHP (CLI + FPM) | 5.6, 7.0, 7.1, 7.2, 7.3, 7.4, 8.0, 8.1, 8.2, 8.3, 8.4, 8.5 | [sury](https://packages.sury.org/php/) |
| Apache | 2.4 | distribuzione |
| MariaDB | 11.8 LTS | Debian 13 e Ubuntu 26.04 stesse; [mariadb.org](https://mariadb.org/download/) su Ubuntu 24.04 (che include la 10.11) |
| PostgreSQL | 18 | [pgdg](https://wiki.postgresql.org/wiki/Apt) |
| Redis | distribuzione | distribuzione |
| Composer | 2 e 1 | [getcomposer.org](https://getcomposer.org/download/), con verifica del checksum |
| Siti locali | `gash hte` | [Gash](https://github.com/mauriziofonte/gash) |
| Shell | Bash con Gash (predefinita), Bash con fzf/zoxide/starship, Zsh, Fish, oppure Bash semplice | vedi la [sezione 6](#6-la-tua-shell-gash-o-unalternativa) |
| Node | LTS tramite nvm | [nvm](https://github.com/nvm-sh/nvm) |

MariaDB 11.8 è una release a lungo termine: il progetto la mantiene fino a giugno 2028. Su Debian 13 e Ubuntu 26.04 è il pacchetto della distribuzione stessa, quindi riceve gli aggiornamenti di sicurezza della distribuzione per tutto il suo periodo di supporto.

I siti locali sono serviti da **`gash hte`**: Apache e un master PHP-FPM per ogni versione di PHP in uso, che girano con **il tuo utente** (nessun processo root), con HTTPS (certificati self-signed ECDSA da 10 anni), HTTP/2 e una versione di PHP per sito. Sostituisce la configurazione di Apache di sistema e lo strumento `hte-cli` delle versioni precedenti di questa guida.

## 1. Installare WSL

Apri **PowerShell come Amministratore** ed esegui:

```powershell
wsl --install --no-distribution
```

Il comando abilita il _Sottosistema Windows per Linux_ e la _Piattaforma macchina virtuale_ e installa il pacchetto WSL. **Riavvia il computer**, poi, sempre in una PowerShell da amministratore:

```powershell
wsl --update
wsl --set-default-version 2
wsl --version
```

`wsl --version` deve riportare WSL **2.0 o successivo**.

## 2. Configurare WSL lato Windows

WSL legge le impostazioni della sua macchina virtuale da `%UserProfile%\.wslconfig`. Senza quel file WSL può prendersi metà della RAM, e il disco virtuale di ogni distribuzione può crescere fino a 1 TB senza mai restituire spazio. L'installazione per Windows scrive il file al posto tuo (il suo passo 4) dalle risposte alle domande qui sotto. Se hai già un `.wslconfig`, ti mostra cosa cambierebbe e chiede prima; ogni riga che non imposta resta com'è, e accanto al file viene conservata una copia di backup.

**Risorse: tre profili calcolati sul tuo PC.** Leggero dà alla macchina virtuale un quarto della RAM e dei processori logici, Bilanciato (il predefinito) la metà, Prestazioni il 70% della RAM e il 75% dei processori. Windows tiene sempre per sé almeno 6 GB di RAM (la metà, su un PC con meno di 12 GB) e 2 processori logici. Il file di swap è metà della RAM della macchina virtuale, da 1 a 8 GB. Per esempio:

<!-- ci:profiles -->
| Questo PC: RAM installata (utilizzabile), processori logici | Leggero | Bilanciato | Prestazioni |
|---|---|---|---|
| 8 GB (7,6), 4 | 2 GB, 2 processori, 1 GB di swap | 4 GB, 2 processori, 2 GB di swap | 4 GB, 2 processori, 2 GB di swap |
| 16 GB (15,6), 8 | 4 GB, 2 processori, 2 GB di swap | 8 GB, 4 processori, 4 GB di swap | 9 GB, 6 processori, 4 GB di swap |
| 32 GB (31,4), 16 | 8 GB, 4 processori, 4 GB di swap | 16 GB, 8 processori, 8 GB di swap | 22 GB, 12 processori, 8 GB di swap |
| 64 GB (63,4), 32 | 16 GB, 8 processori, 8 GB di swap | 32 GB, 16 processori, 8 GB di swap | 44 GB, 24 processori, 8 GB di swap |

La RAM utilizzabile è quella che Windows può usare, un po' meno di quella installata. Se il tuo `.wslconfig` dimensiona già la macchina virtuale, una quarta scelta mantiene quei valori, ed è la predefinita.

**Rete: NAT o mirrored.** L'installazione spiega le due modalità e chiede; con un `.wslconfig` esistente propone la modalità già in uso.

| Modalità | Cosa significa | Quando sceglierla |
|---|---|---|
| NAT (il predefinito di WSL) | Linux ha una sua rete privata dietro Windows. Windows raggiunge i server Linux tramite `localhost`; gli altri computer della tua rete non li vedono | Sviluppi solo su questo PC. È anche il predefinito dell'installazione, e la scelta di `-Unattended` |
| Mirrored | Linux condivide le interfacce di rete di Windows: `localhost` funziona nei due sensi (Linux raggiunge un server in esecuzione su Windows a `127.0.0.1`), IPv6 funziona, le VPN funzionano meglio, e gli altri computer della tua rete possono raggiungere i server Linux se il firewall di Windows li lascia passare. Una porta già usata da Windows non è utilizzabile in Linux | Fai prove da un telefono o da un altro PC, lavori dietro una VPN, o ti serve IPv6. Richiede Windows 11 22H2 o successivo |

Con la rete mirrored l'installazione scrive anche `dnsTunneling`, `autoProxy` e `firewall` a `true` (i loro valori predefiniti), così il file dice per intero cosa è in vigore. La rete mirrored non funziona su ogni PC (alcune VPN, filtri DNS e macchine virtuali lasciano Linux senza DNS): installata la distribuzione, l'installazione controlla che risolva `github.com`, e se con la rete mirrored non ci riesce propone di passare `.wslconfig` a NAT (in modalità unattended passa da sola) e tiene la NAT solo se funziona.

**WSLg.** L'installazione chiede se usi applicazioni Linux con una finestra; se no, `guiApplications=false` risparmia la memoria della distribuzione di sistema di WSLg.

**Limite del disco.** L'installazione chiede se limitare lo spazio che la distribuzione può occupare, e propone circa metà dello spazio libero sul suo disco, arrotondata per difetto a 512, 256, 128 o 64 GB (puoi scrivere un'altra dimensione). Il limite vale per una distribuzione nuova tramite `wsl --install --vhd-size`, per una che hai già tramite `wsl --manage <distro> --resize` (mai sotto lo spazio che usa già), e per le distribuzioni che aggiungerai tramite `defaultVhdSize`. Entrambi i comandi richiedono WSL 2.5 o successivo. Quando un disco limitato si riempie, alza il limite:

```powershell
wsl --shutdown
wsl --manage Debian --resize 256GB
```

**Impostati sempre**: `maxCrashDumpCount=3` (WSL conserva 10 crash dump in modo predefinito), `sparseVhd=true` (un disco virtuale nuovo restituisce a Windows lo spazio che liberi in Linux; l'installazione lo scrive prima di creare la distribuzione) e `autoMemoryReclaim=dropCache` (la memoria che Linux usa solo come cache torna a Windows quando la macchina virtuale è inattiva).

Il file che l'installazione scrive per Bilanciato su un PC da 32 GB con 16 processori logici, NAT, senza WSLg e senza limite del disco; per farlo a mano, scrivilo tu:

<!-- ci:wslconfig -->
```ini
[wsl2]
# RAM della macchina virtuale di WSL
memory=16GB
# Processori logici della macchina virtuale di WSL
processors=8
# File di swap della macchina virtuale di WSL, sul disco di Windows
swap=8GB
# nat: una rete privata dietro Windows; mirrored: le interfacce di rete di Windows
networkingMode=nat
# WSLg: applicazioni Linux con una finestra
guiApplications=false
# Crash dump conservati in %Temp%\wsl-crashes
maxCrashDumpCount=3

[experimental]
# I dischi virtuali nuovi sono sparse: lo spazio liberato in Linux torna a Windows
sparseVhd=true
# Restituisce a Windows la memoria di cache quando la VM è inattiva
autoMemoryReclaim=dropCache
```

Le impostazioni valgono dal successivo avvio di WSL: esegui `wsl --shutdown` dopo aver modificato il file (l'installazione lo fa al posto tuo, e chiede prima se una distribuzione è in esecuzione). Con Gash installato, `gash wsl config` mostra ogni impostazione in vigore e da dove viene (sezione 7).

## 3. Installare la distribuzione

```powershell
wsl --list --online
wsl --install -d Debian          # oppure: Ubuntu-24.04, Ubuntu-26.04
```

Quando richiesto, scegli **nome utente** e **password** di Linux: la password è quella di `sudo`. Quando compare il prompt di Linux, hai finito.

> Tutte le distribuzioni WSL2 condividono **un'unica rete**. Se hai già uno stack LAMP in un'altra distribuzione, le sue porte (80, 443, 3306, 5432, 6379) risultano occupate anche per la nuova: prima ferma quei servizi nell'altra distribuzione (`sudo systemctl stop apache2 mariadb postgresql redis-server`). L'installer lo verifica e si ferma con un messaggio chiaro.

## 4. Eseguire l'installer dello stack

Dentro la distribuzione, con il tuo utente normale. L'immagine Debian di WSL non include `curl`, quindi su Debian installalo prima: `sudo apt-get update && sudo apt-get install -y curl`.

```bash
curl -fsSL https://wsl.mauriziofonte.it/lamp | bash
```

Le opzioni vanno dopo `bash -s --`, per esempio `... | bash -s -- --yes --php "8.4 8.3 7.4" --shell fish`:

| Opzione | Effetto |
|---|---|
| `-y`, `--yes` | Nessuna domanda, usa i valori predefiniti |
| `--php "X.Y ..."` | Versioni di PHP da installare (predefinito: tutte, dalla 5.6 alla 8.5) |
| `--pg N` | Versione major di PostgreSQL (predefinito: 18) |
| `--shell gash\|bash-plus\|zsh\|fish\|bash` | La tua shell interattiva: Bash con Gash (predefinita), Bash con fzf/zoxide/starship, una Zsh minimale, Fish, oppure la Bash della distribuzione così com'è (vedi la [sezione 6](#6-la-tua-shell-gash-o-unalternativa)). Chiesta se non indicata, su un terminale senza `--yes` |
| `--no-gash` | Non installa Gash (e quindi nemmeno `gash hte`); implica `--shell bash` |
| `--no-hte` | Installa Gash ma non configura `gash hte` |
| `--hte-ports standard\|high` | Porte dei siti locali: 80/443 (predefinito) oppure porte alte (8080/8443) |
| `--no-node` | Non installa nvm e Node |
| `--wsl`, `--no-wsl` | Forza o salta l'ottimizzazione per WSL (predefinito: rilevata in automatico) |
| `--tmp-size SIZE` | Dimensione massima di `/tmp` su WSL, per esempio `6G` o `25%` (predefinito: `25%`) |
| `--wsl-init-timeout MS` | Quanto WSL attende l'avvio di systemd, in millisecondi, da 1000 a 600000 (predefinito: 30000, oppure il valore già presente in `/etc/wsl.conf`) |
| `--wsl-append-windows-path true\|false` | Se WSL mette le cartelle di Windows nel `PATH` di Linux (predefinito: lasciato com'è, cioè `true`) |

L'installer **converge**: ogni passaggio controlla lo stato attuale e modifica solo ciò che è diverso. Se si ferma (errore di rete, porta occupata), risolvi la causa ed **eseguilo di nuovo**. Il log completo di ogni esecuzione viene salvato in `~/.local/state/lamp-lapp-stack/`.

Alla fine, se segnala che le impostazioni di WSL sono cambiate, esegui `wsl --terminate Debian` (o `Ubuntu-24.04`, `Ubuntu-26.04`) da PowerShell e riapri il terminale.

Le sezioni seguenti descrivono cosa fa ogni passaggio.

### 4.1 Ottimizzazione per WSL

Applicata solo su WSL:

| Modifica | Perché |
|---|---|
| `/etc/wsl.conf`: `[boot] systemd=true` | I servizi girano come unit systemd |
| `/etc/wsl.conf`: `[automount] mountFsTab=false` | WSL eseguirebbe `mount -a` prima che esista `/mnt/c`; è systemd a montare `/etc/fstab` |
| `/etc/wsl.conf`: `[user] default=<tuo utente>` | Il terminale si apre con il tuo utente |
| `/etc/wsl.conf`: `[boot] initTimeout=30000` | WSL attende systemd per 10 secondi in modo predefinito: un primo avvio lento (un controllo del file system, una lunga pulizia di `/tmp`) perde allora la sessione. Un valore già presente nel file viene mantenuto; `--wsl-init-timeout` ne imposta un altro |
| `/etc/wsl.conf`: `[interop] appendWindowsPath`, solo con `--wsl-append-windows-path` | `false` tiene le cartelle di Windows fuori dal `PATH` di Linux: la ricerca dei comandi e il completamento diventano più veloci, e gli strumenti Linux non scelgono mai per errore un programma Windows. I programmi Windows richiedono allora il percorso completo (`/mnt/c/Windows/explorer.exe`); Gash li chiama con il percorso completo, quindi `gash win` continua a funzionare |
| `/tmp` su tmpfs, con il limite di `--tmp-size` | Un `/tmp` su disco viene svuotato a ogni avvio e rallenta il boot di WSL; i file temporanei grandi vanno in `/var/tmp` |
| `fstrim.timer` attivo, con un drop-in che azzera `ConditionVirtualization` | systemd considera WSL un container e non eseguirebbe mai il TRIM: senza, un disco virtuale sparse non restituisce mai spazio |
| `getty@tty1.service` mascherato | WSL non ha tty1: la unit fallisce soltanto e segna il sistema come "degraded" |

L'installer imposta solo queste chiavi in `/etc/wsl.conf` e lascia il resto del file com'è. **Non** modifica le impostazioni DNS.

### 4.2 Repository

Debian 13 e Ubuntu (il codename è `trixie` su Debian 13, `noble` su Ubuntu 24.04, `resolute` su Ubuntu 26.04):

<!-- ci:run repositories -->
```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl lsb-release postgresql-common
curl -fsSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
sudo dpkg -i /tmp/debsuryorg-archive-keyring.deb
echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php.list
sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
sudo apt-get update
```

Ubuntu 24.04 include MariaDB 10.11, quindi serve anche il repository di mariadb.org:

<!-- ci:run mariadb-repository -->
```bash
curl -fsSL https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash -s -- --mariadb-server-version=mariadb-11.8 --skip-maxscale --skip-tools
sudo apt-get update
```

La `ppa:ondrej/php` usata dalle versioni precedenti di questa guida sta confluendo in packages.sury.org, e Ubuntu 26.04 è servita solo lì. Se la tua Ubuntu usa già la PPA, l'installer la mantiene e non aggiunge sury, così gli stessi pacchetti non arrivano mai da due sorgenti.

### 4.3 Pacchetti

Per ogni versione di PHP `X.Y` l'installer aggiunge `phpX.Y-` + `cli fpm bcmath bz2 curl gd gmp igbinary imagick imap intl mbstring mcrypt memcached msgpack mysql opcache pgsql readline redis soap sqlite3 xml xsl zip` (PHP 8.5 include già opcache). A mano, per PHP 8.5 e 8.4:

<!-- ci:run php-packages -->
```bash
sudo apt-get install -y php8.5-{cli,fpm,bcmath,bz2,curl,gd,gmp,igbinary,imagick,imap,intl,mbstring,mcrypt,memcached,msgpack,mysql,pgsql,readline,redis,soap,sqlite3,xml,xsl,zip}
sudo apt-get install -y php8.4-{cli,fpm,bcmath,bz2,curl,gd,gmp,igbinary,imagick,imap,intl,mbstring,mcrypt,memcached,msgpack,mysql,opcache,pgsql,readline,redis,soap,sqlite3,xml,xsl,zip}
```

Poi i server:

<!-- ci:run stack-packages -->
```bash
sudo apt-get install -y apache2 mariadb-server mariadb-client postgresql-18 postgresql-client-18 redis-server
sudo update-alternatives --set php /usr/bin/php8.5
sudo systemctl enable --now redis-server mariadb postgresql
```

La versione di PHP più recente diventa il `php` predefinito.

### 4.4 MariaDB

L'installer scrive `/etc/mysql/mariadb.conf.d/99-custom.cnf` (impostazioni da sviluppo: `utf8mb4` con `utf8mb4_unicode_ci`, buffer pool InnoDB da 1 GB, niente binary log, `NO_ENGINE_SUBSTITUTION`, ascolto solo su 127.0.0.1). Metti le tue modifiche in un file che viene ordinato dopo, per esempio `99-zz-local.cnf`: rieseguire l'installer riscrive `99-custom.cnf`.

| Account | Accesso | Password |
|---|---|---|
| `root` | `sudo mariadb` (socket unix) | nessuna |
| `default` (tutti i privilegi, per le tue applicazioni) | `mariadb -u default -p`, oppure 127.0.0.1:3306 | in `~/.mysql-pass` |

Gli utenti anonimi e il database `test` vengono rimossi.

### 4.5 PostgreSQL

| Ruolo | Accesso | Password |
|---|---|---|
| `postgres` | `sudo -u postgres psql` | nessuna (peer) |
| il tuo nome utente (superuser, con un database omonimo) | `psql` | nessuna (peer) |
| `default` (superuser, proprietario di `defaultdb`) | `psql -h 127.0.0.1 -U default defaultdb` | in `~/.pgsql-pass` |

`default` è una parola riservata in SQL: nelle tue query scrivila sempre tra virgolette (`"default"`). PostgreSQL ascolta solo su localhost.

### 4.6 Composer

`composer` (2.x) e `composer1` (1.x, per i progetti legacy) vengono scaricati in `/usr/local/bin` e verificati con lo SHA-256 pubblicato. Composer 1 non supporta le versioni recenti di PHP (con PHP 8.4 e successivi stampa avvisi di deprecazione): usalo con un PHP vecchio, per esempio `1composer72`, l'alias di Gash per `php7.2 /usr/local/bin/composer1`.

### 4.7 Gash e `gash hte`

[Gash](https://github.com/mauriziofonte/gash) è un toolkit per Bash: un prompt, funzioni per file, git, database, versioni di PHP, WSL e Windows, e il gestore di siti locali `gash hte`. L'installer esegue l'[installer di Gash](https://github.com/mauriziofonte/gash/blob/main/docs/install.md), che verifica lo SHA-256 del binario di Gash con l'hash fissato dalla sua release, poi:

```bash
gash hte install --yes --ports standard
```

Questo comando usa `sudo` una sola volta per: installare un piccolo helper per `/etc/hosts`, permettere al tuo utente di usare le porte 80 e 443 (`net.ipv4.ip_unprivileged_port_start = 80`), fermare e disabilitare l'Apache di sistema, attivare una unit systemd **utente** (`gash-hte.service`) che avvia lo stack al boot. Dato che `gash hte` usa i propri master Apache e PHP-FPM, l'installer poi disabilita i servizi `phpX.Y-fpm` di sistema, e anche l'Apache di sistema se hai scelto le porte alte (lì `gash hte` non lo tocca): occuperebbero solo memoria (circa 70 MB per versione di PHP).

Con `--shell gash` (il predefinito) le shell Bash interattive caricano Gash, che definisce anche `php85` ... `php56`, `composer85` ... `composer56`, `1composer72` ... `1composer56` e `composer-self-update`. Con ogni altra `--shell` Gash non tocca la tua shell e viene installato solo il comando `gash` (in `~/.local/bin`), quindi `gash hte` funziona allo stesso modo.

### 4.8 nvm e Node

nvm viene installato con il suo script ufficiale, poi `nvm install --lts`.

## 5. Il tuo primo sito locale

<!-- ci:run first-site -->
```bash
mkdir -p ~/sites/shop/public && echo '<?php echo "PHP ", PHP_VERSION, PHP_EOL;' > ~/sites/shop/public/index.php
cd ~/sites/shop
gash hte site create --domain shop.test --docroot public --php 8.4
curl -k https://shop.test/
```

L'ultimo comando stampa `PHP 8.4.x`. Dentro Linux, `gash hte` gestisce i nomi in `/etc/hosts`. Windows ha un proprio file hosts: `gash hte hosts windows` stampa le righe da aggiungere a `C:\Windows\System32\drivers\etc\hosts`, solo per i nomi che Windows non risolve ancora (quindi non stampa nulla quando ci sono già). Aggiungile come Amministratore, oppure dal terminale Linux con `gash win fix hosts-add 127.0.0.1 shop.test`, che mostra il comando e chiede la conferma UAC di Windows. Poi apri `https://shop.test/` nel browser di Windows: WSL inoltra il localhost di Windows a Linux, e il browser avvisa del certificato self-signed.

![Il primo sito locale in Debian, poi Windows lo apre dopo una riga nel suo file hosts](/docs/media/first-site.gif)

Comandi utili: `gash hte site list`, `gash hte site modify --domain shop.test --php 7.4`, `gash hte site remove --domain shop.test --yes`, `gash hte doctor`. Vedi la [guida di gash hte](https://github.com/mauriziofonte/gash/blob/main/docs/hte/README.md).

## 6. La tua shell: Gash o un'alternativa

L'installer configura **Bash con Gash**, a meno che tu non scelga diversamente con `--shell` (o `-Shell` nell'installazione per Windows). È la scelta consigliata per questo stack, perché Gash nasce attorno agli stessi compiti:

* siti locali in HTTPS con `gash hte` (sezione 5);
* un comando per ogni versione di PHP (`php84`, `composer84`, `1composer72`) e `php_detect_version`, che legge la versione richiesta da un progetto in `composer.json` o `.target-php-version`;
* WSL e Windows dal terminale Linux (sezione 7);
* un prompt che conosce git e funzioni per dischi, porte, database, Docker e server, ognuna con `--help`;
* funzioni `llm_*` in sola lettura, con output JSON, per gli agenti AI di programmazione.

Gash è open source, si installa nella tua home, e prompt, alias e impostazioni di sicurezza si possono disattivare uno per uno. La sua [documentazione](https://github.com/mauriziofonte/gash/blob/main/docs/README.md) copre ogni area.

Le alternative:

| Scelta | Opzione dell'installer | Cosa ottieni | Cosa cambia |
|---|---|---|---|
| **Bash con Gash** (consigliata) | `--shell gash` (predefinita) | Tutto quanto sopra | Gash aggiunge un blocco a `~/.bashrc` |
| Bash con fzf, zoxide e starship | `--shell bash-plus` | Ricerca fuzzy nella cronologia e nei file ([fzf](https://github.com/junegunn/fzf): `Ctrl-R`, `Ctrl-T`, `Alt-C`), `z <parte di un percorso>` per saltare nelle cartelle che usi ([zoxide](https://github.com/ajeetdsouza/zoxide)), il prompt [starship](https://starship.rs/), 100000 righe di cronologia condivise dai tuoi terminali, completamento senza distinzione tra maiuscole e minuscole | Un blocco in `~/.bashrc` e un `~/.inputrc`. starship arriva dalla distribuzione dove è pacchettizzato; su Ubuntu 24.04, da una release fissa di cui l'installer verifica lo SHA-256 |
| Zsh, minimale | `--shell zsh` | Zsh come shell di login, con suggerimenti automatici ed evidenziazione della sintassi, fzf, zoxide e starship, nvm e il comando `gash` | Un blocco in `~/.zshrc`. I plugin sono pacchetti della distribuzione, quindi `apt-get upgrade` li aggiorna |
| Fish | `--shell fish` | [Fish](https://fishshell.com/) in ogni terminale: suggerimenti ed evidenziazione integrati, fzf, zoxide e starship, il comando `gash`, e un comando `nvm` che esegue nvm tramite Bash | Bash resta la tua shell di login, e una Bash interattiva avviata da un terminale passa la mano a fish. Gli script, `bash -c`, VS Code e `sudo` continuano a usare Bash. Fish non è una shell POSIX: esegui i frammenti Bash con `bash` |
| Bash semplice | `--shell bash` | La Bash della distribuzione così com'è, con il comando `gash` in `~/.local/bin` | Niente nei file della tua shell |
| Nessun Gash | `--no-gash` | Nessun comando `gash` | Niente `gash hte`: servi i tuoi siti con l'Apache di sistema (attivato dal suo pacchetto) e modifica tu i suoi virtual host |

Con ogni scelta tranne Gash, le funzioni e gli alias di Gash non vengono caricati: usa `php8.4` e `gash run --runtime php:8.4 -- composer install` al posto di `php84` e `composer84`. Il comando `gash`, e con lui `gash hte`, funziona da ogni shell.

Perché niente Oh My Zsh? Carica un framework di centinaia di file a ogni nuovo terminale e si aggiorna da solo da internet, mentre i due plugin che contano nel lavoro di ogni giorno, suggerimenti automatici ed evidenziazione della sintassi, sono pacchettizzati da Debian e Ubuntu e ricevono gli aggiornamenti di sicurezza insieme al resto del sistema. Le versioni precedenti di questa installazione installavano Oh My Zsh: l'installer lascia stare un `~/.oh-my-zsh` esistente. Per tenere solo la configurazione minimale, cancella `~/.oh-my-zsh` e le righe di Oh My Zsh in `~/.zshrc`.

Cambiare idea è sicuro: esegui di nuovo l'installer con un'altra `--shell`. Configura la nuova shell, toglie i blocchi che aveva scritto per la precedente (e il blocco di Gash in `~/.bashrc` quando lasci Gash: Gash resta installato), e cambia la shell di login dove serve.

## 7. Gash su WSL: Windows dal terminale Linux

Gash legge Windows e WSL da dentro la distribuzione, e modifica Windows solo tramite una richiesta UAC che confermi tu. I comandi `gash` funzionano con qualsiasi scelta di shell:

```bash
gash wsl doctor        # interop, PATH di Windows, unità, rete, systemd: ogni problema con il suo rimedio
gash wsl config        # le impostazioni in vigore, da /etc/wsl.conf e dal tuo .wslconfig
gash wsl path 'C:\Users\me\Downloads'   # /mnt/c/Users/me/Downloads, e al contrario con --windows
gash win doctor        # Windows: versione, riavvio in sospeso, Defender, spazio libero
gash win fix hosts-add 127.0.0.1 shop.test   # il file hosts di Windows, tramite UAC
```

In Bash con Gash hai anche dei comandi brevi: `wex` apre Esplora file nella cartella corrente, `wtm` apre Gestione attività, `wr` riavvia WSL (chiede prima conferma) e `wslc` sistema i programmi Windows che vanno in timeout su una VM di WSL accesa da molto tempo. Vedi [Windows and WSL](https://github.com/mauriziofonte/gash/blob/main/docs/windows/README.md) nella documentazione di Gash.

## 8. Creare la tua chiave SSH

L'installer non crea chiavi SSH: una chiave è personale e deve avere una passphrase. Creane una con un **nome** che indichi a cosa serve e su quale macchina, protetta da una passphrase robusta:

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/id_ed25519_work_laptop -C "you@work-laptop"
```

Quando richiesto, digita la passphrase (una frase lunga si ricorda meglio di una parola breve e casuale). Condividi solo la chiave **pubblica** (`~/.ssh/id_ed25519_work_laptop.pub`), per esempio con il tuo server Git. Per usarla con un host, aggiungi a `~/.ssh/config`:

```text
Host git.example.com
    IdentityFile ~/.ssh/id_ed25519_work_laptop
    IdentitiesOnly yes
```

Per digitare la passphrase una sola volta per sessione, carica la chiave nell'agent: `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519_work_laptop`.

## 9. Collegamenti sul Desktop

L'installer automatico crea due collegamenti. A mano: tasto destro sul Desktop, `Nuovo` > `Collegamento`, e usa:

* Terminale: `C:\Windows\System32\wsl.exe -d Debian --cd ~`
* Cartella home: `\\wsl.localhost\Debian\home\NOMEUTENTE`

Sostituisci `Debian` con `Ubuntu-24.04` o `Ubuntu-26.04` se è la tua distribuzione, e `NOMEUTENTE` con il tuo nome utente Linux.

## 10. VS Code

1. Scarica VS Code da <https://code.visualstudio.com/> e installalo su Windows
2. Installa l'estensione **WSL** (`CTRL + SHIFT + x`, cerca "WSL")
3. Nel terminale Linux, entra nella cartella di un progetto ed esegui `code .`: VS Code installa il suo server in Linux e apre la cartella

Installa queste estensioni **mentre sei connesso a WSL** (in una finestra aperta con `code .`), così girano dentro Linux:

1. **php cs fixer** di junstyle
2. **GitLens** di GitKraken
3. **PHP Intelephense** di Ben Mewburn
4. **Prettier - Code formatter** di Prettier
5. **PHP DocBlocker** di Neil Brayfield
6. **markdownlint** di David Anson
7. **Material Icon Theme** di Philipp Kief

Poi `CTRL + SHIFT + p` > **Preferences: Open Remote Settings (JSON) (WSL: Debian)** e incolla [vscode.json](/confs/vscode.json). La configurazione usa il php-cs-fixer incluso nell'estensione e i font [Roboto Mono](https://fonts.google.com/specimen/Roboto+Mono) e [Source Code Pro](https://fonts.google.com/specimen/Source+Code+Pro): scaricali e installali su Windows.

## 11. Mantenere piccolo il disco virtuale

Con `sparseVhd=true` (sezione 2) e il timer del TRIM attivato dall'installer, lo spazio liberato in Linux torna a Windows entro una settimana. `sparseVhd` vale solo per i dischi virtuali nuovi; per convertire una distribuzione già esistente, da PowerShell:

```powershell
wsl --shutdown
wsl --manage Debian --set-sparse true
```

## 12. Tenere aggiornato lo stack

| Cosa | Come |
|---|---|
| PHP, Apache, MariaDB, PostgreSQL, Redis | `sudo apt-get update && sudo apt-get upgrade`: arrivano tutti da repository apt |
| Una nuova versione di questa installazione | Esegui di nuovo l'installer dello stack (sezione 4): aggiunge le novità e lascia il resto com'è |
| Composer | `composer-self-update` in Bash con Gash, oppure `sudo composer self-update` e `sudo composer1 self-update` |
| Gash | `gash update` (per tornare indietro: `gash update --rollback`) |
| Node | `nvm install --lts --reinstall-packages-from=current` |
| WSL | `wsl --update` da PowerShell |

## 13. Risoluzione dei problemi

| Sintomo | Cosa fare |
|---|---|
| L'installer dice `Ports already in use by something outside this system` | Un'altra distribuzione usa uno stack sulle stesse porte (condividono un'unica rete): ferma lì i suoi servizi, oppure fermala con `wsl --terminate <nome>`, poi esegui di nuovo l'installer |
| L'installer dice `systemd is not running yet` | Esegui `wsl --terminate <distro>` da PowerShell, riapri il terminale ed esegui di nuovo l'installer |
| L'installer si è fermato a metà | Risolvi la causa che indica ed eseguilo di nuovo. Log: `~/.local/state/lamp-lapp-stack/` in Linux, `%LOCALAPPDATA%\WSL2Setup` in Windows |
| Un sito risponde in Linux ma non nel browser di Windows | Windows non conosce il nome: `gash hte hosts windows`, poi aggiungi le righe al file hosts di Windows (sezione 5). `gash hte doctor` lo controlla |
| I siti non rispondono dopo `wsl --shutdown` | `gash hte doctor` indica la causa; `gash hte service start` avvia lo stack |
| `code .`, `explorer.exe` e gli altri programmi Windows non partono dentro `tmux` o `screen` | `eval "$(gash wsl interop --export)"` collega la shell a un socket di interop attivo |
| I programmi Windows vanno in timeout con `UtilAcceptVsock ... accept4 failed 110` | `wslc` in Bash con Gash, oppure `wsl --shutdown` da PowerShell |
| Il disco virtuale non si riduce | Controlla `sparseVhd=true` (sezione 2) e che `systemctl status fstrim.timer` lo mostri attivo |
| Il disco è pieno (`No space left on device`) e hai impostato un limite | Alza il limite con `wsl --manage <distro> --resize <dimensione>GB` (sezione 2) |
| L'installazione per Windows si ferma con `opzioni non valide, non è stato cambiato nulla` | Le righe sopra nominano ogni opzione sbagliata e i valori che accetta |
| Rete mirrored: un server Linux non parte perché la sua porta è occupata | Windows usa già quella porta: ferma il programma Windows, oppure scegli un'altra porta. Per tornare a NAT: `networkingMode=nat` in `.wslconfig`, poi `wsl --shutdown` |
| Rete mirrored: un altro computer non raggiunge un server Linux | Lo blocca il firewall di Windows: consenti quella porta in ingresso, oppure usa NAT e servi solo da questo PC |

## 14. Disinstallazione

```powershell
wsl --unregister Debian
```

Il comando elimina la distribuzione e **tutto il suo contenuto** (home, database). Se hai usato l'installer automatico e si è fermato a metà, rimuovi anche il suo stato: `Remove-Item -Path "HKCU:\Software\WSL2Setup" -Force`.

## Esclusione di responsabilità

Seguendo questa guida ti assumi la piena responsabilità delle modifiche apportate al tuo sistema. Né l'autore né i collaboratori rispondono di eventuali danni, compresa la perdita di dati. Questa configurazione è pensata per **macchine di sviluppo**: non usarla su un server di produzione.

## Licenza

Licenza MIT. Vedi [LICENSE](/LICENSE).
