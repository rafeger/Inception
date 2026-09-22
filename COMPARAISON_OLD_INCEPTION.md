# `old_inception` (fpaulas-) vs le projet des tickets

Document de travail — comparaison ligne à ligne des deux implémentations.
Lu intégralement : 17 fichiers, `Makefile`, `srcs/.env`, `srcs/docker-compose.yml`,
3 Dockerfiles, 3 `.dockerignore`, `database.cnf`, `setup_db.sh`, `nginx.conf`,
`setup_wordpress.sh`.

> ⚠️ Ce fichier est un document d'étude personnel. **Ajoute-le à ton `.gitignore`** :
> il ne doit pas partir dans le dépôt de rendu.

---

## 1. Verdict en une page

Les deux projets ont la **même architecture** et répondent au même sujet. Ils divergent
sur **trois points qui peuvent coûter la correction**, sur **quatre choix techniques de
fond**, et sur une douzaine de détails de qualité.

| Sujet | `old_inception` | Tickets | Gravité |
|---|---|---|---|
| Mots de passe | en clair dans `srcs/.env`, **aucun `.gitignore`**, pas de `secrets/` | Docker secrets + `.env` sans mot de passe | 🔴 échec possible |
| PID 1 de MariaDB | `sh` (via `mysqld_safe`) | `mysqld` | 🔴 point de contrôle explicite |
| Tag d'image | `image: mariadb` → `mariadb:latest` | `mariadb:1.0` | 🔴 interdit par le sujet |
| Init de la base | `mysqld_safe &` + boucle d'attente + `shutdown` + relance | `mysqld --bootstrap` | 🟠 « hack » visé par le sujet |
| Synchronisation | boucles `sleep` dans les deux entrypoints | `healthcheck` + `condition: service_healthy` | 🟠 |
| Version WordPress | `latest.tar.gz` au **build** | `wp core download --version=` au **runtime** | 🟠 |
| `docker-compose` | v1 (tiret) | v2 (`docker compose`) | 🟠 ne tourne plus |
| Doc obligatoire | aucun `.md` | README + USER_DOC + DEV_DOC | 🟡 chapitre récent du sujet |
| Commentaires | **excellents**, en anglais, partout | corrects | 🟢 à lui prendre |
| Bloc catch-all nginx | `return 444` sur Host inconnu | absent | 🟢 à lui prendre |

---

## 2. Ce qui est commun aux deux projets

C'est la majorité de l'architecture. Ces choix-là sont dictés par le sujet et les deux
projets les respectent de la même façon :

- **3 services, 3 conteneurs, 3 images**, un `Dockerfile` par service, tous `FROM debian:bookworm`.
- **Réseau bridge nommé `inception`**, déclaré explicitement, avec résolution DNS par nom de
  service (`fastcgi_pass wordpress:9000`, `DB_HOST=mariadb`).
- **Volumes nommés** avec `driver: local` + `type: none` + `o: bind` + `device` pointant vers
  `/home/<login>/data/...` — exactement la même astuce pour concilier « volumes nommés
  obligatoires » et « données dans `/home/login/data` ».
- **`restart: always`** sur les trois services.
- **Un seul port publié** : `443:443` sur nginx.
- **Certificat auto-signé** généré par `openssl req -x509 -nodes` dans le Dockerfile nginx,
  avec `CN=<login>.42.fr`.
- **`ssl_protocols TLSv1.2 TLSv1.3;`** — aucune écoute sur le port 80 dans les deux cas.
- **php-fpm écoute en TCP sur `0.0.0.0:9000`**, workers en `www-data`, `--nodaemonize`.
- **wp-cli** pour tout automatiser : `wp config create`, `wp core install`, `wp user create`
  avec `--role=author` pour le second utilisateur, et `--skip-email`.
- **Entrypoints idempotents** : test de `wp-config.php` / `wp core is-installed` avant
  de réinstaller quoi que ce soit.
