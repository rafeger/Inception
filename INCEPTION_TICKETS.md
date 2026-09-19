# Inception — Plan de travail complet (tickets + explications)

> **Fichier de travail personnel.** Chaque ticket contient : l'objectif, *pourquoi* on le fait
> (concept à comprendre), les étapes exactes, la vérification (Definition of Done), et
> **ce que je dois savoir expliquer en soutenance**.

---

## 0. Conventions de ce document

| Symbole | Sens |
|---|---|
| **OBJ** | Ce que le ticket produit |
| **POURQUOI** | Le concept à comprendre — la partie que le correcteur va te demander |
| **ÉTAPES** | À suivre à la lettre |
| **DoD** | Definition of Done : la commande qui prouve que c'est fait |
| **SOUTENANCE** | Les questions auxquelles tu dois savoir répondre sans hésiter |

### Variables à remplacer partout

| Placeholder | Valeur retenue ici | À vérifier |
|---|---|---|
| `LOGIN` | `rafeger` | ⚠️ **Confirme ton vrai login 42** avant de commencer. S'il diffère, remplace-le partout (domaine, `/home/LOGIN/data`, README). |
| Domaine | `rafeger.42.fr` | dérivé du login |
| Chemin data hôte | `/home/rafeger/data` | dérivé du login |
| Base des images | `debian:bookworm` | voir T02bis pour la vérification "avant-dernière stable" |

### Arborescence cible (à avoir à la fin)

```
inception/
├── Makefile
├── README.md
├── USER_DOC.md
├── DEV_DOC.md
├── .gitignore
├── secrets/                     ← ignoré par git
│   ├── credentials.txt
│   ├── db_password.txt
│   └── db_root_password.txt
└── srcs/
    ├── .env                     ← ignoré par git
    ├── .env.example             ← versionné (modèle sans secret)
    ├── docker-compose.yml
    └── requirements/
        ├── mariadb/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/50-server.cnf
        │   └── tools/entrypoint.sh
        ├── nginx/
        │   ├── Dockerfile
        │   ├── .dockerignore
        │   ├── conf/default.conf
        │   └── tools/           (vide — cf. T15)
        └── wordpress/
            ├── Dockerfile
            ├── .dockerignore
            ├── conf/www.conf
            └── tools/entrypoint.sh
```

### Schéma de l'infrastructure

```
                  HÔTE (la VM Debian)
                  ┌───────────────────────────────────────────────┐
  navigateur      │  port 443 publié  ─────► conteneur nginx      │
  https://        │                          (TLSv1.2/1.3)        │
  rafeger.42.fr   │                              │                │
                  │                   FastCGI    │  réseau bridge │
                  │                   :9000      ▼  "inception"   │
                  │                          conteneur wordpress  │
                  │                          (php-fpm + wp-cli)   │
                  │                              │                │
                  │                   MySQL      │                │
                  │                   :3306      ▼                │
                  │                          conteneur mariadb    │
                  └───────────────────────────────────────────────┘
                         │                              │
       volume nommé wordpress_data          volume nommé mariadb_data
       → /home/rafeger/data/wordpress       → /home/rafeger/data/mariadb
       (monté dans nginx ET wordpress)
```

**Point clé à retenir** : seul `nginx` publie un port vers l'extérieur (443). `wordpress` et
`mariadb` ne sont joignables que depuis l'intérieur du réseau Docker `inception`, par leur
**nom de service** (DNS interne fourni par Docker).

---

# PHASE 0 — Préparation de l'environnement

---

## T00 — Comprendre ce qu'on construit (30 min, aucun code)

**OBJ** : savoir redessiner le schéma ci-dessus de mémoire, au tableau, pendant la soutenance.

**POURQUOI** : tout le projet tient en une phrase — *un reverse-proxy TLS qui parle FastCGI à
un PHP-FPM, lequel parle MySQL à une base, le tout isolé dans un réseau Docker privé avec deux
stockages persistants*. Si tu comprends cette phrase, tu comprends le projet.

**ÉTAPES**

1. Lis (ou relis) le sujet en entier, une fois, sans rien coder.
2. Écris à la main, sur papier, la chaîne de requête complète :
   - le navigateur résout `rafeger.42.fr` → `127.0.0.1` (grâce à `/etc/hosts`) ;
   - il ouvre une connexion **TLS** sur le port **443** ;
   - `nginx` termine le TLS (déchiffre) ;
   - si l'URL finit par `.php`, nginx **ne l'exécute pas** : il transmet la demande en
     protocole **FastCGI** à `wordpress:9000` ;
   - `php-fpm` ouvre le fichier `.php` **sur le disque** (d'où le volume partagé), l'exécute ;
   - le code PHP de WordPress ouvre une connexion **MySQL** vers `mariadb:3306` ;
   - la réponse HTML remonte : php-fpm → nginx → TLS → navigateur.
3. Réponds par écrit à : *pourquoi nginx et wordpress doivent-ils partager le même volume ?*
   (Réponse : nginx sert les fichiers **statiques** — CSS, images, JS — lui-même, et pour les
   `.php` il envoie à php-fpm un chemin **absolu** via `SCRIPT_FILENAME` ; php-fpm doit pouvoir
   ouvrir ce chemin. Les deux conteneurs doivent donc voir la même arborescence.)

**DoD** : tu sais expliquer les 7 étapes de la requête sans regarder.

**SOUTENANCE**
- « Que fait nginx exactement ? » → terminaison TLS + service des fichiers statiques + passerelle FastCGI.
- « Pourquoi php-fpm et pas mod_php ? » → php-fpm est un process manager FastCGI indépendant du
  serveur web : il tourne dans **son propre conteneur** (un service = un conteneur), là où
  `mod_php` serait embarqué dans Apache, donc dans le même conteneur. Le sujet interdit
  explicitement d'avoir nginx dans le conteneur WordPress.

---

## T01 — Créer la machine virtuelle Debian

**OBJ** : une VM Debian fonctionnelle, avec un utilisateur nommé `rafeger`, sudo, et une connexion réseau.

**POURQUOI** : le sujet impose « *This project needs to be done on a Virtual Machine* ». Et le
nom d'utilisateur compte : le sujet exige que les volumes pointent vers `/home/LOGIN/data` **de
la machine hôte** — ici « hôte » = la VM.

**ÉTAPES**

1. Télécharge l'ISO **netinst** de Debian stable sur <https://www.debian.org/distrib/>.
2. Crée la VM. Tu es sur Fedora, donc le plus fluide est **virt-manager / GNOME Boxes** (KVM,
   virtualisation native). VirtualBox marche aussi si tu préfères.
   ```bash
   # côté hôte Fedora, si tu pars sur KVM
   sudo dnf install @virtualization virt-manager
   sudo systemctl enable --now libvirtd
   ```
3. Paramètres conseillés : **2 vCPU**, **4 Go de RAM**, **25 Go de disque**, réseau en NAT.
4. Pendant l'installation Debian :
   - pas d'environnement de bureau lourd nécessaire, mais **coche un bureau léger (XFCE)** :
     il te faut un navigateur graphique dans la VM pour montrer le site au correcteur ;
   - coche aussi « SSH server » et « standard system utilities » ;
   - **crée l'utilisateur `rafeger`** (nom d'utilisateur = ton login 42) ;
   - laisse le compte root activé, ou pas — mais assure-toi d'avoir sudo.
5. Après le premier démarrage, si `sudo` n'est pas configuré :
   ```bash
   su -
   apt update && apt install -y sudo
   usermod -aG sudo rafeger
   exit
   # puis se déconnecter / reconnecter pour que le groupe prenne effet
   ```
6. Mets à jour :
   ```bash
   sudo apt update && sudo apt upgrade -y
   sudo apt install -y git make curl vim
   ```

**DoD**
```bash
whoami          # → rafeger
echo $HOME      # → /home/rafeger
sudo -v         # ne renvoie pas d'erreur
```

**SOUTENANCE**
- « Différence VM vs conteneur ? » → une VM virtualise du **matériel** et fait tourner un
  **noyau complet** (via un hyperviseur) : isolation forte, démarrage en dizaines de secondes,
  des Go de RAM/disque. Un conteneur partage le **noyau de l'hôte** et n'isole que l'espace
  utilisateur via des fonctionnalités du noyau Linux (**namespaces** : PID, réseau, mount, UTS,
  IPC, user ; et **cgroups** pour limiter CPU/RAM). Résultat : démarrage en millisecondes,
  quelques Mo, mais isolation plus faible et **pas d'OS différent** (pas de conteneur Windows
  sur noyau Linux).
- « Pourquoi le sujet impose-t-il une VM alors ? » → parce que Docker manipule le noyau de
  l'hôte, monte des volumes dans `/home`, ouvre des ports privilégiés : on isole tout ça d'une
  machine de l'école, et on garantit un environnement reproductible pour la correction.

---

## T02 — Installer Docker Engine + le plugin Compose dans la VM

**OBJ** : `docker` et `docker compose` utilisables sans `sudo`.

**POURQUOI** : le paquet `docker.io` des dépôts Debian est souvent ancien et n'embarque pas le
plugin **Compose v2** (`docker compose`, sans tiret). On installe depuis le dépôt officiel.

**ÉTAPES** (dans la VM)

1. Dépendances et clé GPG du dépôt :
   ```bash
   sudo apt update
   sudo apt install -y ca-certificates curl gnupg
   sudo install -m 0755 -d /etc/apt/keyrings
   curl -fsSL https://download.docker.com/linux/debian/gpg \
     | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
   sudo chmod a+r /etc/apt/keyrings/docker.gpg
   ```
2. Ajout du dépôt :
   ```bash
   echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
   https://download.docker.com/linux/debian $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
     | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
   ```
3. Installation :
   ```bash
   sudo apt update
   sudo apt install -y docker-ce docker-ce-cli containerd.io \
                       docker-buildx-plugin docker-compose-plugin
   ```
4. Utiliser Docker sans sudo :
   ```bash
   sudo usermod -aG docker $USER
   # DÉCONNEXION / RECONNEXION obligatoire (ou : newgrp docker)
   ```
5. Démarrage automatique :
   ```bash
   sudo systemctl enable --now docker
   ```

**DoD**
```bash
docker --version          # Docker version 2x.x.x
docker compose version    # Docker Compose version v2.x.x
docker run --rm hello-world   # doit afficher "Hello from Docker!"
docker rmi hello-world        # on nettoie : image tierce, pas voulue dans le projet
```

**SOUTENANCE**
- « `docker-compose` ou `docker compose` ? » → v1 (Python, tiret) est **obsolète** ; v2 est un
  **plugin Go** de la CLI Docker, invoqué `docker compose`. C'est celui du projet.
- « Pourquoi le groupe `docker` est-il ≈ root ? » → le démon Docker tourne en root et expose un
  socket Unix ; qui peut parler à ce socket peut monter `/` dans un conteneur privilégié, donc
  devenir root sur l'hôte. À savoir, on ne te le demandera pas forcément, mais ça fait bonne
  impression.

---

## T02bis — Vérifier « l'avant-dernière version stable » de Debian

**OBJ** : justifier `FROM debian:bookworm` (et non `debian:latest`, interdit).

**POURQUOI** : le sujet impose de construire depuis **l'avant-dernière version stable** d'Alpine
ou de Debian, et **interdit le tag `latest`**. Un `latest` rend le build non reproductible : la
même commande produit une image différente dans six mois.

**ÉTAPES**

