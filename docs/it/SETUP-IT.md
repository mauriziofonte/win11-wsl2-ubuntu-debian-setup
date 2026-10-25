# Setup manuale di uno stack LAMP+LAPP su Windows 11 con WSL2, Debian 13 o Ubuntu 24.04/26.04, servizi nativi e VS Code

> Ultimo aggiornamento: _25/10/2026_. Distribuzioni supportate: **Debian 13 (trixie)** (consigliata), **Ubuntu 24.04 (noble)** e **Ubuntu 26.04 (resolute)**.

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
| MariaDB | 11.8 LTS (EOL 13/02/2030) | Debian 13 e Ubuntu 26.04 stesse; [mariadb.org](https://mariadb.org/download/) su Ubuntu 24.04 (che include la 10.11) |
| PostgreSQL | 18 | [pgdg](https://wiki.postgresql.org/wiki/Apt) |
| Redis | distribuzione | distribuzione |
| Composer | 2 e 1 | [getcomposer.org](https://getcomposer.org/download/), con verifica del checksum |
| Siti locali | `gash hte` | [Gash](https://github.com/mauriziofonte/gash) |
| Node | LTS tramite nvm | [nvm](https://github.com/nvm-sh/nvm) |

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

## 2. Configurare WSL lato Windows (facoltativo, consigliato)

WSL legge le impostazioni della VM da `%UserProfile%\.wslconfig`. Senza questo file WSL può arrivare a usare metà della RAM e il disco virtuale non si riduce mai. Un buon punto di partenza per una macchina da 32 GB:

```ini
[wsl2]
# RAM assegnata alla VM di WSL: lascia a Windows almeno un terzo del totale
memory=16GB
processors=8
swap=8GB
# Non avviare lo stack grafico WSLg se non usi applicazioni Linux con interfaccia grafica
guiApplications=false

[experimental]
# I nuovi dischi virtuali sono sparse: lo spazio liberato in Linux torna a Windows
sparseVhd=true
```

Dopo la modifica esegui `wsl --shutdown`: le impostazioni valgono dal successivo avvio di WSL.

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

Le opzioni vanno dopo `bash -s --`, per esempio `... | bash -s -- --yes --php "8.4 8.3 7.4"`:

| Opzione | Effetto |
|---|---|
| `-y`, `--yes` | Nessuna domanda, usa i valori predefiniti |
| `--php "X.Y ..."` | Versioni di PHP da installare (predefinito: tutte, dalla 5.6 alla 8.5) |
| `--pg N` | Versione major di PostgreSQL (predefinito: 18) |
| `--no-gash` | Non installa Gash (e quindi nemmeno `gash hte`) |
| `--no-hte` | Installa Gash ma non configura `gash hte` |
| `--hte-ports standard\|high` | Porte dei siti locali: 80/443 (predefinito) oppure porte alte |
| `--no-node` | Non installa nvm e Node |
| `--wsl`, `--no-wsl` | Forza o salta l'ottimizzazione per WSL (predefinito: rilevata in automatico) |
| `--tmp-size SIZE` | Dimensione massima di `/tmp` su WSL, per esempio `6G` o `25%` (predefinito: `25%`) |

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
| `/tmp` su tmpfs, con il limite di `--tmp-size` | Un `/tmp` su disco viene svuotato a ogni avvio e rallenta il boot di WSL; i file temporanei grandi vanno in `/var/tmp` |
| `fstrim.timer` attivo, con un drop-in che azzera `ConditionVirtualization` | systemd considera WSL un container e non eseguirebbe mai il TRIM: senza, un disco virtuale sparse non restituisce mai spazio |
| `getty@tty1.service` mascherato | WSL non ha tty1: la unit fallisce soltanto e segna il sistema come "degraded" |

L'installer imposta solo queste chiavi in `/etc/wsl.conf` e lascia il resto del file com'è. **Non** modifica le impostazioni DNS.

### 4.2 Repository

Debian 13 e Ubuntu (il codename è `trixie` su Debian 13, `noble` su Ubuntu 24.04, `resolute` su Ubuntu 26.04):

```bash
sudo apt-get install -y ca-certificates curl lsb-release postgresql-common
curl -fsSLo /tmp/debsuryorg-archive-keyring.deb https://packages.sury.org/debsuryorg-archive-keyring.deb
sudo dpkg -i /tmp/debsuryorg-archive-keyring.deb
echo "deb [signed-by=/usr/share/keyrings/debsuryorg-archive-keyring.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php.list
sudo /usr/share/postgresql-common/pgdg/apt.postgresql.org.sh -y
sudo apt-get update
```

Ubuntu 24.04 include MariaDB 10.11, quindi serve anche il repository di mariadb.org:

```bash
curl -fsSL https://r.mariadb.com/downloads/mariadb_repo_setup | sudo bash -s -- --mariadb-server-version=mariadb-11.8 --skip-maxscale --skip-tools
sudo apt-get update
```

La `ppa:ondrej/php` usata dalle versioni precedenti di questa guida sta confluendo in packages.sury.org, e Ubuntu 26.04 è servita solo lì. Se la tua Ubuntu usa già la PPA, l'installer la mantiene e non aggiunge sury, così gli stessi pacchetti non arrivano mai da due sorgenti.

### 4.3 Pacchetti

Per ogni versione di PHP `X.Y` l'installer aggiunge `phpX.Y-` + `cli fpm bcmath bz2 curl gd gmp igbinary imagick imap intl mbstring mcrypt memcached msgpack mysql opcache pgsql readline redis soap sqlite3 xml xsl zip` (PHP 8.5 include già opcache), poi:

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

`default` è una parola riservata in SQL: nelle tue query scrivila sempre tra virgolette (`"default"`).

### 4.6 Composer

`composer` (2.x) e `composer1` (1.x, per i progetti legacy) vengono scaricati in `/usr/local/bin` e verificati con lo SHA-256 pubblicato. Composer 1 non supporta le versioni recenti di PHP (con PHP 8.4 e successivi stampa avvisi di deprecazione): usalo con un PHP vecchio, per esempio `1composer72`, l'alias di Gash per `php7.2 /usr/local/bin/composer1`.

### 4.7 Gash e `gash hte`

[Gash](https://github.com/mauriziofonte/gash) è un ambiente Bash con prompt, funzioni di supporto e il gestore di siti locali `gash hte`. L'installer esegue l'installer di Gash, poi:

```bash
gash hte install --yes --ports standard
```

Questo comando usa `sudo` una sola volta per: installare un piccolo helper per `/etc/hosts`, permettere al tuo utente di usare le porte 80 e 443 (`net.ipv4.ip_unprivileged_port_start = 80`), fermare e disabilitare l'Apache di sistema, attivare una unit systemd **utente** (`gash-hte.service`) che avvia lo stack al boot. Dato che `gash hte` usa i propri master PHP-FPM, l'installer poi disabilita i servizi `phpX.Y-fpm` di sistema: occuperebbero solo memoria (circa 70 MB per versione).

Nelle shell interattive Gash definisce anche `php85` ... `php56`, `composer85` ... `composer56`, `1composer72` ... `1composer56` e `composer-self-update`.

### 4.8 nvm e Node

nvm viene installato con il suo script ufficiale, poi `nvm install --lts`.

## 5. Il tuo primo sito locale

```bash
mkdir -p ~/sites/shop/public && echo '<?php phpinfo();' > ~/sites/shop/public/index.php
cd ~/sites/shop
gash hte site create --domain shop.test --docroot public --php 8.4
curl -k https://shop.test/ | head
```

Dentro Linux, `gash hte` gestisce i nomi in `/etc/hosts`. Windows ha un proprio file hosts: `gash hte hosts windows` stampa le righe da aggiungere a `C:\Windows\System32\drivers\etc\hosts` (da modificare come Amministratore). Poi apri `https://shop.test/` nel browser di Windows.

Comandi utili: `gash hte site list`, `gash hte site modify --domain shop.test --php 7.4`, `gash hte site remove --domain shop.test --yes`, `gash hte doctor`. Vedi la [guida di gash hte](https://github.com/mauriziofonte/gash/blob/main/docs/hte.md).

## 6. Creare la tua chiave SSH

L'installer non crea chiavi SSH: una chiave è personale e deve avere una passphrase. Creane una con un **nome** che indichi a cosa serve e su quale macchina, protetta da una passphrase robusta:

```bash
ssh-keygen -t ed25519 -a 100 -f ~/.ssh/id_ed25519_lavoro_portatile -C "tu@portatile-lavoro"
```

Quando richiesto, digita la passphrase (una frase lunga si ricorda meglio di una parola breve e casuale). Condividi solo la chiave **pubblica** (`~/.ssh/id_ed25519_lavoro_portatile.pub`), per esempio con il tuo server Git. Per usarla con un host, aggiungi a `~/.ssh/config`:

```text
Host git.example.com
    IdentityFile ~/.ssh/id_ed25519_lavoro_portatile
    IdentitiesOnly yes
```

Per digitare la passphrase una sola volta per sessione, carica la chiave nell'agent: `eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519_lavoro_portatile`.

## 7. Collegamenti sul Desktop

L'installer automatico crea due collegamenti. A mano: tasto destro sul Desktop, `Nuovo` > `Collegamento`, e usa:

* Terminale: `C:\Windows\System32\wsl.exe -d Debian --cd ~`
* Cartella home: `\\wsl.localhost\Debian\home\NOMEUTENTE`

Sostituisci `Debian` con `Ubuntu-24.04` o `Ubuntu-26.04` se è la tua distribuzione, e `NOMEUTENTE` con il tuo nome utente Linux.

## 8. VS Code

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

Poi `CTRL + SHIFT + p` > **Preferences: Open Remote Settings (JSON) (WSL: Debian)** e incolla [vscode.json](/confs/vscode.json), sostituendo `##LINUX_USERNAME##` con il tuo nome utente Linux. La configurazione usa i font [Roboto](https://fonts.google.com/specimen/Roboto) e [Source Code Pro](https://fonts.google.com/specimen/Source+Code+Pro): scaricali e installali su Windows.

## 9. Mantenere piccolo il disco virtuale

Con `sparseVhd=true` (sezione 2) e il timer del TRIM attivato dall'installer, lo spazio liberato in Linux torna a Windows entro una settimana. Per convertire una distribuzione già esistente, da PowerShell:

```powershell
wsl --shutdown
wsl --manage Debian --set-sparse true
```

## 10. Disinstallazione

```powershell
wsl --unregister Debian
```

Il comando elimina la distribuzione e **tutto il suo contenuto** (home, database). Se hai usato l'installer automatico e si è fermato a metà, rimuovi anche il suo stato: `Remove-Item -Path "HKCU:\Software\WSL2Setup" -Force`.

## Esclusione di responsabilità

Seguendo questa guida ti assumi la piena responsabilità delle modifiche apportate al tuo sistema. Né l'autore né i collaboratori rispondono di eventuali danni, compresa la perdita di dati. Questa configurazione è pensata per **macchine di sviluppo**: non usarla su un server di produzione.

## Licenza

Licenza MIT. Vedi [LICENSE](/LICENSE).