- **`WP_ADMIN_USER` sans « admin »** (`Death` chez lui, `rafeger` chez toi).
- **Makefile** à la racine avec `all`, `build`, `up`, `down`, `clean`, `fclean`.

**Conclusion** : tu ne construis pas quelque chose de fondamentalement différent. Les
divergences portent sur la **rigueur d'exécution**, pas sur la conception.

---

## 3. Les différences bloquantes

### 3.1 🔴 Les secrets — la divergence la plus importante

**Chez lui** (`srcs/.env`) :

```
DB_PASSWORD=dpass
DB_ROOT_PASSWORD=rpass
WP_ADMIN_PASSWORD=strongscythe42
WP_USER_PASSWORD=bpass
```

Et dans le compose, les quatre services reçoivent **tout** le fichier :

```yaml
env_file:
  - .env
```

Il n'y a **aucun dossier `secrets/`** et **aucun `.gitignore`** dans tout le projet.

**Chez toi** : les quatre mots de passe vivent dans `secrets/*.txt`, montés en lecture seule
dans `/run/secrets/`, lus explicitement par les entrypoints. Le `.env` ne contient aucun
mot de passe et est ignoré par git.

**Pourquoi c'est grave.** Le sujet :

> *It is strongly recommended that you use Docker secrets to store any confidential
> information. **Any credentials, API keys, or passwords found in your Git repository
> (outside of properly configured secrets) will result in project failure.***

Ne pas utiliser les secrets Docker n'est « que » fortement déconseillé. Mais des mots de
passe **dans le dépôt git**, c'est l'échec, sans discussion.

> **Nuance de rigueur** : la copie que tu m'as donnée n'a pas d'historique git (`.git`
> absent), donc je ne peux pas vérifier si ce `.env` a réellement été commité. Ce que je
> constate : le fichier est présent dans le dossier livré et rien dans le projet ne
> l'empêche d'être suivi.

**Effet secondaire, même sans git** : `env_file: .env` injecte les mots de passe dans
**l'environnement du conteneur**. Ils sont donc lisibles par `docker inspect`, par
`/proc/1/environ`, par tout processus du conteneur, et ils fuitent dans les logs de crash.
C'est exactement la comparaison « Secrets vs Environment Variables » que le sujet te
demande de savoir défendre dans ton README.

---

### 3.2 🔴 PID 1 de MariaDB : `sh`, pas `mysqld`

**Chez lui** :

```dockerfile
ENTRYPOINT ["sh", "./setup_db.sh"]
```

et le script se termine par :

```sh
exec mysqld_safe
```

`mysqld_safe` n'est **pas un binaire** : c'est un **script shell** enrobant `mysqld`. Le
`exec` remplace donc `sh` par… un autre `sh`. Résultat : **PID 1 = `sh`**, et `mysqld` n'est
qu'un processus enfant.

**Chez toi** :

```dockerfile
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["mysqld", "--user=mysql"]
```

avec `exec "$@"` à la fin → **PID 1 = `mysqld`**.

**Pourquoi c'est grave.** Le DoD de ton T11 le dit littéralement :

```bash
docker exec -it mariadb ps -o pid,cmd    # PID 1 doit être mysqld, PAS sh
```

C'est un point de contrôle que le correcteur connaît. Et le risque est réel : `docker stop`
envoie `SIGTERM` au PID 1. Un shell PID 1 sans gestionnaire explicite **ignore** le signal
(comportement particulier du noyau pour PID 1), Docker attend 10 s puis envoie `SIGKILL`, et
MariaDB est tuée sans avoir vidé ses tampons → **risque de corruption**.

**Bonus** : `mysqld_safe` a pour rôle de **redémarrer `mysqld` s'il plante**. Combiné à
`restart: always`, ça fait **deux superviseurs empilés**. Si `mysqld` meurt, `mysqld_safe` le
relance en silence : Docker ne voit rien, `restart:` ne se déclenche jamais, et le
`healthcheck` peut rester vert pendant que la base redémarre en boucle. C'est l'inverse de la
philosophie « un conteneur = un processus, l'orchestrateur supervise ».