1. Ouvre <https://www.debian.org/releases/> et note :
   - la version **stable** actuelle (au moment où j'écris : Debian **13 « trixie »**) ;
   - la version **oldstable**, qui est donc l'avant-dernière stable : Debian **12 « bookworm »**.
2. Retiens le **nom de code**, pas le numéro : le tag Docker est `debian:bookworm`.
3. Vérifie ce que contient réellement l'image :
   ```bash
   docker run --rm debian:bookworm cat /etc/debian_version   # → 12.x
   docker run --rm debian:bookworm php --version 2>/dev/null || true
   ```
4. Note les versions des paquets que tu vas utiliser (c'est demandé en soutenance) :
   ```bash
   docker run --rm debian:bookworm sh -c \
     "apt-get update -qq && apt-cache policy nginx mariadb-server php-fpm"
   ```
   Attendu sous bookworm : **nginx 1.22**, **MariaDB 10.11**, **PHP 8.2**.

> ⚠️ **Si la liste des releases a changé depuis**, recalcule : oldstable = avant-dernière stable,
> et adapte le nom de code + la version de PHP (`php8.2-fpm` deviendrait `php8.3-fpm`, etc.)
> dans tous les Dockerfiles et le chemin `/etc/php/8.2/`.

**DoD** : tu sais dire « j'utilise `debian:bookworm`, c'est Debian 12, l'oldstable, donc
l'avant-dernière stable ; elle fournit PHP 8.2, MariaDB 10.11 et nginx 1.22 ».

**SOUTENANCE**
- « Pourquoi `latest` est-il interdit ? » → non reproductible, et il casse silencieusement un
  build qui marchait. Un tag figé = même image, même comportement, aujourd'hui et dans un an.

---

## T03 — Initialiser le dépôt et l'arborescence

**OBJ** : la structure de dossiers exacte attendue par le sujet.

**POURQUOI** : le sujet donne l'arborescence attendue. Le correcteur la regarde en premier.
`Makefile` **à la racine**, toute la configuration dans `srcs/`, un dossier par service dans
`srcs/requirements/`.

**ÉTAPES**

```bash
cd ~
mkdir -p inception && cd inception
git init

mkdir -p secrets
mkdir -p srcs/requirements/mariadb/{conf,tools}
mkdir -p srcs/requirements/nginx/{conf,tools}
mkdir -p srcs/requirements/wordpress/{conf,tools}

touch Makefile srcs/docker-compose.yml
touch srcs/requirements/{mariadb,nginx,wordpress}/Dockerfile
touch srcs/requirements/{mariadb,nginx,wordpress}/.dockerignore
```

**DoD**
```bash
find . -not -path './.git/*' | sort
```
→ compare avec l'arborescence cible en tête de document.

**SOUTENANCE**
- « Pourquoi un dossier par service ? » → chaque dossier est le **contexte de build** de son
  image : ce que Docker envoie au démon lors du `docker build`. Un contexte minimal = build
  rapide, et pas de risque d'embarquer les secrets ou le `.git` dans une image.

---

## T04 — `.gitignore` et politique de secrets

**OBJ** : garantir qu'**aucun mot de passe** n'entre jamais dans l'historique git.

**POURQUOI** : le sujet est sans appel — « *Any credentials, API keys, or passwords found in
your Git repository (outside of properly configured secrets) will result in project failure* ».
C'est la cause n°1 d'échec du projet. Et attention : un secret **commité puis supprimé** reste
dans l'historique git ; il compte toujours comme une fuite.

**ÉTAPES**

1. Crée `.gitignore` à la racine :
   ```gitignore
   # Secrets — ne doivent JAMAIS être versionnés
   secrets/
   srcs/.env

   # Données persistantes (elles sont hors du repo, mais au cas où)
   data/

   # Divers
   *.swp
   .DS_Store
   ```
2. Le `.env` sera ignoré, mais le correcteur doit comprendre quelles variables existent : on
   versionne un **modèle** `srcs/.env.example` (créé en T05) contenant les clés avec des valeurs
   factices.
3. Ajoute un `secrets/.gitkeep`… **non** : `secrets/` est entièrement ignoré, on documente à la
   place dans `DEV_DOC.md` comment le recréer (T25).

**DoD**
```bash
git add -A && git status --short
# secrets/ et srcs/.env ne doivent PAS apparaître
git check-ignore -v srcs/.env secrets/db_password.txt   # doit matcher .gitignore
```
Et avant chaque push :
```bash
git grep -nEi "password|passwd|secret" -- ':!*.md' ':!.gitignore'
```
→ aucune valeur de mot de passe en clair ne doit sortir (seulement des noms de variables).

**SOUTENANCE**
- « Secrets vs variables d'environnement ? » (c'est une question **explicitement demandée** dans
  le README, donc elle tombera) :
  - une variable d'environnement est **lisible** par `docker inspect`, par `/proc/<pid>/environ`,
    par tout processus du conteneur, et elle fuit dans les logs et les rapports de crash ;
  - un **secret Docker** est monté comme un **fichier en lecture seule** dans `/run/secrets/`,
    sur un **tmpfs** (en mémoire, jamais sur disque), lu explicitement par le processus qui en a
    besoin — il n'apparaît ni dans `docker inspect`, ni dans l'environnement ;
  - conclusion pratique : **configuration non sensible → `.env`** (domaine, nom de base, nom
    d'utilisateur) ; **secret → fichier dans `secrets/`**, jamais versionné.

---

# PHASE 1 — Configuration partagée

---

## T05 — Le fichier `srcs/.env`

**OBJ** : centraliser toute la configuration **non sensible** dans un seul fichier.

**POURQUOI** : le sujet l'impose (« *it is mandatory to use a `.env` file* »). Compose charge
automatiquement le fichier `.env` situé dans le **répertoire du projet**, c'est-à-dire le
dossier qui contient le `docker-compose.yml` — donc `srcs/.env`. Les `${VAR}` du
`docker-compose.yml` y sont substituées **avant** l'interprétation du YAML.

**ÉTAPES**

1. Crée `srcs/.env` :
   ```bash
   cat > srcs/.env << 'EOF'
   # ---------- Domaine & chemins hôte ----------
   DOMAIN_NAME=rafeger.42.fr
   DATA_PATH=/home/rafeger/data

   # ---------- MariaDB ----------
   MYSQL_DATABASE=wordpress
   MYSQL_USER=wpuser

   # ---------- WordPress ----------
   WP_VERSION=6.7.2
   WP_TITLE=Inception
   WP_DB_HOST=mariadb:3306

   # administrateur — le login NE DOIT PAS contenir admin/administrator
   WP_ADMIN_USER=rafeger
   WP_ADMIN_EMAIL=rafeger@student.42.fr

   # second utilisateur (non administrateur)
   WP_USER=visiteur
   WP_USER_EMAIL=visiteur@student.42.fr
   EOF
   ```
2. **Vérifie `WP_VERSION`** sur <https://wordpress.org/download/releases/> et mets une version
   qui existe réellement. Si tu préfères, tu peux retirer `WP_VERSION` et laisser wp-cli prendre
   la dernière — mais figer la version est plus propre et plus cohérent avec l'esprit du sujet.
3. Crée le modèle versionné :
   ```bash
   sed -E 's/=(.*)/=<a_remplir>/' srcs/.env | sed 's/^DOMAIN_NAME=.*/DOMAIN_NAME=login.42.fr/' \
     > srcs/.env.example
   ```
   (ou écris-le à la main, c'est plus lisible — l'important est qu'il liste **toutes** les clés.)

> ⚠️ **Il n'y a AUCUN mot de passe dans ce fichier.** Tous les mots de passe vont dans
> `secrets/` (T06). C'est un choix à assumer devant le correcteur.

**Règle du sujet à ne pas rater** : `WP_ADMIN_USER` ne doit contenir **ni** `admin`, `Admin`,
`administrator`, `Administrator`, **ni** sous forme de sous-chaîne (`admin-123` est refusé).
`rafeger` convient.

**DoD**
```bash
docker compose -f srcs/docker-compose.yml config | head -30
```
→ une fois le compose écrit (T17), cette commande affiche le YAML **après** substitution : tu
dois y voir `rafeger.42.fr` et non `${DOMAIN_NAME}`.

**SOUTENANCE**
- « Où Compose cherche-t-il le `.env` ? » → dans le répertoire du projet, par défaut celui du
  fichier compose. Comme on lance `docker compose -f srcs/docker-compose.yml`, c'est `srcs/`.
- « Différence entre le `.env` et la section `environment:` ? » → le `.env` alimente la
  **substitution de variables dans le fichier compose lui-même** (côté hôte, au moment du
  parsing) ; `environment:` définit les variables **à l'intérieur du conteneur**. Les deux sont
  distincts : une variable du `.env` n'atteint le conteneur que si on la passe explicitement
  via `environment:`.

---

## T06 — Les secrets

**OBJ** : trois fichiers dans `secrets/`, montés dans les conteneurs via le mécanisme
**Docker secrets**.

**POURQUOI** : le sujet « recommande fortement » les secrets Docker, et l'arborescence d'exemple
montre exactement ces trois fichiers. Compose v2 supporte les secrets **fichier** hors Swarm :
ils sont montés en lecture seule dans `/run/secrets/<nom_du_secret>`.

**ÉTAPES**

1. Crée les trois fichiers. **Utilise `printf` et non `echo`** :
   ```bash
   printf '%s' 'R00tP4ss_Inception' > secrets/db_root_password.txt
   printf '%s' 'WpUs3rP4ss_Inception' > secrets/db_password.txt
   cat > secrets/credentials.txt << 'EOF'
   WP_ADMIN_PASSWORD='Adm1nP4ss_Inception'
   WP_USER_PASSWORD='V1siteurP4ss_Inception'
   EOF
   chmod 600 secrets/*.txt
   ```
   > ⚠️ **Change ces valeurs.** Utilise des mots de passe alphanumériques + `_` (évite les
   > guillemets, `$`, `` ` ``, `\` : ils compliquent le parsing shell et YAML pour rien).

2. Pourquoi `printf` et pas `echo` : `echo` ajoute un **retour à la ligne** final. Le mot de
   passe stocké deviendrait `"R00tP4ss_Inception\n"` et l'authentification échouerait avec un
   message incompréhensible. Par sécurité, les entrypoints nettoieront quand même le `\n` avec
   `tr -d '\r\n'` — ceinture **et** bretelles.

3. `credentials.txt` est écrit en **format shell sourçable** (`CLE='valeur'`) : l'entrypoint
   WordPress fera simplement `. /run/secrets/credentials` et récupérera ses deux variables. Ça
   respecte le nom de fichier donné par le sujet tout en restant simple à expliquer.

4. Vérifie qu'ils sont bien ignorés :
   ```bash
   git status --short   # rien de secrets/ ne doit apparaître
   ```

**Mapping final** (à connaître par cœur) :

| Fichier hôte | Nom du secret Compose | Chemin dans le conteneur | Consommé par |
|---|---|---|---|
| `secrets/db_root_password.txt` | `db_root_password` | `/run/secrets/db_root_password` | mariadb |
| `secrets/db_password.txt` | `db_password` | `/run/secrets/db_password` | mariadb + wordpress |
| `secrets/credentials.txt` | `credentials` | `/run/secrets/credentials` | wordpress |

**DoD** (après T17)
```bash
docker exec -it mariadb ls -l /run/secrets/
docker exec -it mariadb cat /run/secrets/db_password | xxd | tail -2   # pas de 0a final
```

**SOUTENANCE**
- « Un secret Docker, c'est chiffré ? » → hors Swarm, **non** : le fichier est sur le disque de
  l'hôte, en clair. Ce que le mécanisme apporte ici : (1) le secret **n'est pas dans l'image**
  (donc pas dans une image qu'on pousserait par erreur), (2) il **n'est pas dans l'environnement**
  du conteneur (invisible à `docker inspect` et à `env`), (3) il est monté en **lecture seule**
  et n'est accessible qu'aux services qui le déclarent. En Swarm, il serait en plus chiffré au
  repos et en transit dans le raft. C'est la réponse honnête et complète.
- « Pourquoi pas de mot de passe dans le Dockerfile ? » → chaque instruction d'un Dockerfile est
  une **couche** de l'image, et les couches sont consultables (`docker history`, `docker save`).
  Un `ENV PASSWORD=...` ou un `RUN echo pass > f` reste lisible à vie, même si une couche
  ultérieure supprime le fichier.

---

## T07 — Faire pointer `rafeger.42.fr` sur la machine

**OBJ** : `https://rafeger.42.fr` doit atteindre la VM.

**POURQUOI** : le sujet impose le nom de domaine `login.42.fr` pointant vers l'IP locale. Et
nginx en a besoin : le `server_name` doit correspondre, et surtout le certificat TLS est émis
pour ce nom — sans lui, le navigateur affiche une erreur de nom en plus de l'erreur
d'auto-signature.

**ÉTAPES** (dans la VM)

```bash
grep -q 'rafeger.42.fr' /etc/hosts || \
  echo "127.0.0.1 rafeger.42.fr" | sudo tee -a /etc/hosts
```

**DoD**
```bash
getent hosts rafeger.42.fr     # → 127.0.0.1  rafeger.42.fr
ping -c1 rafeger.42.fr
```

**SOUTENANCE**
- « Comment ça marche ? » → `/etc/hosts` est consulté par le *resolver* de la glibc **avant** le
  DNS, selon l'ordre défini dans `/etc/nsswitch.conf` (`hosts: files dns`). On court-circuite
  donc toute résolution réseau.
- « Et le DNS entre conteneurs ? » → c'est un autre mécanisme, interne à Docker : sur un réseau
  **bridge défini par l'utilisateur**, le démon Docker fournit un résolveur DNS embarqué à
  `127.0.0.11` qui résout les **noms de services** (`mariadb`, `wordpress`) vers l'IP du
  conteneur. C'est exactement ce que `--link` faisait à l'ancienne, en mieux — d'où son
  interdiction.

---

## T08 — Créer les dossiers de données sur l'hôte

**OBJ** : `/home/rafeger/data/mariadb` et `/home/rafeger/data/wordpress` existent.

**POURQUOI** : les volumes nommés du projet sont créés avec `driver_opts: type=none, o=bind,
device=<chemin>` (T17). Le driver `local` exige que ce chemin **existe déjà** : sinon Docker
refuse de démarrer le conteneur avec `failed to mount local volume: no such file or directory`.
C'est pour ça que le Makefile crée ces dossiers avant tout `up`.

**ÉTAPES**

```bash
mkdir -p /home/rafeger/data/mariadb
mkdir -p /home/rafeger/data/wordpress
```
(Le Makefile le refera automatiquement — T18. On le fait une fois à la main pour vérifier.)

**DoD**
```bash
ls -ld /home/rafeger/data/*
```

**SOUTENANCE** — c'est la question piège du projet :
- « Volumes Docker vs bind mounts ? » (demandée explicitement dans le README)
  - un **bind mount** monte un chemin **arbitraire** de l'hôte dans le conteneur
    (`- /home/x/y:/var/lib/mysql`). Docker ne le gère pas : il n'apparaît pas dans
    `docker volume ls`, il n'est pas sauvegardable par l'API Docker, il dépend de l'arborescence
    de l'hôte, et il expose l'hôte (permissions, SELinux, chemins inexistants créés en root) ;
  - un **volume nommé** est un objet **géré par Docker** : créé, listé, inspecté, supprimé via
    l'API (`docker volume ...`), avec un cycle de vie propre, portable, sauvegardable.
  - **Le sujet impose des volumes nommés et interdit les bind mounts** — mais exige en même
    temps que les données soient dans `/home/login/data`. La réponse est le driver `local` avec
    `o=bind` : c'est un **volume nommé** (il apparaît dans `docker volume ls`, on le supprime
    avec `docker volume rm`, Compose le gère), dont on demande au driver de le **stocker** à un
    chemin précis. Ce n'est pas un bind mount : dans `services.*.volumes` on écrit
    `- mariadb_data:/var/lib/mysql`, c'est-à-dire **un nom de volume**, jamais un chemin hôte.
  - Sache montrer la différence à l'écran :
    ```bash
    docker volume ls                     # inception_mariadb_data est listé
    docker volume inspect inception_mariadb_data   # Mountpoint + Options
    ```

---

# PHASE 2 — Les trois services

> **Ordre imposé : MariaDB → WordPress → NGINX.** C'est l'ordre des dépendances. Tu dois pouvoir
> valider chaque service isolément avant de passer au suivant, sinon tu débogueras trois bugs
> imbriqués en même temps.

---

## T09 — Dockerfile MariaDB

**OBJ** : une image `mariadb:1.0` basée sur `debian:bookworm` qui contient MariaDB, sa config,
son entrypoint — et rien d'autre.

**POURQUOI** : trois principes de Dockerfile que le correcteur peut interroger : **une seule
couche `RUN` pour apt** (chaque instruction = une couche, et un `apt-get clean` dans une couche
suivante ne récupère pas l'espace de la précédente), **`--no-install-recommends`** (Debian
installe sinon des dizaines de paquets inutiles), et **la forme exec** pour `ENTRYPOINT`/`CMD`.

**ÉTAPES** — `srcs/requirements/mariadb/Dockerfile` :

```dockerfile
# Debian 12 "bookworm" = oldstable = avant-dernière version stable.
# Tag figé : le tag "latest" est interdit par le sujet et casse la reproductibilité.
FROM debian:bookworm

# Une seule couche : install + nettoyage du cache apt dans le MÊME RUN,
# sinon le cache reste stocké dans la couche précédente.
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        mariadb-server \
        mariadb-client && \
    rm -rf /var/lib/apt/lists/*

# Configuration serveur (écoute réseau, socket, datadir)
COPY conf/50-server.cnf /etc/mysql/mariadb.conf.d/50-server.cnf

# Script d'initialisation : crée la base au premier démarrage, puis exec le serveur
COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Purement documentaire : indique le port du service. N'ouvre RIEN vers l'hôte.
EXPOSE 3306

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["mysqld", "--user=mysql"]
```

Et `srcs/requirements/mariadb/.dockerignore` :
```
.dockerignore
*.md
```

**DoD**
```bash
docker build -t mariadb:1.0 srcs/requirements/mariadb
docker images mariadb
```

**SOUTENANCE**
- « `ENTRYPOINT` vs `CMD` ? » → `ENTRYPOINT` est **l'exécutable**, `CMD` fournit ses
  **arguments par défaut**. Ici l'entrypoint reçoit `mysqld --user=mysql` en `"$@"` et finit par
  `exec "$@"`. Avantage : on peut lancer `docker run mariadb:1.0 bash` pour déboguer — le `CMD`
  est remplacé, mais l'initialisation de l'entrypoint reste jouée.
- « Forme exec vs forme shell ? » → `CMD ["mysqld"]` (exec, en JSON) lance directement le binaire,
  qui devient **PID 1**. `CMD mysqld` (shell) lance en réalité `/bin/sh -c "mysqld"` : c'est
  **`sh` qui est PID 1**, il ne transmet pas les signaux, et `docker stop` finit par tuer le
  conteneur au bout de 10 s avec SIGKILL → base de données corrompue. Toujours la forme exec.
- « `EXPOSE`, ça ouvre le port ? » → **non**. C'est de la documentation dans les métadonnées de
  l'image. Seul `ports:` (ou `-p`) publie un port vers l'hôte. À l'intérieur d'un réseau Docker,
  tous les ports des conteneurs sont déjà joignables entre eux sans `EXPOSE`.

---

## T10 — Configuration MariaDB

**OBJ** : faire écouter MariaDB sur le réseau du conteneur (et pas seulement en local).

**POURQUOI** : Debian configure MariaDB avec `bind-address = 127.0.0.1` par défaut. Dans un
conteneur, ça signifie « écoute uniquement sur la loopback **du conteneur** » : le conteneur
`wordpress` ne pourrait jamais s'y connecter. C'est le bug n°1 de ce ticket.

**ÉTAPES** — `srcs/requirements/mariadb/conf/50-server.cnf` :

```ini
[server]

[mysqld]
user                    = mysql
pid-file                = /run/mysqld/mysqld.pid
socket                  = /run/mysqld/mysqld.sock
basedir                 = /usr
datadir                 = /var/lib/mysql
tmpdir                  = /tmp
lc-messages-dir         = /usr/share/mysql

# Écoute sur toutes les interfaces du CONTENEUR.
# Le conteneur n'étant joignable que depuis le réseau Docker "inception"
# (aucun port n'est publié vers l'hôte), cela reste privé.
bind-address            = 0.0.0.0

# Pas de résolution DNS inverse à chaque connexion : plus rapide et plus prévisible,
# les droits sont accordés sur '%' et non sur un nom d'hôte.
skip-name-resolve

character-set-server    = utf8mb4
collation-server        = utf8mb4_unicode_ci

[client]
socket                  = /run/mysqld/mysqld.sock
default-character-set   = utf8mb4

[mysqld_safe]
socket                  = /run/mysqld/mysqld.sock
```

**DoD** (après T11/T17)
```bash
docker exec -it mariadb ss -lntp | grep 3306    # 0.0.0.0:3306
```

**SOUTENANCE**
- « `0.0.0.0`, ce n'est pas dangereux ? » → non ici, parce qu'aucun port n'est **publié** :
  `mariadb` n'a pas de section `ports:` dans le compose. Le seul point d'entrée depuis l'hôte
  est le 443 de nginx. `0.0.0.0` ne signifie « accessible depuis internet » que si un port est
  publié.

---

## T11 — Entrypoint MariaDB (initialisation de la base)

**OBJ** : au **premier** démarrage seulement, initialiser le datadir, poser le mot de passe root,
créer la base WordPress et l'utilisateur applicatif — puis passer la main au serveur.

**POURQUOI** : c'est le ticket le plus « piégé » du projet à cause de l'interdiction des hacks.
La tentation classique est : démarrer `mysqld` en tâche de fond, `sleep 10`, lancer `mysql -e
"..."`, arrêter, redémarrer en avant-plan. C'est exactement le genre de bricolage que le sujet
vise. La bonne méthode : **`mysqld --bootstrap`**, un mode où le serveur lit du SQL sur son
entrée standard, l'exécute **sans ouvrir de réseau ni se daemoniser**, et se termine. Zéro
attente, zéro boucle, zéro processus fantôme.

**ÉTAPES** — `srcs/requirements/mariadb/tools/entrypoint.sh` :

```sh
#!/bin/sh
# Arrêt immédiat à la première erreur : mieux vaut un conteneur qui échoue bruyamment
# qu'une base à moitié initialisée.
set -e

# Les secrets sont montés en lecture seule par Compose dans /run/secrets/.
# tr -d '\r\n' : protège contre un retour à la ligne final dans le fichier.
DB_ROOT_PASSWORD="$(tr -d '\r\n' < /run/secrets/db_root_password)"
DB_PASSWORD="$(tr -d '\r\n' < /run/secrets/db_password)"

# Le volume est monté vide au premier lancement : ces répertoires doivent exister
# et appartenir à l'utilisateur mysql.
mkdir -p /run/mysqld
chown -R mysql:mysql /run/mysqld /var/lib/mysql

# /var/lib/mysql/mysql est la base système : sa présence = datadir déjà initialisé.
# Ce test rend le script IDEMPOTENT : au 2e démarrage, on ne réinitialise rien
# et les données du volume sont conservées.
if [ ! -d "/var/lib/mysql/mysql" ]; then
    echo "[mariadb] premier demarrage : initialisation du datadir"
    mariadb-install-db --user=mysql --datadir=/var/lib/mysql --skip-test-db >/dev/null

    echo "[mariadb] application du SQL d'initialisation"
    # --bootstrap : le serveur execute ce SQL puis se termine.
    # Aucun port ouvert, aucun daemon, aucune attente : pas de "sleep", pas de boucle.
    mysqld --user=mysql --bootstrap <<EOSQL
USE mysql;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${DB_ROOT_PASSWORD}';
DELETE FROM mysql.global_priv WHERE User='';
CREATE DATABASE IF NOT EXISTS \`${MYSQL_DATABASE}\`;
CREATE USER IF NOT EXISTS '${MYSQL_USER}'@'%' IDENTIFIED BY '${DB_PASSWORD}';
GRANT ALL PRIVILEGES ON \`${MYSQL_DATABASE}\`.* TO '${MYSQL_USER}'@'%';
FLUSH PRIVILEGES;
EOSQL
    echo "[mariadb] initialisation terminee"
else
    echo "[mariadb] datadir existant : demarrage direct"
fi

# exec : le shell est REMPLACÉ par mysqld, qui devient PID 1 et reçoit
# directement les signaux (SIGTERM de docker stop) → arrêt propre de la base.
exec "$@"
```

Rends-le exécutable côté hôte aussi (utile si tu le lances à la main) :
```bash
chmod +x srcs/requirements/mariadb/tools/entrypoint.sh
```

**Détails qui comptent**

- `'root'@'localhost'` seulement : root **ne doit pas** être accessible depuis le réseau.
- `'${MYSQL_USER}'@'%'` : l'utilisateur WordPress se connecte depuis **un autre conteneur**,
  donc depuis une IP du réseau Docker, qui change à chaque recréation → on autorise `%`.
- `GRANT ... ON \`wordpress\`.*` : l'utilisateur WordPress n'a **aucun** droit sur les autres
  bases. Principe du moindre privilège.
- `DELETE FROM mysql.global_priv WHERE User=''` supprime les utilisateurs anonymes.
  (`global_priv` est la table de MariaDB ≥ 10.4 ; `mysql.user` n'y est plus qu'une vue.)

**DoD**
```bash
docker compose -f srcs/docker-compose.yml up -d mariadb        # après T17
docker compose -f srcs/docker-compose.yml logs mariadb
docker exec -it mariadb mariadb -u wpuser -p -e "SHOW DATABASES;"
# → doit lister "wordpress"
docker exec -it mariadb ps -o pid,cmd
# → PID 1 doit être mysqld, PAS sh, PAS tail
```

**SOUTENANCE** — la question qui tombe à tous les coups :
- « Pourquoi le PID 1 est-il important ? » → dans un conteneur, le premier processus reçoit le
  PID 1, ce qui lui donne deux responsabilités spéciales du noyau Linux : (1) les **signaux par
  défaut sont ignorés** pour PID 1 — s'il n'a pas de handler explicite pour SIGTERM, le signal
  est simplement jeté ; (2) il doit **récolter les processus orphelins** (zombies). Concrètement :
  `docker stop` envoie SIGTERM au PID 1 puis attend 10 s avant SIGKILL. Si PID 1 est un `sh -c`
  ou un `tail -f`, MariaDB ne reçoit jamais le signal, n'écrit jamais ses buffers sur disque, et
  se fait tuer brutalement → risque de corruption.
- « Pourquoi `tail -f` est-il interdit ? » → c'est un pansement pour « garder le conteneur
  vivant » alors que le vrai service s'est daemonisé en arrière-plan. Ça inverse la logique :
  Docker n'a plus aucun moyen de savoir si le service est vivant, `restart:` ne redémarre plus
  rien quand le service crashe (le `tail` tourne toujours), et les logs du service ne vont plus
  sur la sortie standard du conteneur. **Un conteneur = un processus en avant-plan.**
- « Pourquoi `exec` et pas juste `mysqld` ? » → sans `exec`, le shell reste PID 1 et `mysqld`
  devient son enfant : on retombe exactement dans le problème de signaux ci-dessus.

---

## T12 — Dockerfile WordPress (php-fpm + wp-cli)

**OBJ** : une image `wordpress:1.0` contenant PHP-FPM, les extensions nécessaires et l'outil
`wp-cli` — **sans nginx**, comme l'exige le sujet.

**POURQUOI** : WordPress n'est pas un serveur : c'est du code PHP. Il lui faut un interpréteur
piloté par un *process manager* FastCGI (php-fpm) et un client MySQL (extension `php-mysql`).
`wp-cli` est l'outil **officiel** en ligne de commande de WordPress : il permet de télécharger
le cœur, générer `wp-config.php`, installer le site et créer les utilisateurs **sans passer par
l'assistant web** — donc de façon totalement automatisée et reproductible.

**ÉTAPES** — `srcs/requirements/wordpress/Dockerfile` :

```dockerfile
FROM debian:bookworm

# php8.2-* : bookworm fournit PHP 8.2. Adapte le numéro si tu changes de version Debian.
#   -fpm      : le process manager FastCGI
#   -mysql    : extension mysqli/pdo_mysql, indispensable pour parler à MariaDB
#   -curl -gd -mbstring -xml -zip : extensions attendues par WordPress
#   mariadb-client : fournit la commande `mariadb`, utilisee par wp-cli pour certaines
#                    operations et bien pratique pour deboguer
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        php8.2-fpm \
        php8.2-mysql \
        php8.2-curl \
        php8.2-gd \
        php8.2-mbstring \
        php8.2-xml \
        php8.2-zip \
        mariadb-client \
        curl \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# wp-cli : outil officiel WordPress, recupere depuis sa source amont.
# Ce n'est PAS une image Docker toute faite : le sujet interdit de tirer des images
# pretes a l'emploi, pas de telecharger un outil depuis son site officiel.
RUN curl -fsSL -o /usr/local/bin/wp \
        https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar && \
    chmod +x /usr/local/bin/wp

# Pool php-fpm : ecoute en TCP sur 9000 (le defaut Debian est une socket Unix,
# inutilisable depuis un AUTRE conteneur).
COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf

COPY tools/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh && \
    mkdir -p /run/php /var/www/html && \
    chown -R www-data:www-data /var/www/html

WORKDIR /var/www/html

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
# -F (--nodaemonize) : php-fpm reste en avant-plan → il est PID 1, pas de daemon.
CMD ["php-fpm8.2", "-F"]
```

`srcs/requirements/wordpress/.dockerignore` :
```
.dockerignore
*.md
```

**DoD**
```bash
docker build -t wordpress:1.0 srcs/requirements/wordpress
docker run --rm wordpress:1.0 php -m | grep -E 'mysqli|curl|gd|mbstring'
docker run --rm wordpress:1.0 wp --info --allow-root
```

**SOUTENANCE**
- « Pourquoi télécharger WordPress au **runtime** et pas dans le Dockerfile ? » → parce que
  `/var/www/html` est un **point de montage de volume**. Au démarrage, Docker monte le volume
  par-dessus le répertoire de l'image : tout ce qui aurait été copié là à la construction serait
  masqué. (Docker copie le contenu de l'image dans un volume *nommé et vide* lors du premier
  montage — mais ce comportement ne s'applique pas de façon fiable à un volume adossé à un
  chemin hôte via `o=bind`.) On installe donc dans l'entrypoint, ce qui a un bonus : le contenu
  du site est bien dans le volume, donc **persistant**, comme le demande le sujet.
- « Pourquoi `-F` ? » → sans lui, php-fpm se *fork* et rend la main : le PID 1 se termine, donc
  Docker considère le conteneur comme terminé et l'arrête. `-F` le garde en avant-plan.

---

## T13 — Pool php-fpm (`www.conf`)

**OBJ** : faire écouter php-fpm en TCP sur `0.0.0.0:9000`.

**POURQUOI** : sur Debian, php-fpm écoute par défaut sur une **socket Unix**
(`/run/php/php8.2-fpm.sock`). Une socket Unix est un fichier : elle ne franchit pas la frontière
d'un conteneur. Comme nginx est dans **un autre conteneur**, il faut basculer en **TCP** — les
deux conteneurs partagent alors le réseau `inception`, pas le système de fichiers.

**ÉTAPES** — `srcs/requirements/wordpress/conf/www.conf` :

```ini
[www]
user = www-data
group = www-data

; TCP et non socket Unix : nginx est dans un autre conteneur.
; 0.0.0.0 = toutes les interfaces du conteneur ; aucun port n'est publie vers l'hote.
listen = 0.0.0.0:9000
listen.owner = www-data
listen.group = www-data

; Securite : n'accepter les requetes FastCGI que du conteneur nginx.
; (Commente si tu veux eviter une dependance a la resolution DNS au demarrage.)
; listen.allowed_clients = 127.0.0.1

; Gestion dynamique des workers : php-fpm ajuste le nombre de processus PHP
; entre min_spare et max_spare, dans la limite de max_children.
pm = dynamic
pm.max_children = 10
pm.start_servers = 2
pm.min_spare_servers = 1
pm.max_spare_servers = 3
pm.max_requests = 500

; Laisse passer les variables d'environnement du conteneur vers PHP.
clear_env = no

; Logs des erreurs PHP vers la sortie d'erreur du conteneur → visibles dans docker logs.
catch_workers_output = yes
php_admin_value[error_log] = /proc/self/fd/2
php_admin_flag[log_errors] = on
```

**DoD**
```bash
docker exec -it wordpress ss -lntp | grep 9000   # 0.0.0.0:9000
docker exec -it wordpress ps -o pid,user,cmd     # PID 1 = php-fpm master (root),
                                                 # workers en www-data
```

**SOUTENANCE**
- « Pourquoi le master php-fpm tourne-t-il en root ? » → pour pouvoir ouvrir le port et surtout
  **changer d'identité** : il crée ses workers sous `www-data`. C'est le code PHP (donc le code
  non maîtrisé de WordPress et de ses plugins) qui s'exécute en `www-data`, pas en root. C'est le
  bon modèle de privilèges.
- « `catch_workers_output` ? » → sans lui, les erreurs PHP partent dans un fichier de log interne
  et `docker logs wordpress` reste muet. Un conteneur doit écrire ses logs sur stdout/stderr :
  c'est la convention que Docker collecte.

---

## T14 — Entrypoint WordPress (installation automatique)

**OBJ** : au premier démarrage, télécharger WordPress, générer `wp-config.php`, installer le
site, créer **deux utilisateurs** dont un administrateur — puis lancer php-fpm.

**POURQUOI** : le sujet impose « *two users, one of them being the administrator* » et un login
d'admin qui ne contient pas `admin`. Tout doit être automatique : le correcteur lance `make` et
doit tomber sur un site déjà installé, sans passer par l'assistant web.

**ÉTAPES** — `srcs/requirements/wordpress/tools/entrypoint.sh` :

```sh
#!/bin/sh
set -e

WP_PATH=/var/www/html

# --- Secrets ---------------------------------------------------------------
# db_password : mot de passe de l'utilisateur MySQL applicatif.
DB_PASSWORD="$(tr -d '\r\n' < /run/secrets/db_password)"
# credentials : fichier au format shell -> definit WP_ADMIN_PASSWORD et WP_USER_PASSWORD.
. /run/secrets/credentials

mkdir -p /run/php
cd "$WP_PATH"

# wp-config.php n'existe que si l'installation a deja ete faite :
# ce test rend le script idempotent (2e demarrage = on ne reinstalle rien).
if [ ! -f "$WP_PATH/wp-config.php" ]; then

    echo "[wordpress] telechargement du coeur WordPress ${WP_VERSION}"
    wp core download --version="${WP_VERSION}" --path="$WP_PATH" --allow-root

    echo "[wordpress] generation de wp-config.php"
    wp config create \
        --dbname="${MYSQL_DATABASE}" \
        --dbuser="${MYSQL_USER}" \
        --dbpass="${DB_PASSWORD}" \
        --dbhost="${WP_DB_HOST}" \
        --path="$WP_PATH" --allow-root

    echo "[wordpress] installation du site"
    wp core install \
        --url="https://${DOMAIN_NAME}" \
        --title="${WP_TITLE}" \
        --admin_user="${WP_ADMIN_USER}" \
        --admin_password="${WP_ADMIN_PASSWORD}" \
        --admin_email="${WP_ADMIN_EMAIL}" \
        --skip-email \
        --path="$WP_PATH" --allow-root

    echo "[wordpress] creation du second utilisateur (non administrateur)"
    wp user create "${WP_USER}" "${WP_USER_EMAIL}" \
        --role=author \
        --user_pass="${WP_USER_PASSWORD}" \
        --path="$WP_PATH" --allow-root
else
    echo "[wordpress] installation existante detectee : demarrage direct"
fi

# Les fichiers viennent d'etre crees par root : php-fpm tourne en www-data.
chown -R www-data:www-data "$WP_PATH"

# exec : php-fpm devient PID 1 et recoit les signaux.
exec "$@"
```

```bash
chmod +x srcs/requirements/wordpress/tools/entrypoint.sh
```

**Points à comprendre**

- `--allow-root` : wp-cli refuse de tourner en root par défaut (bonne pratique sur un serveur
  partagé). Ici l'entrypoint est root parce qu'il doit écrire dans un volume fraîchement monté
  et faire le `chown`. Sache le dire : *« je sais pourquoi wp-cli se plaint, et le `chown`
  final remet les fichiers sous `www-data` »*.
- `--dbhost="${WP_DB_HOST}"` vaut `mariadb:3306` : **le nom du service**, résolu par le DNS
  interne de Docker. C'est ce qui remplace `--link`.
- `--skip-email` : évite que WordPress essaie d'envoyer un mail d'installation (il n'y a pas de
  MTA dans le conteneur, ça ralentirait le démarrage).
- `--role=author` : le second utilisateur doit être **non-administrateur** pour que la contrainte
  « deux utilisateurs dont un admin » ait du sens (`subscriber` convient aussi).

**Dépendance critique** : ce script échoue si MariaDB n'est pas encore prête. On ne résout pas ça
avec un `sleep` : on utilise un **healthcheck** sur mariadb + `depends_on: condition:
service_healthy` dans le compose (T17). Docker ne démarre WordPress qu'une fois la base déclarée
saine.

**DoD**
```bash
docker compose -f srcs/docker-compose.yml logs wordpress
docker exec -it wordpress wp user list --path=/var/www/html --allow-root
# → 2 lignes : rafeger (administrator) et visiteur (author)
docker exec -it wordpress ls /var/www/html      # wp-config.php, wp-admin, wp-content...
ls /home/rafeger/data/wordpress                 # les MÊMES fichiers, côté hôte
```

**SOUTENANCE**
- « Comment gères-tu l'ordre de démarrage ? » → `depends_on` seul n'attend que le **démarrage du
  conteneur**, pas la disponibilité du service. J'ajoute donc un `healthcheck` sur mariadb
  (`mariadb-admin ping`) et `condition: service_healthy` : Docker ne lance WordPress qu'une fois
  la base réellement prête. Et si malgré tout ça échoue, `restart: always` relance le conteneur
  — pas de `sleep` arbitraire dans mon code.
- « Et si je relance `make` ? » → le script est **idempotent** : `wp-config.php` existe déjà, on
  saute toute l'installation, les données du volume sont conservées.

---

## T15 — Dockerfile NGINX + certificat TLS

**OBJ** : une image `nginx:1.0` avec un certificat auto-signé pour `rafeger.42.fr`, écoutant
**uniquement** sur 443 en TLSv1.2/1.3.

**POURQUOI** : le sujet est très précis — nginx doit être **le seul point d'entrée**, **via le
port 443 uniquement**, en **TLSv1.2 ou TLSv1.3 seulement**. Donc : pas d'écoute sur 80, pas de
redirection 80→443 (ce serait une seconde entrée), et désactivation explicite des vieux
protocoles.

**ÉTAPES** — `srcs/requirements/nginx/Dockerfile` :

```dockerfile
FROM debian:bookworm

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        nginx \
        openssl && \
    rm -rf /var/lib/apt/lists/*

# ARG : variable disponible UNIQUEMENT pendant le build (pas dans le conteneur final).
# Sa valeur est fournie par docker-compose.yml (build.args) depuis le .env.
ARG DOMAIN_NAME=rafeger.42.fr

# Certificat auto-signe valable 1 an, cle RSA 2048.
#   -x509  : produit directement un certificat, pas une demande de signature (CSR)
#   -nodes : la cle privee n'est pas chiffree (sinon nginx demanderait une passphrase
#            au demarrage, ce qui est impossible dans un conteneur non interactif)
#   CN     : doit correspondre au nom de domaine, sinon erreur de nom dans le navigateur
RUN mkdir -p /etc/nginx/ssl && \
    openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
        -keyout /etc/nginx/ssl/inception.key \
        -out    /etc/nginx/ssl/inception.crt \
        -subj "/C=FR/ST=IDF/L=Paris/O=42/OU=42/CN=${DOMAIN_NAME}" && \
    chmod 600 /etc/nginx/ssl/inception.key

# On retire le site par defaut de Debian (il ecoute sur le port 80).
RUN rm -f /etc/nginx/sites-enabled/default

COPY conf/default.conf /etc/nginx/conf.d/default.conf

EXPOSE 443

# "daemon off;" : nginx reste en avant-plan → PID 1, pas de fork en arriere-plan.
CMD ["nginx", "-g", "daemon off;"]
```

`srcs/requirements/nginx/.dockerignore` :
```
.dockerignore
*.md
```

> Le dossier `srcs/requirements/nginx/tools/` reste vide ici : il n'y a pas d'initialisation à
> faire au runtime. Tu peux le supprimer, ou y placer le certificat si tu préfères le générer
> dans un script. Générer dans le Dockerfile est plus simple à défendre : le certificat fait
> partie de l'image, il n'y a aucun secret dans le compose.

**DoD**
```bash
docker build --build-arg DOMAIN_NAME=rafeger.42.fr -t nginx:1.0 srcs/requirements/nginx
docker run --rm nginx:1.0 openssl x509 -in /etc/nginx/ssl/inception.crt -noout -subject -dates
```

**SOUTENANCE**
- « `ARG` vs `ENV` ? » → `ARG` n'existe **qu'au build** et n'est pas présent dans le conteneur
  final ; `ENV` est écrit dans les métadonnées de l'image et présent au runtime. Corollaire :
  **jamais de mot de passe en `ARG`** non plus — il reste visible dans `docker history`.
- « Un certificat auto-signé, c'est du vrai TLS ? » → le **chiffrement** est identique ; ce qui
  manque est l'**authentification** : aucune autorité de certification reconnue ne garantit que
  ce certificat appartient bien à `rafeger.42.fr`. D'où l'avertissement du navigateur. En
  production on utiliserait une CA (Let's Encrypt) ; ici le domaine est local, aucune CA ne
  pourrait le signer.
- « Pourquoi pas de redirection depuis le port 80 ? » → parce que le sujet dit « via le port
  **443 uniquement** ». Écouter sur 80, même pour rediriger, créerait un second point d'entrée.

---

## T16 — Configuration NGINX

**OBJ** : servir WordPress en HTTPS et transmettre les `.php` à `wordpress:9000`.

**POURQUOI** : c'est ici que se joue le lien nginx ↔ php-fpm. **FastCGI** est un protocole
binaire : nginx n'envoie pas le fichier PHP, il envoie un jeu de **paramètres** (méthode, URI,
en-têtes, et surtout `SCRIPT_FILENAME` = le **chemin absolu** du script) ; php-fpm ouvre ce
chemin lui-même sur son propre système de fichiers. D'où le volume partagé.

**ÉTAPES** — `srcs/requirements/nginx/conf/default.conf` :

```nginx
server {
    # Seul port d'ecoute : 443, en TLS. Aucune ecoute sur le port 80.
    listen      443 ssl;
    listen      [::]:443 ssl;

    # Doit correspondre au CN du certificat et a DOMAIN_NAME du .env.
    server_name rafeger.42.fr;

    ssl_certificate     /etc/nginx/ssl/inception.crt;
    ssl_certificate_key /etc/nginx/ssl/inception.key;

    # EXIGENCE DU SUJET : uniquement TLSv1.2 et TLSv1.3.
    # SSLv3, TLSv1.0 et TLSv1.1 sont donc refuses.
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    # Racine = le volume partage avec le conteneur wordpress.
    root  /var/www/html;
    index index.php index.html;

    # Fichiers statiques servis par nginx ; sinon on passe la main a WordPress
    # (permaliens : /mon-article -> /index.php?...).
    location / {
        try_files $uri $uri/ /index.php?$args;
    }

    location ~ \.php$ {
        # Separe /index.php/foo en $fastcgi_script_info + $fastcgi_path_info
        fastcgi_split_path_info ^(.+\.php)(/.+)$;

        # Parametres FastCGI standards (REQUEST_METHOD, QUERY_STRING, en-tetes...)
        include fastcgi_params;

        # LE parametre cle : chemin ABSOLU du script, tel que php-fpm le verra.
        # $document_root vaut /var/www/html, qui existe aussi dans le conteneur
        # wordpress grace au volume partage.
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        fastcgi_param PATH_INFO       $fastcgi_path_info;

        # "wordpress" est resolu par le DNS interne de Docker (127.0.0.11)
        # vers l'IP du conteneur sur le reseau "inception".
        fastcgi_pass wordpress:9000;
        fastcgi_index index.php;
    }

    # On ne sert jamais les fichiers sensibles ni les .php de wp-content
    # (uploads utilisateurs) : durcissement classique de WordPress.
    location ~ /\.ht { deny all; }
    location = /wp-config.php { deny all; }
}
```

**DoD**
```bash
docker exec -it nginx nginx -t                 # syntaxe OK
curl -Ik https://rafeger.42.fr                 # 200 ou 301/302 vers /
curl -Ik --tlsv1.1 --tls-max 1.1 https://rafeger.42.fr   # DOIT ÉCHOUER
curl -Ik --tlsv1.2 --tls-max 1.2 https://rafeger.42.fr   # DOIT PASSER
curl -Ik --tlsv1.3 https://rafeger.42.fr                 # DOIT PASSER
```

**SOUTENANCE**
- « Que fait `try_files` ? » → nginx teste d'abord si l'URI correspond à un fichier réel, puis à
  un répertoire, sinon il réécrit vers `/index.php?$args`. C'est ce qui rend les permaliens
  WordPress fonctionnels : `/mon-article` n'est pas un fichier, c'est WordPress qui interprète
  l'URL.
- « Pourquoi `fastcgi_pass wordpress:9000` et pas une IP ? » → l'IP d'un conteneur change à
  chaque recréation. Le nom de service est stable et résolu par le DNS embarqué de Docker.
- « Qu'est-ce que `fastcgi_params` contient ? » → la liste standard des variables CGI que nginx
  transmet (`REQUEST_METHOD`, `QUERY_STRING`, `CONTENT_TYPE`, `HTTP_*`…). `SCRIPT_FILENAME` doit
  être défini **après** l'include, sinon la valeur par défaut le neutralise.

---

# PHASE 3 — Orchestration

---

## T17 — `srcs/docker-compose.yml`

**OBJ** : le fichier qui décrit les 3 services, le réseau, les 2 volumes nommés et les 3 secrets.

**POURQUOI** : c'est la pièce que le correcteur lira ligne par ligne. Chaque exigence du sujet
doit y être visible et justifiable.

**ÉTAPES** — écris `srcs/docker-compose.yml` :

```yaml
# Nom du projet : prefixe tous les objets Docker (reseau, volumes, conteneurs).
# Pas de cle "version:" : elle est obsolete depuis Compose v2 et produit un warning.
name: inception

services:

  # --------------------------------------------------------------------------
  # Base de donnees
  # --------------------------------------------------------------------------
  mariadb:
    container_name: mariadb
    build:
      context: ./requirements/mariadb          # chemin relatif AU FICHIER compose
    image: mariadb:1.0                         # nom = nom du service ; pas de tag "latest"
    restart: always                            # exigence du sujet : redemarrage en cas de crash
    networks:
      - inception
    volumes:
      - mariadb_data:/var/lib/mysql            # VOLUME NOMME (pas un chemin hote)
    environment:
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER: ${MYSQL_USER}
      # aucun mot de passe ici : ils passent par les secrets
    secrets:
      - db_root_password
      - db_password
    expose:
      - "3306"                                 # documentation ; aucun port publie vers l'hote
    healthcheck:
      # Verifie que le serveur repond REELLEMENT, pas seulement que le conteneur tourne.
      # $$ : echappe le $ pour que Compose ne tente pas de substituer la variable.
      test: ['CMD-SHELL', 'mariadb-admin ping -h localhost -u root -p"$$(cat /run/secrets/db_root_password)" --silent']
      interval: 5s
      timeout: 5s
      retries: 20
      start_period: 20s

  # --------------------------------------------------------------------------
  # WordPress + php-fpm
  # --------------------------------------------------------------------------
  wordpress:
    container_name: wordpress
    build:
      context: ./requirements/wordpress
    image: wordpress:1.0
    restart: always
    depends_on:
      mariadb:
        condition: service_healthy             # attend que le healthcheck passe au vert
    networks:
      - inception
    volumes:
      - wordpress_data:/var/www/html
    environment:
      DOMAIN_NAME:    ${DOMAIN_NAME}
      MYSQL_DATABASE: ${MYSQL_DATABASE}
      MYSQL_USER:     ${MYSQL_USER}
      WP_DB_HOST:     ${WP_DB_HOST}
      WP_VERSION:     ${WP_VERSION}
      WP_TITLE:       ${WP_TITLE}
      WP_ADMIN_USER:  ${WP_ADMIN_USER}
      WP_ADMIN_EMAIL: ${WP_ADMIN_EMAIL}
      WP_USER:        ${WP_USER}
      WP_USER_EMAIL:  ${WP_USER_EMAIL}
    secrets:
      - db_password
      - credentials
    expose:
      - "9000"
    healthcheck:
      # Le site est pret quand wp-config.php existe dans le volume.
      test: ['CMD-SHELL', 'test -f /var/www/html/wp-config.php']
      interval: 5s
      timeout: 5s
      retries: 30
      start_period: 30s

  # --------------------------------------------------------------------------
  # Reverse proxy TLS - SEUL point d'entree
  # --------------------------------------------------------------------------
  nginx:
    container_name: nginx
    build:
      context: ./requirements/nginx
      args:
        DOMAIN_NAME: ${DOMAIN_NAME}            # injecte dans le CN du certificat
    image: nginx:1.0
    restart: always
    depends_on:
      wordpress:
        condition: service_healthy
    networks:
      - inception
    volumes:
      - wordpress_data:/var/www/html           # meme volume : nginx sert les fichiers statiques
    ports:
      - "443:443"                              # LE SEUL port publie de toute l'infra

# ------------------------------------------------------------------------------
# Volumes NOMMES, stockes dans /home/rafeger/data comme l'exige le sujet.
#
#   driver: local + type=none + o=bind + device=<chemin>
#   -> on demande au driver local de stocker le volume a un emplacement precis.
#   Ce reste un volume NOMME : il apparait dans `docker volume ls`, il est gere par
#   Docker, et dans services.*.volumes on reference un NOM, jamais un chemin hote.
#   Les repertoires doivent exister AVANT le `up` : c'est le role du Makefile.
# ------------------------------------------------------------------------------
volumes:
  mariadb_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_PATH}/mariadb

  wordpress_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: ${DATA_PATH}/wordpress

# ------------------------------------------------------------------------------
# Reseau bridge dedie. Interdits par le sujet : network_mode: host, links, --link.
# Sur un bridge defini par l'utilisateur, Docker fournit un DNS interne qui resout
# les noms de services -> c'est ce qui remplace --link.
# ------------------------------------------------------------------------------
networks:
  inception:
    driver: bridge

# ------------------------------------------------------------------------------
# Secrets : montes en lecture seule dans /run/secrets/<nom> (tmpfs, en memoire).
# Chemins relatifs au fichier compose -> ../secrets = <racine>/secrets.
# ------------------------------------------------------------------------------
secrets:
  db_root_password:
    file: ../secrets/db_root_password.txt
  db_password:
    file: ../secrets/db_password.txt
  credentials:
    file: ../secrets/credentials.txt
```

**Vérification de conformité, ligne à ligne** — coche mentalement :

| Exigence du sujet | Où c'est dans le fichier |
|---|---|
| un conteneur par service | 3 blocs `services:` |
| image nommée comme le service | `image: mariadb:1.0` / `wordpress:1.0` / `nginx:1.0` |
| pas de tag `latest` | tags explicites `:1.0`, et `FROM debian:bookworm` |
| Dockerfiles appelés par le compose | `build.context` sur chaque service |
| pas d'image toute faite tirée | aucun service sans `build:` |
| volumes **nommés** | section `volumes:` de premier niveau, référencés par nom |
| données dans `/home/login/data` | `device: ${DATA_PATH}/...` avec `DATA_PATH=/home/rafeger/data` |
| un réseau docker, ligne présente | section `networks:` + `networks:` sur chaque service |
| pas de `host` / `links` | aucune occurrence |
| redémarrage en cas de crash | `restart: always` ×3 |
| nginx seul point d'entrée, 443 seul | un seul `ports:` dans tout le fichier |
| pas de mot de passe en clair | aucun ; seulement `secrets:` et des `${VAR}` non sensibles |

**DoD**
```bash
docker compose -f srcs/docker-compose.yml config          # rend le YAML final, substitue
docker compose -f srcs/docker-compose.yml config --quiet  # 0 = fichier valide
grep -rniE 'network_mode|links:|latest' srcs/             # doit ne rien renvoyer
```

**SOUTENANCE**
- « Docker network vs host network ? » (question **explicitement demandée** dans le README)
  - `network_mode: host` supprime le **namespace réseau** : le conteneur utilise directement la
    pile réseau de l'hôte. Conséquences : aucun isolement, tous les ports du conteneur sont
    ouverts sur l'hôte, **pas de DNS interne** (les conteneurs ne se voient plus par nom), et
    conflits de ports dès que deux conteneurs veulent le même. C'est pour ça que le sujet
    l'interdit — ça reviendrait à supprimer l'isolation qu'on est censé démontrer.
  - un **bridge défini par l'utilisateur** crée un réseau virtuel isolé : chaque conteneur a sa
    propre interface et sa propre IP, la résolution par nom de service est fournie, et **rien
    n'est joignable depuis l'extérieur tant qu'on ne publie pas de port**. On expose exactement
    une chose : le 443 de nginx.
  - bonus : le bridge **par défaut** (`docker0`) n'a pas le DNS par nom — c'est justement pour
    ça que `--link` existait. Un bridge **nommé**, comme ici, rend `--link` obsolète.
- « `expose` vs `ports` ? » → `expose` est purement déclaratif (métadonnée) ; `ports` crée une
  règle de NAT/DNAT (iptables) qui publie le port sur l'hôte. Seul nginx en a un.
- « `depends_on` garantit quoi ? » → l'ordre de **démarrage**, et avec `condition:
  service_healthy`, l'attente de la **disponibilité réelle** mesurée par le healthcheck.

---

## T18 — Le Makefile

**OBJ** : `make` construit et démarre toute l'infrastructure ; `make fclean` remet à zéro.

**POURQUOI** : exigence du sujet — Makefile **à la racine**, qui « doit mettre en place toute
l'application, c'est-à-dire construire les images Docker en utilisant le docker-compose.yml ».
C'est aussi la première commande que le correcteur tapera.

**ÉTAPES** — `Makefile` à la racine :

```makefile
# ==============================================================================
# Inception - Makefile
# ==============================================================================

COMPOSE_FILE := srcs/docker-compose.yml
COMPOSE      := docker compose -f $(COMPOSE_FILE)

# On lit le .env pour recuperer DATA_PATH : une seule source de verite.
# `include` echoue si le fichier manque -> on est prevenu tout de suite.
include srcs/.env

# Les deux repertoires hote qui servent de support aux volumes nommes.
DIRS := $(DATA_PATH)/mariadb $(DATA_PATH)/wordpress

# ------------------------------------------------------------------------------
.PHONY: all up build down stop start restart re clean fclean logs ps status help

all: up

# Les repertoires DOIVENT exister avant le up : le driver local avec o=bind
# refuse de monter un chemin inexistant.
$(DIRS):
	@mkdir -p $@
	@echo "  [mkdir] $@"

## up      : construit les images si besoin et demarre toute l'infrastructure
up: $(DIRS)
	$(COMPOSE) up -d --build
	@echo "==> https://$(DOMAIN_NAME)"

## build   : construit les images sans demarrer les conteneurs
build: $(DIRS)
	$(COMPOSE) build

## down    : arrete et SUPPRIME les conteneurs et le reseau (les volumes restent)
down:
	$(COMPOSE) down

## stop    : met les conteneurs en pause sans les supprimer
stop:
	$(COMPOSE) stop

## start   : relance des conteneurs arretes
start:
	$(COMPOSE) start

## restart : down puis up
restart: down up

## logs    : suit les logs des trois services
logs:
	$(COMPOSE) logs -f

## ps      : etat des conteneurs
ps status:
	$(COMPOSE) ps
	@echo "--- volumes ---"  && docker volume ls
	@echo "--- reseaux ---"  && docker network ls

## clean   : down + suppression des volumes Docker
clean: down
	$(COMPOSE) down --volumes --remove-orphans

## fclean  : clean + suppression des images du projet ET des donnees sur l'hote
fclean: clean
	-docker image rm -f mariadb:1.0 wordpress:1.0 nginx:1.0 2>/dev/null
	@echo "Suppression des donnees dans $(DATA_PATH) (sudo requis)"
	sudo rm -rf $(DATA_PATH)/mariadb $(DATA_PATH)/wordpress

## re      : repart d'une infrastructure totalement vierge
re: fclean all

help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## //'
```

**Points à comprendre**

- `include srcs/.env` : `make` sait lire un fichier `CLE=valeur`. On évite ainsi de dupliquer
  `/home/rafeger/data` entre le `.env` et le Makefile. (Attention : ça suppose des valeurs
  simples, sans `$` ni guillemets bizarres.)
- `$(DIRS)` en **prérequis** de `up` : `make` ne recrée les dossiers que s'ils manquent.
- `-docker image rm` : le `-` initial dit à make d'ignorer l'échec (si l'image n'existe pas).
- `sudo` dans `fclean` : les fichiers de MariaDB appartiennent à l'utilisateur `mysql` **du
  conteneur** (un uid inconnu de l'hôte), donc ton utilisateur ne peut pas les supprimer.
- `.PHONY` : ces cibles ne produisent pas de fichier du même nom ; sans ça, un fichier nommé
  `clean` empêcherait la cible de tourner.

**DoD**
```bash
make help
make            # doit construire et démarrer les 3 conteneurs
make ps
```

**SOUTENANCE**
- « Que fait `docker compose down` exactement ? » → il arrête et **supprime** les conteneurs, le
  réseau, et les conteneurs orphelins ; il **ne supprime pas** les volumes (il faut `--volumes`).
  C'est justement ce qui permet de prouver la persistance : `make down && make up` et le site
  est toujours là.
- « Différence `clean` / `fclean` ? » → `clean` supprime les objets Docker (conteneurs, réseau,
  volumes) ; `fclean` supprime en plus les **images du projet** et les **données sur l'hôte**.
  Après `fclean`, `make` reconstruit tout de zéro et réinstalle WordPress.

---

# PHASE 4 — Build, débogage et validation

---

## T19 — Premier build et débogage

**OBJ** : passer du code qui compile à une infra qui tourne.

**ÉTAPES — méthode, service par service** (ne lance pas tout d'un coup la première fois)

1. **MariaDB seul**
   ```bash
   make build
   docker compose -f srcs/docker-compose.yml up mariadb        # SANS -d : logs en direct
   ```
   Attendu : `[mariadb] premier demarrage : initialisation du datadir`, puis
   `mariadbd: ready for connections`. `Ctrl-C` pour arrêter, puis :
   ```bash
   docker compose -f srcs/docker-compose.yml up -d mariadb
   docker exec -it mariadb mariadb -u wpuser -p -e "SHOW DATABASES;"
   ```

2. **WordPress ensuite**
   ```bash
   docker compose -f srcs/docker-compose.yml up wordpress
   ```
   Attendu : téléchargement du cœur, `Success: WordPress installed successfully.`, création du
   second utilisateur, puis `fpm is running`.

3. **NGINX enfin**
   ```bash
   docker compose -f srcs/docker-compose.yml up -d
   curl -Ik https://rafeger.42.fr
   ```

**Tableau de débogage — les pannes réelles et leur cause**

| Symptôme | Cause probable | Vérification / correctif |
|---|---|---|
| `failed to mount local volume: no such file or directory` | `/home/rafeger/data/...` n'existe pas | `make` le crée ; sinon `mkdir -p` |
| mariadb redémarre en boucle | erreur dans le SQL d'init, ou `set -e` déclenché | `docker compose logs mariadb` ; `docker compose down -v` puis `sudo rm -rf` du datadir et on recommence |
| `Access denied for user 'wpuser'` | mot de passe avec un `\n` final | crée les secrets avec `printf '%s'`, et vérifie le `tr -d` dans l'entrypoint |
| `Can't connect to MySQL server on 'mariadb'` | `bind-address` resté à 127.0.0.1, ou mariadb pas encore prête | `docker exec mariadb ss -lntp` ; vérifier le healthcheck |
| nginx : **502 Bad Gateway** | php-fpm injoignable | `docker exec wordpress ss -lntp \| grep 9000` ; vérifier `listen = 0.0.0.0:9000` |
| nginx : **404** sur `/` | le volume WordPress est vide côté nginx | `docker exec nginx ls /var/www/html` ; les deux services doivent monter `wordpress_data` |
| nginx : le navigateur **télécharge** le `.php` | le bloc `location ~ \.php$` ne matche pas | `docker exec nginx nginx -T \| grep -A5 fastcgi_pass` |
| `Error establishing a database connection` | mauvais `WP_DB_HOST` dans `wp-config.php` | `docker exec wordpress wp config get DB_HOST --allow-root` |
| Boucle de redirection HTTPS | `siteurl` enregistré en `http://` | `docker exec wordpress wp option get siteurl --allow-root` → doit être `https://rafeger.42.fr` |
| Le conteneur s'arrête tout de suite | le processus s'est daemonisé | vérifier `daemon off;` / `-F` / `exec "$@"` |

**Commandes de débogage à connaître**
```bash
docker compose -f srcs/docker-compose.yml logs -f <service>
docker exec -it <service> sh                 # shell dans le conteneur
docker exec -it <service> ps -o pid,user,cmd # qui est PID 1 ?
docker inspect <service> | less              # config effective
docker network inspect inception_inception   # qui est sur le réseau, avec quelle IP
docker volume inspect inception_mariadb_data # Mountpoint réel
docker exec -it nginx getent hosts wordpress # le DNS interne fonctionne-t-il ?
```

**Repartir de zéro proprement** (à faire souvent pendant le développement)
```bash
make fclean && make
```

---

## T20 — Checklist de conformité au sujet

**OBJ** : passer en revue **chaque phrase** du sujet et prouver qu'elle est satisfaite.
Fais ce ticket **avant** de demander la correction, avec le sujet ouvert à côté.

```
[ ] Le projet tourne dans une VM.
[ ] Makefile à la racine ; tous les fichiers de config dans srcs/.
[ ] `make` construit les images via docker-compose.yml.
[ ] docker compose utilisé (pas docker run à la main).
[ ] 3 services, 3 conteneurs, 3 images, chaque image porte le nom de son service.
[ ] Toutes les images FROM debian:bookworm (avant-dernière stable). Aucun `latest`.
[ ] Un Dockerfile par service, écrit par moi, appelé par le compose.
[ ] Aucune image toute faite tirée depuis DockerHub (sauf debian).
[ ] nginx : TLSv1.2/1.3 seulement.
[ ] wordpress : WordPress + php-fpm, SANS nginx dans le conteneur.
[ ] mariadb : MariaDB seul, SANS nginx.
[ ] Volume nommé pour la base de données.
[ ] Volume nommé pour les fichiers du site.
[ ] Aucun bind mount dans services.*.volumes (seulement des NOMS de volumes).
[ ] Les deux volumes stockent dans /home/rafeger/data.
[ ] Un docker-network relie les conteneurs ; la ligne `networks:` est présente.
[ ] restart: always sur les 3 services.
[ ] Aucun tail -f / sleep infinity / while true / bash comme commande principale.
[ ] PID 1 = le vrai service dans chaque conteneur.
[ ] network: host, --link et links: absents.
[ ] 2 utilisateurs WordPress, dont 1 administrateur.
[ ] Le login admin ne contient ni admin ni administrator.
[ ] rafeger.42.fr pointe vers l'IP locale.
[ ] Aucun mot de passe dans les Dockerfiles.
[ ] Variables d'environnement utilisées ; fichier .env présent.
[ ] Docker secrets utilisés pour les mots de passe.
[ ] .env et secrets/ ignorés par git ; historique git propre.
[ ] nginx est le SEUL point d'entrée, via le port 443 UNIQUEMENT.
[ ] README.md conforme (T23).
[ ] USER_DOC.md présent (T24).
[ ] DEV_DOC.md présent (T25).
```

**Commandes de preuve, à enchaîner devant le correcteur**
```bash
# PID 1 de chaque conteneur
for c in nginx wordpress mariadb; do echo "== $c"; docker exec $c ps -o pid,cmd | head -3; done

# un seul port publié dans toute l'infra
docker compose -f srcs/docker-compose.yml ps

# volumes nommés et leur emplacement réel
docker volume ls
docker volume inspect inception_mariadb_data --format '{{.Name}} -> {{.Mountpoint}} {{.Options}}'

# réseau dédié
docker network inspect inception_inception --format '{{.Name}} {{.Driver}}'

# aucun mot de passe dans les images
docker history --no-trunc mariadb:1.0 | grep -i pass    # rien

# secrets montés en lecture seule
docker exec mariadb ls -l /run/secrets/
docker exec mariadb mount | grep secrets                 # ro
```

---

## T21 — Tests de persistance et de redémarrage

**OBJ** : prouver que les volumes et la politique de restart font leur travail.
Le correcteur **va** faire ces tests.

**ÉTAPES**

1. **Persistance après suppression des conteneurs**
   ```bash
   # créer une trace : publier un article
   docker exec -it wordpress wp post create --post_title="Test persistance" \
        --post_status=publish --path=/var/www/html --allow-root

   make down          # supprime conteneurs + réseau, garde les volumes
   docker ps -a       # plus aucun conteneur du projet
   make up

   docker exec -it wordpress wp post list --path=/var/www/html --allow-root
   # → l'article "Test persistance" est toujours là
   ```

2. **Persistance après redémarrage de la VM**
   ```bash
   sudo reboot
   # au retour :
   docker ps          # les 3 conteneurs sont repartis seuls (restart: always)
   curl -Ik https://rafeger.42.fr
   ```

3. **Redémarrage après crash** — on tue brutalement le processus :
   ```bash
   docker kill --signal=SIGKILL wordpress
   docker ps -a --filter name=wordpress     # quelques secondes plus tard : Up, RESTARTING→Up
   docker inspect wordpress --format '{{.RestartCount}} {{.HostConfig.RestartPolicy.Name}}'
   ```

4. **Les données sont bien sur l'hôte**
   ```bash
   ls -la /home/rafeger/data/wordpress      # wp-config.php, wp-content, ...
   sudo ls -la /home/rafeger/data/mariadb   # ibdata1, wordpress/, mysql/, ...
   ```

**SOUTENANCE**
- « Que se passe-t-il exactement à `make down` ? » → conteneurs et réseau supprimés ; les volumes
  nommés survivent, donc les données aussi. C'est la différence entre l'état **éphémère** (le
  conteneur) et l'état **persistant** (le volume) — le cœur de la philosophie Docker : un
  conteneur est jetable, on doit pouvoir le détruire et le recréer sans rien perdre.
- « `always` vs `unless-stopped` vs `on-failure` ? » → `on-failure` redémarre seulement si le
  code de sortie est non nul ; `unless-stopped` redémarre sauf si tu as explicitement fait
  `docker stop` ; `always` redémarre dans tous les cas, y compris au démarrage du démon Docker
  après un reboot. Le sujet demande le redémarrage en cas de crash : `always` couvre tous les
  cas et est le plus simple à défendre.

---

## T22 — Tests TLS

**OBJ** : prouver que seuls TLSv1.2 et TLSv1.3 sont acceptés, et que 443 est la seule porte.

**ÉTAPES**

```bash
# 1. TLS 1.2 et 1.3 acceptés
curl -Ik --tlsv1.2 --tls-max 1.2 https://rafeger.42.fr && echo "TLS1.2 OK"
curl -Ik --tlsv1.3 --tls-max 1.3 https://rafeger.42.fr && echo "TLS1.3 OK"

# 2. TLS 1.0 et 1.1 refusés (la commande DOIT échouer)
curl -Ik --tlsv1.0 --tls-max 1.0 https://rafeger.42.fr ; echo "code retour = $?"
curl -Ik --tlsv1.1 --tls-max 1.1 https://rafeger.42.fr ; echo "code retour = $?"

# 3. Détail de la négociation et du certificat
openssl s_client -connect rafeger.42.fr:443 -servername rafeger.42.fr </dev/null 2>/dev/null \
  | grep -E 'Protocol|Cipher|subject=|issuer='

# 4. Rien d'autre n'est ouvert
ss -lntp | grep -E ':(80|443|3306|9000)'    # seul 443 doit apparaître
docker compose -f srcs/docker-compose.yml ps    # seul nginx a un mapping de port

# 5. Le port 80 est bien mort
curl -I http://rafeger.42.fr                # connexion refusée
```

5. Test dans le navigateur de la VM : ouvre `https://rafeger.42.fr`. Firefox affiche
   « Risque probable de sécurité » → **Avancé** → **Accepter le risque**. C'est **normal** et
   attendu : le certificat est auto-signé. Sache l'expliquer avant que le correcteur ne demande.

**SOUTENANCE**
- « Qu'est-ce que TLS apporte ? » → trois garanties : **confidentialité** (chiffrement
  symétrique de la session), **intégrité** (MAC/AEAD : on détecte toute altération), et
  **authentification du serveur** (via le certificat signé par une CA — c'est ce point qui
  manque avec un certificat auto-signé).
- « Pourquoi interdire TLS 1.0/1.1 ? » → algorithmes obsolètes (SHA-1, RC4, CBC vulnérable à
  BEAST/Lucky13), dépréciés par la RFC 8996 et retirés des navigateurs depuis 2020.
- « Différence entre le handshake 1.2 et 1.3 ? » → TLS 1.3 fait le handshake en **1 aller-retour**
  (au lieu de 2), supprime les suites non-AEAD et impose la **forward secrecy** (ECDHE
  obligatoire). Bonus si tu le sais, pas exigé.

---

# PHASE 5 — Documentation (obligatoire pour la validation)

> Le sujet ajoute un chapitre « Prerequisites for validation » : **trois fichiers Markdown** à la
> racine. Ce n'est pas optionnel. Écris le README **en anglais** (exigence explicite) ;
> `USER_DOC.md` et `DEV_DOC.md` ne sont pas soumis à cette règle mais autant rester cohérent :
> **tout en anglais**.
>
> ⚠️ Dans les trois gabarits ci-dessous, les blocs de commandes sont écrits **sans** délimiteurs
> de code (impossible d'imbriquer des ``` dans un bloc ```). Dans tes vrais fichiers, entoure-les
> de triples backticks, et remplace les `<!-- ... -->` par du contenu rédigé.

---

## T23 — `README.md`

**OBJ** : un README qui coche **exactement** les points listés par le sujet.

**POURQUOI** : le sujet énumère les sections obligatoires. Un README incomplet = un point de
correction raté pour rien.

**Structure imposée** — reprends-la telle quelle :

```markdown
*This project has been created as part of the 42 curriculum by rafeger.*

# Inception

## Description
<!-- Le but du projet + un panorama rapide -->
Inception sets up a small multi-service infrastructure inside a virtual machine, entirely
built with Docker and orchestrated with Docker Compose. Three services — NGINX (TLS reverse
proxy), WordPress with PHP-FPM, and MariaDB — each run in their own container, built from
custom Dockerfiles based on Debian bookworm, connected by a dedicated bridge network, and
backed by two named volumes.

## Instructions
<!-- Prérequis, build, lancement, arrêt -->
### Requirements
- A virtual machine running Debian (tested on Debian ...)
- docker-ce and the docker compose plugin
- `127.0.0.1 rafeger.42.fr` added to `/etc/hosts`
- `srcs/.env` and `secrets/*.txt` created (see DEV_DOC.md)

### Build and run
make            # build the images and start the stack
make ps         # container status
make logs       # follow the logs
make down       # stop and remove containers (data is kept)
make fclean     # remove containers, images, volumes and host data
make re         # rebuild everything from scratch

Then open https://rafeger.42.fr — the certificate is self-signed, your browser will warn you.

## Project description
<!-- LE cœur du README : section explicitement demandée par le sujet -->
### Use of Docker and included sources
<!-- comment les images sont construites, quelles sources amont sont utilisées :
     debian bookworm, paquets apt officiels, wp-cli depuis son dépôt amont -->

### Main design choices
<!-- pourquoi wp-cli, pourquoi l'installation au runtime, pourquoi un healthcheck
     plutôt qu'un sleep, pourquoi bootstrap pour l'init MariaDB -->

### Virtual Machines vs Docker
<!-- voir annexe A1 -->

### Secrets vs Environment Variables
<!-- voir annexe A1 -->

### Docker Network vs Host Network
<!-- voir annexe A1 -->

### Docker Volumes vs Bind Mounts
<!-- voir annexe A1 -->

## Resources
<!-- références classiques + usage de l'IA, EXPLICITEMENT demandé -->
- Docker documentation — https://docs.docker.com/
- Dockerfile best practices — https://docs.docker.com/build/building/best-practices/
- Compose file reference — https://docs.docker.com/reference/compose-file/
- NGINX FastCGI / php-fpm — https://nginx.org/en/docs/http/ngx_http_fastcgi_module.html
- MariaDB documentation — https://mariadb.com/kb/en/documentation/
- WP-CLI handbook — https://make.wordpress.org/cli/handbook/
- Mozilla SSL Configuration Generator — https://ssl-config.mozilla.org/

### Use of AI
<!-- Sois factuel et honnête : pour quelles tâches, quelles parties.
     Exemple : "AI assistance was used to draft the task breakdown and to review the
     entrypoint scripts for PID 1 / signal handling issues. All configuration files were
     written and verified manually, and every command in this README was run and checked
     on the VM." -->
```

**DoD**
- la **toute première ligne** est en italique et dit exactement : *This project has been created
  as part of the 42 curriculum by rafeger.*
- les 4 comparaisons demandées sont chacune une sous-section ;
- la section « Use of AI » existe et est honnête ;
- tout est en anglais.

---

## T24 — `USER_DOC.md`

**OBJ** : documentation **utilisateur / administrateur**. Le sujet liste 5 points ; fais-en
5 sections.

```markdown
# User documentation

## 1. What this stack provides
<!-- Un site WordPress en HTTPS, son panneau d'administration, et la base qui le stocke.
     Décris les 3 services en une phrase chacun, sans jargon Docker. -->

## 2. Starting and stopping the project
| Action | Command |
|---|---|
| Start everything | `make` |
| Stop (keep data) | `make down` |
| Pause / resume | `make stop` / `make start` |
| Reset completely | `make fclean` |

## 3. Accessing the website and the admin panel
- Website: https://rafeger.42.fr
- Admin panel: https://rafeger.42.fr/wp-admin
- The browser shows a certificate warning: the certificate is self-signed for a local
  domain. Accept it to continue.

## 4. Credentials
<!-- N'ÉCRIS AUCUN MOT DE PASSE ICI. Explique OÙ ils sont : -->
- Non-sensitive settings (site title, user names, database name): `srcs/.env`
- Passwords: `secrets/db_root_password.txt`, `secrets/db_password.txt`,
  `secrets/credentials.txt` — never committed to git.
- Inside the containers they are mounted read-only at `/run/secrets/<name>`.
- Two WordPress accounts exist: one administrator and one author. Their logins are in
  `srcs/.env` (`WP_ADMIN_USER`, `WP_USER`); their passwords are in `secrets/credentials.txt`.
- To rotate a password: edit the secret file, then `make fclean && make`.

## 5. Checking that everything runs
make ps                                    # the three containers must be "Up"
curl -Ik https://rafeger.42.fr             # HTTP 200/301
docker compose -f srcs/docker-compose.yml logs --tail=20
docker inspect --format '{{.State.Health.Status}}' mariadb   # healthy
```

---

## T25 — `DEV_DOC.md`

**OBJ** : documentation **développeur**. Le sujet liste 4 points ; fais-en 4 sections.

```markdown
# Developer documentation

## 1. Setting up the environment from scratch
### Prerequisites
<!-- VM Debian, docker-ce + compose plugin, make, git, entrée /etc/hosts -->

### Configuration files
Create `srcs/.env` from `srcs/.env.example` and fill in every key:
| Key | Meaning |
|---|---|
| DOMAIN_NAME | the site domain, must match `server_name` and the certificate CN |
| DATA_PATH | host directory backing the named volumes |
| MYSQL_DATABASE / MYSQL_USER | WordPress database and application user |
| WP_VERSION / WP_TITLE / WP_DB_HOST | WordPress core version, site title, DB endpoint |
| WP_ADMIN_USER / WP_ADMIN_EMAIL | administrator account (must not contain "admin") |
| WP_USER / WP_USER_EMAIL | second, non-administrator account |

### Secrets
mkdir -p secrets
printf '%s' '<root password>' > secrets/db_root_password.txt
printf '%s' '<wp db password>' > secrets/db_password.txt
cat > secrets/credentials.txt <<'EOF'
WP_ADMIN_PASSWORD='<admin password>'
WP_USER_PASSWORD='<user password>'
EOF
chmod 600 secrets/*.txt
<!-- Rappelle: printf et non echo, pour éviter le \n final. -->

## 2. Building and running
<!-- Toutes les cibles du Makefile et ce que fait chacune, + la commande compose
     équivalente pour ceux qui veulent contourner make. -->

## 3. Managing containers and volumes
docker compose -f srcs/docker-compose.yml ps
docker compose -f srcs/docker-compose.yml logs -f <service>
docker compose -f srcs/docker-compose.yml build --no-cache <service>
docker compose -f srcs/docker-compose.yml up -d --force-recreate <service>
docker exec -it <service> sh
docker volume ls / docker volume inspect inception_<name>
docker network inspect inception_inception

## 4. Where the data lives and how it persists
| Volume | Container path | Host path | Contents |
|---|---|---|---|
| mariadb_data | /var/lib/mysql | /home/rafeger/data/mariadb | InnoDB files, WordPress DB |
| wordpress_data | /var/www/html (wordpress AND nginx) | /home/rafeger/data/wordpress | WordPress core, themes, plugins, uploads |

<!-- Explique: `down` garde les volumes, `down --volumes` les détruit,
     `make fclean` détruit aussi les répertoires hôte (sudo requis car les fichiers
     appartiennent à l'uid mysql du conteneur). -->
```

**DoD (T23–T25)**
```bash
ls -1 README.md USER_DOC.md DEV_DOC.md
head -1 README.md          # la ligne italique exacte
```
Fais-les relire par quelqu'un qui ne connaît pas le projet : c'est littéralement le critère
énoncé par le sujet (« *to allow anyone unfamiliar with the project… to quickly understand* »).

---

## T26 — Nettoyage final, commit et répétition de la soutenance

**ÉTAPES**

1. **Vérification finale de l'historique git**
   ```bash
   git log --oneline
   git grep -nEi "password *= *['\"][^$]" -- ':!*.md'   # aucune valeur en clair
   # si un secret a DÉJÀ été commité : il faut réécrire l'historique
   # (git filter-repo) ET changer les mots de passe. Ne pas se contenter d'un rm.
   ```
2. **Test « depuis zéro », exactement ce que fera le correcteur**
   ```bash
   make fclean
   docker system df            # plus rien du projet
   make
   # attendre, puis ouvrir https://rafeger.42.fr dans le navigateur de la VM
   ```
3. **Test « clone vierge »** — vérifie que la doc suffit :
   ```bash
   cd /tmp && git clone ~/inception inception-test && cd inception-test
   # recrée .env et secrets/ EN SUIVANT UNIQUEMENT DEV_DOC.md
   make
   ```
   Si tu es bloqué, c'est que `DEV_DOC.md` est incomplet. Corrige-le.
4. **Push sur le dépôt de rendu** (vogsphere), puis re-clone depuis le dépôt de rendu et refais
   l'étape 3. C'est ce dépôt-là qui sera corrigé.
5. **Répétition orale** : reprends l'annexe A1 et réponds à voix haute, sans notes.
   Chronomètre-toi : une réponse doit tenir en 60–90 secondes.

---

# ANNEXE A1 — Les concepts, en questions/réponses

> Les quatre premières sont **explicitement demandées par le sujet** dans le README. Elles
> tomberont.

### 1. Machines virtuelles vs Docker

| | VM | Conteneur |
|---|---|---|
| Ce qui est virtualisé | le **matériel** (hyperviseur) | rien : on **isole** des processus |
| Noyau | un noyau invité complet par VM | le noyau **de l'hôte**, partagé |
| Mécanisme | Type 1 (KVM, ESXi) ou Type 2 (VirtualBox) | **namespaces** + **cgroups** + capabilities |
| Démarrage | dizaines de secondes | millisecondes |
| Empreinte | Go de RAM/disque | Mo |
| Isolation | forte (frontière matérielle) | plus faible (une faille noyau touche tout) |
| OS invité | libre (Windows sur Linux, etc.) | forcément compatible avec le noyau hôte |

Les 6 namespaces à citer : **PID** (arbre de processus propre → d'où le PID 1), **NET** (pile
réseau, interfaces, ports propres), **MNT** (système de fichiers), **UTS** (hostname), **IPC**,
**USER** (mapping d'uid). Les **cgroups** limitent les ressources (CPU, RAM, I/O).
Formule à retenir : *une VM isole un système, un conteneur isole une application.*

### 2. Secrets vs variables d'environnement

| | Variable d'environnement | Secret Docker |
|---|---|---|
| Visible dans `docker inspect` | **oui** | non |
| Visible dans `/proc/<pid>/environ` | **oui**, par tout process du conteneur | non |
| Héritée par les processus enfants | **oui** (fuite dans les logs, les crash reports) | non |
| Emplacement | l'environnement du process | fichier dans `/run/secrets/`, **tmpfs**, lecture seule |
| Dans l'image ? | si `ENV` dans le Dockerfile : **oui, à vie** | jamais |
| Chiffrement au repos | non | non hors Swarm ; **oui** en Swarm |
| Usage | configuration non sensible | mots de passe, clés, tokens |

Dans ce projet : `.env` → domaine, nom de base, noms d'utilisateurs, version de WP.
`secrets/` → les quatre mots de passe. Aucune exception.

### 3. Réseau Docker vs réseau hôte

| | bridge défini par l'utilisateur (`inception`) | `network_mode: host` |
|---|---|---|
| Namespace réseau | propre au conteneur | **celui de l'hôte** |
| IP | une IP privée par conteneur | l'IP de l'hôte |
| Résolution par nom | **oui**, DNS Docker sur 127.0.0.11 | non |
| Exposition | rien, sauf les ports publiés | **tous** les ports du service |
| Conflits de ports | impossibles entre conteneurs | oui |
| Performance réseau | une couche NAT en plus | native |

Le bridge **par défaut** (`docker0`) n'a **pas** le DNS par nom : c'est historiquement pourquoi
`--link` existait. Un bridge **nommé** rend `--link` inutile — d'où son interdiction par le
sujet, qui veut la méthode moderne.

### 4. Volumes Docker vs bind mounts

| | Volume nommé | Bind mount |
|---|---|---|
| Géré par Docker | **oui** (`docker volume ls/inspect/rm`) | non |
| Déclaration | `- mariadb_data:/var/lib/mysql` | `- /home/x/db:/var/lib/mysql` |
| Emplacement | `/var/lib/docker/volumes/...`, ou dirigé par `driver_opts` | chemin hôte arbitraire |
| Portabilité | indépendant de l'arborescence de l'hôte | dépend de l'hôte |
| Drivers | oui (local, NFS, cloud…) | non |
| Cas d'usage | données de production | code source en développement |

**Le point délicat du projet** : le sujet interdit les bind mounts mais impose
`/home/login/data`. La réponse : un **volume nommé** avec `driver_opts: type=none, o=bind,
device=/home/rafeger/data/...`. Ce qu'on manipule dans `services.*.volumes` reste un **nom de
volume** ; c'est au **driver** qu'on indique où stocker. Objet Docker à part entière, listé et
supprimable par l'API — contrairement à un bind mount.

### 5. PID 1, daemons et signaux

- Le premier processus du conteneur est **PID 1** dans son namespace PID.
- Le noyau traite PID 1 spécialement : **les signaux sans handler explicite sont ignorés**, et
  PID 1 doit **récolter les zombies** (processus orphelins).
- `docker stop` → SIGTERM au PID 1, attente de 10 s, puis SIGKILL.
- Donc : si PID 1 est `sh -c "..."` ou `tail -f`, le vrai service ne reçoit **jamais** SIGTERM
  et meurt d'un SIGKILL → buffers non écrits, base potentiellement corrompue.
- D'où les trois règles appliquées dans ce projet :
  1. `CMD`/`ENTRYPOINT` en **forme exec** (tableau JSON), jamais en forme shell ;
  2. **`exec "$@"`** à la fin de chaque entrypoint, pour que le shell soit *remplacé* ;
  3. le service en **avant-plan** : `nginx -g "daemon off;"`, `php-fpm8.2 -F`, `mysqld`.
- Un **daemon** est un processus qui se détache du terminal (double fork, `setsid`, redirection
  des descripteurs). C'est utile sur une machine classique gérée par systemd, et **contre-productif
  dans un conteneur** : Docker *est* le superviseur, il a besoin que le processus reste au
  premier plan pour suivre son état et collecter ses logs.

### 6. Docker : images, couches, cache

- Une **image** est une pile de **couches** en lecture seule (union filesystem, overlay2).
- Chaque instruction d'un Dockerfile produit une couche → d'où le `apt-get update && install &&
  rm -rf /var/lib/apt/lists/*` **en un seul RUN** : supprimer dans une couche ultérieure ne
  récupère pas l'espace, et le contenu reste extractible.
- Un **conteneur** = une image + une fine couche **inscriptible** au-dessus. Elle disparaît avec
  le conteneur : c'est pour ça que les données vont dans des volumes.
- Le **cache de build** invalide une couche et toutes les suivantes dès qu'une instruction ou un
  fichier copié change → mettre les `COPY` qui changent souvent **après** les `RUN` d'install.

### 7. FastCGI

Protocole **binaire** entre serveur web et interpréteur, successeur de CGI (qui forkait un
processus par requête). nginx envoie un jeu de paires clé/valeur ; php-fpm maintient un pool de
workers persistants. La variable décisive est **`SCRIPT_FILENAME`** : le chemin **absolu** du
script tel que **php-fpm** le voit. C'est la raison profonde du volume partagé entre nginx et
wordpress : les deux doivent voir `/var/www/html` avec le même contenu.

---

# ANNEXE A2 — Les pièges qui font échouer le projet

1. **Un mot de passe dans l'historique git.** Échec direct, sans discussion. Vérifie *avant*
   chaque push, et si c'est arrivé : réécris l'historique **et** change les mots de passe.
2. **Un `tail -f`, `sleep infinity` ou `while true`** quelque part, y compris dans un entrypoint.
3. **PID 1 qui n'est pas le service.** Vérifie les trois conteneurs avec `docker exec X ps`.
4. **Le tag `latest`**, dans un `FROM` ou sur une image du projet.
5. **Un bind mount** dans `services.*.volumes` (`- /home/...:/var/...`). Seuls des **noms** de
   volumes sont autorisés là.
6. **`network_mode: host`** ou `links:` — même en commentaire, retire-les.
7. **Publier plus d'un port.** Pas de `ports: - "80:80"`, pas de `3306:3306` « pour déboguer ».
8. **Un login administrateur contenant `admin`.** Relis `WP_ADMIN_USER`.
9. **Un `echo` au lieu d'un `printf`** pour créer un secret → `\n` final → `Access denied`.
10. **Oublier `README.md`, `USER_DOC.md` ou `DEV_DOC.md`** : ils sont dans « Prerequisites for
    validation ».
11. **Un `.env` absent du dépôt sans `.env.example` ni doc** : le correcteur ne peut plus rien
    lancer.
12. **`docker-compose.yml` ailleurs que dans `srcs/`**, ou **Makefile ailleurs qu'à la racine**.
13. **Une base réinitialisée à chaque `make`** : le test `if [ ! -d /var/lib/mysql/mysql ]` doit
    être là, sinon tu perds les données à chaque redémarrage.
14. **Ne pas savoir expliquer son propre code.** C'est le vrai critère de la soutenance :
    chaque ligne de chaque fichier doit pouvoir être justifiée.

---

# ANNEXE A3 — Antisèche de commandes

```bash
# --- Cycle de vie -------------------------------------------------------------
make                  # build + up -d
make down             # supprime conteneurs + réseau (garde les données)
make fclean           # + images + volumes + données hôte
make re               # repart de zéro

# --- Inspection ---------------------------------------------------------------
docker compose -f srcs/docker-compose.yml ps
docker compose -f srcs/docker-compose.yml config     # YAML final, variables substituées
docker compose -f srcs/docker-compose.yml logs -f mariadb
docker stats --no-stream
docker inspect nginx --format '{{json .NetworkSettings.Networks}}' | python3 -m json.tool

# --- Dans un conteneur --------------------------------------------------------
docker exec -it nginx sh
docker exec nginx nginx -T                 # config nginx complète, includes résolus
docker exec wordpress wp option get siteurl --path=/var/www/html --allow-root
docker exec wordpress wp user list --path=/var/www/html --allow-root
docker exec -it mariadb mariadb -u root -p -e "SHOW DATABASES; SELECT user,host FROM mysql.user;"

# --- Réseau -------------------------------------------------------------------
docker network ls
docker network inspect inception_inception
docker exec nginx getent hosts wordpress   # le DNS Docker résout-il ?

# --- Volumes ------------------------------------------------------------------
docker volume ls
docker volume inspect inception_wordpress_data
ls -la /home/rafeger/data/wordpress

# --- Images -------------------------------------------------------------------
docker images
docker history --no-trunc nginx:1.0
docker image inspect mariadb:1.0 --format '{{.Config.Entrypoint}} {{.Config.Cmd}}'
```

---

# Récapitulatif — suivi d'avancement

| # | Ticket | Durée estimée | Fait |
|---|---|---|---|
| T00 | Comprendre l'architecture | 0h30 | ☐ |
| T01 | VM Debian | 1h00 | ☐ |
| T02 | Docker + Compose | 0h30 | ☐ |
| T02bis | Version Debian de base | 0h15 | ☐ |
| T03 | Dépôt + arborescence | 0h15 | ☐ |
| T04 | .gitignore + politique secrets | 0h20 | ☐ |
| T05 | srcs/.env | 0h20 | ☐ |
| T06 | secrets/ | 0h20 | ☐ |
| T07 | /etc/hosts | 0h05 | ☐ |
| T08 | Dossiers de données | 0h05 | ☐ |
| T09 | Dockerfile MariaDB | 0h30 | ☐ |
| T10 | Config MariaDB | 0h20 | ☐ |
| T11 | Entrypoint MariaDB | 1h00 | ☐ |
| T12 | Dockerfile WordPress | 0h40 | ☐ |
| T13 | www.conf php-fpm | 0h20 | ☐ |
| T14 | Entrypoint WordPress | 1h00 | ☐ |
| T15 | Dockerfile NGINX + TLS | 0h40 | ☐ |
| T16 | Config NGINX | 0h40 | ☐ |
| T17 | docker-compose.yml | 1h00 | ☐ |
| T18 | Makefile | 0h40 | ☐ |
| T19 | Build + débogage | 2h00 | ☐ |
| T20 | Checklist de conformité | 0h40 | ☐ |
| T21 | Tests persistance/restart | 0h30 | ☐ |
| T22 | Tests TLS | 0h20 | ☐ |
| T23 | README.md | 1h00 | ☐ |
| T24 | USER_DOC.md | 0h40 | ☐ |
| T25 | DEV_DOC.md | 0h40 | ☐ |
| T26 | Nettoyage + répétition | 1h00 | ☐ |

**Total estimé : ~17 h** hors temps d'apprentissage et de débogage imprévu. Compte 25–30 h si
Docker est nouveau pour toi.