---

### 3.3 🔴 Le tag `latest`, deux fois

**Dans le compose** :

```yaml
image: mariadb      # → docker tague l'image construite en "mariadb:latest"
image: nginx
image: wordpress
```

Sans tag explicite, Docker utilise `latest`. Le sujet : *« The latest tag is prohibited. »*
C'est un `grep` de trois secondes pour le correcteur.

**Dans le Dockerfile WordPress** :

```dockerfile
RUN curl -o /wordpress.tar.gz https://wordpress.org/latest.tar.gz
```

Ici c'est moins formellement interdit (ce n'est pas un tag Docker), mais c'est le même
problème de fond : deux builds à un mois d'écart ne donnent pas le même site.

**Chez toi** : `image: mariadb:1.0` et `WP_VERSION=7.1.1` figé dans le `.env`.

---

## 4. Les différences structurelles

### 4.1 🟠 L'initialisation de la base : le contraste le plus instructif

**Chez lui** (`setup_db.sh`) :

```sh
mysqld_safe &                      # 1. démarrer le serveur en arrière-plan
until mysqladmin ping ...          # 2. l'attendre avec une boucle + sleep 5
mysql -u root -e "CREATE DATABASE..."   # 3. envoyer le SQL par le réseau/socket
mysqladmin shutdown                # 4. l'arrêter
exec mysqld_safe                   # 5. le redémarrer en avant-plan
```

**Chez toi** (T11) :

```sh
mysqld --user=mysql --bootstrap <<EOSQL
CREATE DATABASE IF NOT EXISTS ...
EOSQL
exec "$@"
```

`--bootstrap` est un mode où `mysqld` lit du SQL sur son **entrée standard**, l'exécute
**sans ouvrir de port ni se daemoniser**, puis se termine. Zéro attente, zéro boucle, zéro
processus fantôme, zéro `sleep`.

**Pourquoi la version des tickets est meilleure à défendre** : le sujet interdit les
« patchs » pour faire tenir un conteneur en vie et vise explicitement ce genre de bricolage.
Un démarrage/arrêt/redémarrage avec boucle d'attente **fonctionne**, mais tu passes trois
minutes à le justifier. `--bootstrap` se justifie en une phrase.

**Et un bug latent chez lui** :

```sh
MAX_RETRIES=2
until mysqladmin ping >/dev/null 2>&1 || [ $COUNT -eq $MAX_RETRIES ]; do
    sleep 5
```

Deux tentatives, 5 secondes chacune : **10 secondes maximum** avant `exit 1`. Sur une VM
lente ou un premier démarrage chargé, l'initialisation échoue. `restart: always` masque le
problème en relançant le conteneur — mais les logs sont alarmants et le comportement est
non déterministe.

### 4.2 🟠 `mysql_install_db` au build

```dockerfile
RUN mysql_install_db --user=mysql --datadir=/var/lib/mysql
```

Il initialise le datadir **pendant la construction de l'image**. Mais `/var/lib/mysql` est un
**point de montage de volume** : au démarrage, Docker monte le volume par-dessus, ce qui
masque le contenu de l'image.

Ça marche chez lui parce que Docker **recopie** le contenu de l'image dans un volume nommé
vide au premier montage. Mais ce comportement n'est **pas fiable** avec un volume adossé à un
chemin hôte via `o=bind` — c'est précisément la remarque du T12 de tes tickets. Son projet
repose donc sur un comportement ambigu.

**Chez toi** : `mariadb-install-db` est exécuté dans l'**entrypoint**, au premier démarrage,
gardé par `if [ ! -d /var/lib/mysql/mysql ]`. Le datadir est créé **dans** le volume, pas
avant lui. Sans ambiguïté.

Même logique pour WordPress : lui extrait `latest.tar.gz` dans le Dockerfile (donc sous le
futur point de montage), toi tu fais `wp core download` au runtime.

### 4.3 🟠 La synchronisation entre conteneurs

**Chez lui**, le compose déclare un healthcheck sur mariadb… mais ne l'utilise pas :

```yaml
depends_on:
  - mariadb          # forme courte : n'attend QUE le démarrage du conteneur
healthcheck:
  test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
```

Le healthcheck ne sert donc qu'à colorer le statut dans `docker ps`. La vraie attente est
faite par une boucle dans `setup_wordpress.sh` :

```sh
MAX_RETRIES=2
while ! mysqladmin ping -h"$DB_HOST" ...; do
    sleep 2
```

**4 secondes maximum**, puis `exit 1` et le conteneur meurt. Ce qui sauve le projet, c'est
`restart: always` : WordPress redémarre en boucle jusqu'à ce que la base réponde. Ça
**fonctionne**, mais par accident — la synchronisation est assurée par une boucle de crash.

**Chez toi** :

```yaml
depends_on:
  mariadb:
    condition: service_healthy
```

Docker ne lance WordPress qu'une fois le healthcheck de MariaDB au vert. C'est déclaratif,
c'est visible dans le compose, et ça répond directement à la question « comment gères-tu
l'ordre de démarrage ? ».

> Détail : son healthcheck `mysqladmin ping -h localhost` sans identifiants renvoie
> « mysqld is alive » même quand l'authentification échoue — il teste que le port répond,
> pas que la base est utilisable. Le tien passe le mot de passe root et teste vraiment.

### 4.4 🟠 wp-cli téléchargé au runtime

```sh
if [ ! -f /usr/local/bin/wp ]; then
    curl -o wp-cli.phar https://raw.githubusercontent.com/...
```

`/usr/local/bin` n'est pas un volume : à chaque **recréation** du conteneur, le téléchargement
recommence. Le démarrage dépend donc de GitHub et d'une connexion réseau. Si tu démarres le
projet devant le correcteur avec un wifi capricieux, le conteneur ne démarre pas.

**Chez toi** : wp-cli est installé dans le Dockerfile, donc **dans l'image**. Aucune
dépendance réseau au démarrage.

---

## 5. Les différences de qualité (non bloquantes mais visibles)

| Point | `old_inception` | Tickets |
|---|---|---|
| Couches `RUN` | jusqu'à 7 dans le Dockerfile WordPress, dont `apt update` et `apt install` **séparés** | un seul `RUN` par groupe logique |
| `--no-install-recommends` | absent partout | présent partout |
| Nettoyage apt | `apt clean` seulement (mariadb), `rm -rf` (nginx), rien (wordpress) | `rm -rf /var/lib/apt/lists/*` systématique |
| `apt-get upgrade -y` | présent dans mariadb et wordpress | absent |
| Paquets de debug | `vim`, `iputils-ping`, `curl` embarqués en prod | aucun |
| `apt` vs `apt-get` | `apt` (déconseillé en script) | `apt-get` |
| `skip-name-resolve` | absent | présent |
| `utf8mb4` | absent → pas d'emoji dans WordPress | présent |
| Config php-fpm | `sed -i` sur le fichier Debian | fichier `www.conf` complet et versionné |
| `catch_workers_output` | absent → erreurs PHP invisibles dans `docker logs` | présent |
| `DATA_PATH` | `${USER}` dans le compose, mais `/home/fpaulas-` **codé en dur** dans le Makefile | `DATA_PATH` du `.env`, une seule source de vérité |
| `fclean` | `docker system prune -a -f --volumes` → **détruit tout Docker sur la machine** | ne supprime que les images du projet |
| Doc obligatoire | aucun `.md` | README, USER_DOC, DEV_DOC |

**Deux points méritent un commentaire.**

**`apt update` et `apt install` dans deux `RUN` séparés** (Dockerfile WordPress) est un
piège classique : la couche `apt update` est mise en cache, et des semaines plus tard
`apt install` s'exécute avec une liste de paquets périmée → erreurs 404 sur des URLs qui
n'existent plus. C'est un build qui casse tout seul, sans qu'on ait rien changé.

**`docker system prune -a -f --volumes`** dans `fclean` supprime **toutes** les images, tous
les volumes et tous les réseaux non utilisés **de la machine entière**, pas seulement ceux du
projet. Sur une VM dédiée c'est sans conséquence ; c'est quand même une habitude dangereuse.

**Sur l'absence de documentation** : sois honnête dans ton jugement. Le chapitre
« Prerequisites for validation » qui impose `USER_DOC.md` et `DEV_DOC.md` est un **ajout
récent** du sujet. Son projet date probablement d'avant. Ce n'est pas une négligence de sa
part, c'est le sujet qui a évolué.

---

## 6. Pourquoi ça diffère : trois causes racines

**① Une approche impérative contre une approche déclarative.**
Chez lui, la logique est dans les scripts : attendre, boucler, redémarrer. Chez toi, elle est
dans le compose : `healthcheck`, `condition: service_healthy`, `restart`. Son code *fait*
les choses ; ton compose les *décrit*. C'est plus court à écrire chez lui, plus court à
**défendre** chez toi.

**② « Ça marche » contre « c'est justifiable ».**
Son projet fonctionne — probablement très bien. Mais plusieurs choix reposent sur des
comportements de repli (`restart: always` qui rattrape une boucle d'attente trop courte,
recopie d'image dans un volume). Une correction 42 ne note pas seulement le résultat : elle
note ta capacité à **expliquer chaque ligne**. Les tickets ont été écrits pour cette
contrainte-là.

**③ Le sujet s'est durci.**
Les trois `.md` obligatoires, et l'insistance sur les secrets, sont plus récents. Son projet
répond à une version antérieure du même énoncé.

---

## 7. Ce que je prendrais chez lui

Cinq choses, par ordre d'intérêt.

### 7.1 ⭐ Le bloc `default_server` qui renvoie 444

C'est le meilleur apport de son projet, et il te manque.

```nginx
server {
    listen 443 ssl default_server;
    server_name _;

    ssl_certificate     /etc/nginx/ssl/inception.crt;
    ssl_certificate_key /etc/nginx/ssl/inception.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    return 444;
}
```

**Ce que ça fait** : toute requête HTTPS dont l'en-tête `Host:` ne vaut pas exactement
`rafeger.42.fr` tombe dans ce bloc. `444` est un **code interne à nginx** : il ferme la
connexion **sans envoyer la moindre réponse**.

**Pourquoi c'est bien** : sans lui, une requête vers `https://127.0.0.1` ou vers l'IP de la VM
est servie par ton unique `server` block — nginx utilisant le premier bloc déclaré comme
serveur par défaut. Ton site répond donc à n'importe quel nom. Avec ce bloc, il ne répond
**que** sur son domaine.

**Ce que ça te donne en soutenance** : une réponse à « qu'est-ce qui garantit que seul
`rafeger.42.fr` est servi ? » qui va plus loin que « j'ai mis un `server_name` ». Tu peux le
démontrer en direct :

```bash
curl -kI https://rafeger.42.fr          # 200
curl -kI https://127.0.0.1              # connexion fermée, aucune réponse
```

### 7.2 ⭐ La densité de commentaires

Son projet est **remarquablement commenté**. Chaque fichier explique le *pourquoi*, pas le
*quoi* :

```sh
# We stop MariaDB that we launch in background, because we'll relaunch again
# as main process of the container just after
```

```nginx
# if unknown extension, we send octet-stream (browser will suggest to download
# the file and not open it)
```

C'est du travail de préparation à la soutenance directement intégré au code. Quand le
correcteur ouvre un fichier et demande « ça, c'est quoi ? », la réponse est à l'écran.
Prends-lui cette habitude : c'est ce qui distingue un projet qu'on a **compris** d'un projet
qu'on a **recopié**.

### 7.3 La cible `exec-%` du Makefile

```makefile
exec-%:
	docker compose -f $(COMPOSE_FILE) exec $* sh
```

`make exec-mariadb`, `make exec-nginx`, `make exec-wordpress`. Une règle à motif, trois
commandes gratuites. Utile en débogage et agréable à montrer.

### 7.4 L'idée d'une cible de démonstration

Sa cible `wp-comments` affiche les 10 derniers commentaires directement depuis la base :

```makefile
wp-comments:
	docker exec -i mariadb mysql -u root -p$$DB_ROOT_PASSWORD wordpress -e "..."
```

L'idée est excellente pour la soutenance : **prouver visuellement que WordPress écrit
réellement dans MariaDB**. Reprends le principe, mais adapte-le à tes secrets :

```makefile
## db-check : prouve que WordPress ecrit bien dans MariaDB
db-check:
	@docker exec -i mariadb mariadb -u root \
		-p"$$(cat secrets/db_root_password.txt)" $(MYSQL_DATABASE) \
		-e "SELECT COUNT(*) AS articles FROM wp_posts WHERE post_status='publish';"
```

### 7.5 Le polissage nginx

```nginx
sendfile on;
keepalive_timeout 65;
gzip on;
```

Trois lignes sans risque, qui montrent que tu as lu la documentation nginx au-delà du
minimum. `sendfile` fait servir les fichiers statiques par le noyau sans copie en espace
utilisateur ; `gzip` compresse le HTML/CSS/JS.

---

## 8. Ce que je ne prendrais surtout pas

- **`env_file: .env`** — c'est ce qui met les mots de passe dans l'environnement des
  conteneurs. Garde ta liste `environment:` explicite : elle est plus verbeuse mais tu
  contrôles exactement ce qui entre dans chaque conteneur.
- **`mysqld_safe`** sous toutes ses formes — casse le PID 1 et double la supervision.
- **Les boucles d'attente avec `sleep`** — c'est le motif que le sujet vise. Ton
  `healthcheck` + `condition: service_healthy` est la bonne réponse.
- **`docker system prune -a --volumes`** dans `fclean`.
- **`apt-get upgrade -y`** dans un Dockerfile — non reproductible et inutile : si tu veux des
  paquets à jour, change d'image de base.
- **`vim` et `iputils-ping`** dans les images finales.

---

## 9. Ce que cette comparaison t'apporte en soutenance

Tu peux désormais répondre à ces questions avec un **contre-exemple concret**, ce qui est
toujours plus convaincant qu'une récitation :

| Question probable | Ce que tu peux dire |
|---|---|
| « Pourquoi des secrets plutôt que le `.env` ? » | « Parce qu'`env_file` met les mots de passe dans `docker inspect` et `/proc/1/environ`. Regardez : `docker inspect mariadb \| grep -i pass` ne renvoie rien chez moi. » |
| « Pourquoi PID 1 compte-t-il ? » | « Un `exec mysqld_safe` laisse `sh` en PID 1, parce que `mysqld_safe` est un script shell. `SIGTERM` n'atteint jamais la base. » |
| « Comment attends-tu MariaDB ? » | « Pas avec un `sleep` : un healthcheck qui teste une vraie connexion authentifiée, plus `condition: service_healthy`. » |
| « Pourquoi installer WordPress au runtime ? » | « Parce que `/var/www/html` est un point de montage : ce qui est copié au build est masqué par le volume. » |
| « Qu'est-ce qui garantit que seul ton domaine est servi ? » | « Un bloc `default_server` qui renvoie 444 sur tout autre `Host`. » |

---

## 10. Une remarque pour la fin

Son projet fonctionne et se lit bien — les commentaires valent mieux que ceux de beaucoup de
rendus. Ses faiblesses ne sont pas des erreurs de compréhension : ce sont des raccourcis
(`mysqld_safe`, les boucles d'attente, `env_file`) qui marchent tant qu'on ne demande pas
pourquoi.

L'usage utile de cette lecture est d'avoir un **point de comparaison** : pour chaque endroit
où vous divergez, tu dois pouvoir dire *pourquoi* tu as choisi l'autre voie. C'est ce que la
section 9 te donne. Recopier ses fichiers te ferait perdre exactement ça — et le correcteur
le repère en deux questions.
