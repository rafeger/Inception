#!/usr/bin/env bash
#
# check.sh — passe de validation Inception
#
# A lancer depuis la RACINE du projet, dans la VM :
#     ./check.sh              passes 0 a 5 + 7  (non destructif)
#     ./check.sh --full       ajoute la passe 6 (persistance : down/up, kill)
#     ./check.sh --pass 3     une seule passe
#
# Les tests dont les prerequis manquent sont marques [SKIP], pas [KO] :
# tu peux donc le lancer des le T05 et suivre ta progression.

LOGIN="${LOGIN:-rafeger}"
DOMAIN="${DOMAIN:-${LOGIN}.42.fr}"
DATA="${DATA:-/home/${LOGIN}/data}"
COMPOSE_FILE="srcs/docker-compose.yml"
DC="docker compose -f ${COMPOSE_FILE}"

# ------------------------------------------------------------------ affichage

if [ -t 1 ]; then
    G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; B=$'\033[1m'; N=$'\033[0m'
else
    G=''; R=''; Y=''; B=''; N=''
fi

NB_OK=0; NB_KO=0; NB_SKIP=0
FAILED=""

ok()   { printf '  %s[OK]%s   %s\n'      "$G" "$N" "$1"; NB_OK=$((NB_OK+1)); }
ko()   { printf '  %s[KO]%s   %s\n'      "$R" "$N" "$1"; NB_KO=$((NB_KO+1))
         FAILED="${FAILED}\n    - $1"; }
skip() { printf '  %s[SKIP]%s %s — %s\n' "$Y" "$N" "$1" "$2"; NB_SKIP=$((NB_SKIP+1)); }
note() { printf '         %s\n' "$1"; }
title(){ printf '\n%s== %s%s\n' "$B" "$1" "$N"; }

# check "libelle" <commande...>        -> OK si code retour 0
check() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then ok "$label"; else ko "$label"; fi
}

# check_fail "libelle" <commande...>   -> OK si code retour NON nul
check_fail() {
    local label="$1"; shift
    if "$@" >/dev/null 2>&1; then ko "$label"; else ok "$label"; fi
}

# check_out "libelle" "motif_grep" <commande...>
check_out() {
    local label="$1" pattern="$2"; shift 2
    if "$@" 2>/dev/null | grep -qE "$pattern"; then ok "$label"
    else ko "$label"; fi
}

have()       { command -v "$1" >/dev/null 2>&1; }
running()    { [ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }
in_ctr()     { docker exec "$@" 2>/dev/null; }

# ------------------------------------------------------------------ contexte

[ -d srcs ] || {
    printf '%sErreur :%s lance ce script depuis la racine du projet (le dossier qui contient srcs/).\n' "$R" "$N"
    exit 1
}

# Charge le .env s'il existe : MYSQL_USER, WP_ADMIN_USER, etc.
if [ -f srcs/.env ]; then
    set -a; . ./srcs/.env; set +a
fi

ONLY=""; FULL=0
while [ $# -gt 0 ]; do
    case "$1" in
        --full)  FULL=1 ;;
        --pass)  shift; ONLY="$1" ;;
        *)       printf 'option inconnue : %s\n' "$1"; exit 1 ;;
    esac
    shift
done
want() { [ -z "$ONLY" ] || [ "$ONLY" = "$1" ]; }

printf '%sInception — passe de validation%s   (login=%s  domaine=%s)\n' "$B" "$N" "$LOGIN" "$DOMAIN"

# ============================================================================
# PASSE 0 — sans rien lancer                       T01 T02 T03 T04 T07 T08
# ============================================================================
if want 0; then
title "PASSE 0 — environnement, depot, resolution de nom"

# --- T01
[ "$(whoami)" = "$LOGIN" ] && ok "T01 utilisateur = $LOGIN" || ko "T01 utilisateur = $LOGIN (trouve: $(whoami))"
[ "$HOME" = "/home/$LOGIN" ] && ok "T01 HOME = /home/$LOGIN" || ko "T01 HOME = /home/$LOGIN (trouve: $HOME)"
if sudo -n -v >/dev/null 2>&1; then ok "T01 sudo disponible"
else skip "T01 sudo disponible" "mot de passe demande, verifie a la main : sudo -v"; fi

# --- T02
check     "T02 docker installe"                 docker --version
check_out "T02 plugin compose v2"               'v2\.'            docker compose version
if docker info >/dev/null 2>&1; then ok "T02 le demon docker repond"
else ko "T02 le demon docker repond (groupe docker ? newgrp docker)"; fi

# --- T03  arborescence
for f in Makefile "$COMPOSE_FILE" srcs/.env srcs/.env.example; do
    [ -f "$f" ] && ok "T03 present : $f" || ko "T03 manquant : $f"
done
for s in mariadb nginx wordpress; do
    [ -f "srcs/requirements/$s/Dockerfile" ] \
        && ok "T03 present : srcs/requirements/$s/Dockerfile" \
        || ko "T03 manquant : srcs/requirements/$s/Dockerfile"
done
[ -d secrets ] && ok "T03 present : secrets/" || ko "T03 manquant : secrets/"

# --- T04  hygiene git   (le plus important : un echec ici = projet non valide)
if [ -d .git ]; then
    git check-ignore -q srcs/.env \
        && ok "T04 srcs/.env est ignore par git" \
        || ko "T04 srcs/.env N'EST PAS ignore par git"
    if git check-ignore -q srcs/.env.example; then
        ko "T04 srcs/.env.example est ignore — ta regle .gitignore est trop large (.env* ?)"
    else
        ok "T04 srcs/.env.example n'est PAS ignore (il doit etre commite)"
    fi
    git check-ignore -q secrets/ \
        && ok "T04 secrets/ est ignore par git" \
        || ko "T04 secrets/ N'EST PAS ignore par git"

    if git ls-files --error-unmatch srcs/.env >/dev/null 2>&1; then
        ko "T04 srcs/.env est SUIVI par git — a retirer de l'index ET de l'historique"
    else ok "T04 srcs/.env n'est pas suivi par git"; fi
    if git ls-files | grep -q '^secrets/'; then
        ko "T04 des fichiers de secrets/ sont SUIVIS par git"
    else ok "T04 aucun fichier de secrets/ suivi par git"; fi

    if git grep -nEi "password|passwd" -- ':!*.md' ':!.gitignore' >/dev/null 2>&1; then
        ko "T04 'password' apparait dans un fichier suivi (hors .md) — verifie a la main"
        note "git grep -nEi 'password|passwd' -- ':!*.md' ':!.gitignore'"
    else ok "T04 aucun 'password' dans les fichiers suivis (hors .md)"; fi

    if git ls-files | grep -q 'INCEPTION_TICKETS.md'; then
        skip "T04 INCEPTION_TICKETS.md est commite" \
             "il contient des mots de passe d'exemple : a retirer du depot de rendu"
    fi
else
    skip "T04 controles git" "pas de depot git ici"
fi

# --- T07
check_out "T07 $DOMAIN resout vers 127.0.0.1"   '127\.0\.0\.1'   getent hosts "$DOMAIN"

# --- T08
for d in "$DATA/mariadb" "$DATA/wordpress"; do
    [ -d "$d" ] && ok "T08 dossier present : $d" || ko "T08 dossier manquant : $d"
done
fi

# ============================================================================
# PASSE 1 — le compose est ecrit, rien n'est lance          T05 T17
# ============================================================================
if want 1; then
title "PASSE 1 — substitution des variables et validite du compose"

if [ ! -f "$COMPOSE_FILE" ]; then
    skip "PASSE 1" "$COMPOSE_FILE absent (T17 pas encore fait)"
else
    if $DC config --quiet >/dev/null 2>&1; then
        ok "T17 le YAML est valide"
        check_out "T05 DOMAIN_NAME est substitue" "$DOMAIN" $DC config
        if $DC config 2>/dev/null | grep -q '\${'; then
            ko "T05 il reste des \${...} non substitues dans le compose"
        else ok "T05 aucune variable non substituee"; fi
    else
        ko "T17 le YAML est invalide (ou le fichier est vide)"
        skip "T05 substitution des variables" "le compose ne se parse pas"
    fi

    # interdits du sujet
    if grep -rniE 'network_mode|[^_]links:' srcs/ >/dev/null 2>&1; then
        ko "T17 network_mode ou links: trouve dans srcs/ — interdit par le sujet"
    else ok "T17 ni network_mode ni links: dans srcs/"; fi
    if grep -rniE ':latest|FROM +[a-z0-9]+ *$' srcs/ >/dev/null 2>&1; then
        ko "T17 tag 'latest' (ou FROM sans tag) trouve dans srcs/"
    else ok "T17 aucun tag latest"; fi

    # regle du sujet sur le login admin
    case "$(printf '%s' "${WP_ADMIN_USER:-}" | tr 'A-Z' 'a-z')" in
        *admin*) ko "T05 WP_ADMIN_USER contient 'admin' — interdit par le sujet" ;;
        "")      skip "T05 WP_ADMIN_USER" "non defini dans srcs/.env" ;;
        *)       ok "T05 WP_ADMIN_USER ne contient pas 'admin'" ;;
    esac
    if grep -qiE '^[^#]*(password|passwd)' srcs/.env 2>/dev/null; then
        ko "T05 srcs/.env contient une cle 'password' — les mots de passe vont dans secrets/"
    else ok "T05 aucun mot de passe dans srcs/.env"; fi

    # coherence .env / .env.example : memes cles des deux cotes
    if [ -f srcs/.env ] && [ -f srcs/.env.example ]; then
        a=$(grep -oE '^[A-Z_]+=' srcs/.env         | sort -u)
        b=$(grep -oE '^[A-Z_]+=' srcs/.env.example | sort -u)
        [ "$a" = "$b" ] && ok "T05 .env et .env.example listent les memes cles" \
                        || ko "T05 .env et .env.example divergent (diff des cles)"
    fi
fi
fi

# ============================================================================
# PASSE 2 — les images                                      T09 T12 T15
# ============================================================================
if want 2; then
title "PASSE 2 — images construites"

for i in mariadb:1.0 wordpress:1.0 nginx:1.0; do
    if docker image inspect "$i" >/dev/null 2>&1; then ok "image presente : $i"
    else skip "image presente : $i" "pas encore construite (make / docker build)"; fi
done

for s in mariadb nginx wordpress; do
    f="srcs/requirements/$s/Dockerfile"
    [ -f "$f" ] || continue
    grep -qE '^FROM +debian:bookworm' "$f" \
        && ok "T09/T12/T15 $s : FROM debian:bookworm" \
        || ko "T09/T12/T15 $s : la base n'est pas debian:bookworm"
    if grep -qiE '^\s*(ENV|ARG).*(PASS|SECRET|PWD)' "$f"; then
        ko "$s/Dockerfile : un mot de passe semble present en ENV/ARG"
    else ok "$s/Dockerfile : aucun mot de passe en ENV/ARG"; fi
    grep -qE '^(CMD|ENTRYPOINT) +\[' "$f" \
        && ok "$s/Dockerfile : CMD/ENTRYPOINT en forme exec (JSON)" \
        || ko "$s/Dockerfile : CMD/ENTRYPOINT en forme shell — PID 1 sera sh"
done

if docker image inspect wordpress:1.0 >/dev/null 2>&1; then
    check_out "T12 extensions PHP presentes" 'mysqli' \
        docker run --rm wordpress:1.0 php -m
    check     "T12 wp-cli fonctionne" \
        docker run --rm wordpress:1.0 wp --info --allow-root
fi
if docker image inspect nginx:1.0 >/dev/null 2>&1; then
    check_out "T15 certificat au nom de $DOMAIN" "$DOMAIN" \
        docker run --rm nginx:1.0 openssl x509 -in /etc/nginx/ssl/inception.crt -noout -subject
fi
fi

# ============================================================================
# PASSE 3 — la stack tourne              T06 T10 T11 T13 T14 T16 T18
# ============================================================================
if want 3; then
title "PASSE 3 — services en fonctionnement"

UP=1
for c in mariadb wordpress nginx; do
    if running "$c"; then ok "conteneur en cours : $c"; else ko "conteneur arrete : $c"; UP=0; fi
done

if [ "$UP" -eq 0 ]; then
    skip "PASSE 3 (suite)" "les 3 conteneurs doivent tourner — lance 'make'"
else
    # --- T11 / T13 : PID 1 = le vrai service.
    # /proc/1/comm plutot que ps : toujours present, aucun paquet requis.
    p1=$(in_ctr mariadb cat /proc/1/comm)
    case "$p1" in mysqld|mariadbd) ok "T11 mariadb : PID 1 = $p1" ;;
                  *) ko "T11 mariadb : PID 1 = '$p1' (attendu mysqld/mariadbd)" ;; esac
    p1=$(in_ctr wordpress cat /proc/1/comm)
    case "$p1" in php-fpm*) ok "T13 wordpress : PID 1 = $p1" ;;
                  *) ko "T13 wordpress : PID 1 = '$p1' (attendu php-fpm)" ;; esac
    p1=$(in_ctr nginx cat /proc/1/comm)
    case "$p1" in nginx) ok "T16 nginx : PID 1 = nginx" ;;
                  *) ko "T16 nginx : PID 1 = '$p1' (attendu nginx)" ;; esac

    # --- T06 : secrets montes, en lecture seule, sans \n final
    for s in db_root_password db_password credentials; do
        in_ctr mariadb test -f "/run/secrets/$s" >/dev/null 2>&1 \
          || in_ctr wordpress test -f "/run/secrets/$s" >/dev/null 2>&1 \
          && ok "T06 secret monte : $s" || ko "T06 secret absent : $s"
    done
    if in_ctr mariadb mount 2>/dev/null | grep -q 'secrets.*ro,'; then
        ok "T06 les secrets sont montes en lecture seule"
    else skip "T06 montage en lecture seule" "commande 'mount' indisponible dans l'image"; fi
    for f in secrets/db_root_password.txt secrets/db_password.txt; do
        [ -f "$f" ] || continue
        if [ "$(tail -c1 "$f" | od -An -tx1 | tr -d ' \n')" = "0a" ]; then
            ko "T06 $f se termine par un retour a la ligne (utilise printf, pas echo)"
        else ok "T06 $f sans \\n final"; fi
    done

    # --- T10 : MariaDB ecoute sur le reseau, pas seulement sur sa loopback
    ROOTPW=$(cat secrets/db_root_password.txt 2>/dev/null)
    if [ -n "$ROOTPW" ]; then
        check_out "T10 bind_address = 0.0.0.0" '0\.0\.0\.0' \
            docker exec mariadb mariadb -u root -p"$ROOTPW" \
                -e "SHOW VARIABLES LIKE 'bind_address';"
    else
        skip "T10 bind_address" "secrets/db_root_password.txt illisible"
    fi

    # --- T11 : la base et l'utilisateur applicatif existent, joignables en TCP
    DBPW=$(cat secrets/db_password.txt 2>/dev/null)
    if [ -n "$DBPW" ] && [ -n "${MYSQL_USER:-}" ]; then
        # -h 127.0.0.1 force le TCP : -h localhost passerait par la socket Unix
        check_out "T11 base '${MYSQL_DATABASE}' joignable en TCP par ${MYSQL_USER}" \
            "${MYSQL_DATABASE}" \
            docker exec mariadb mariadb -h 127.0.0.1 -u "$MYSQL_USER" -p"$DBPW" \
                -e "SHOW DATABASES;"
    else
        skip "T11 acces base" "MYSQL_USER ou secrets/db_password.txt indisponible"
    fi

    # --- T13 : php-fpm ecoute en TCP sur 9000 (et non sur une socket Unix)
    if in_ctr wordpress grep -rhE '^\s*listen\s*=' /etc/php/*/fpm/pool.d/www.conf 2>/dev/null \
         | grep -q '9000'; then
        ok "T13 php-fpm configure sur 0.0.0.0:9000"
    else
        ko "T13 php-fpm n'ecoute pas en TCP sur 9000 (socket Unix ? inatteignable depuis nginx)"
    fi

    # --- T14 : WordPress installe, deux utilisateurs, dont un admin sans 'admin'
    WPU=$(in_ctr wordpress wp user list --path=/var/www/html --allow-root \
            --fields=user_login,roles --format=csv 2>/dev/null | tail -n +2)
    if [ -n "$WPU" ]; then
        n=$(printf '%s\n' "$WPU" | grep -c .)
        [ "$n" -ge 2 ] && ok "T14 $n utilisateurs WordPress" \
                       || ko "T14 $n utilisateur(s) WordPress (2 requis)"
        printf '%s\n' "$WPU" | grep -q 'administrator' \
            && ok "T14 un administrateur existe" || ko "T14 aucun administrateur"
        if printf '%s\n' "$WPU" | grep 'administrator' | cut -d, -f1 \
             | grep -qi 'admin'; then
            ko "T14 le login admin contient 'admin' — echec du projet"
        else ok "T14 le login admin ne contient pas 'admin'"; fi
    else
        ko "T14 'wp user list' ne repond pas (installation incomplete ?)"
    fi

    check "T14 wp-config.php dans le conteneur" \
        docker exec wordpress test -f /var/www/html/wp-config.php
    [ -f "$DATA/wordpress/wp-config.php" ] \
        && ok "T14 wp-config.php visible sur l'hote ($DATA/wordpress)" \
        || ko "T14 wp-config.php absent de $DATA/wordpress — le volume ne pointe pas la"

    # --- T16 : nginx sert le site
    check     "T16 syntaxe nginx valide"   docker exec nginx nginx -t
    check_out "T16 https://$DOMAIN repond" '^HTTP/[0-9.]+ (200|301|302)' \
        curl -Isk --max-time 10 "https://$DOMAIN"
fi
fi

# ============================================================================
# PASSE 4 — conformite au sujet                              T20
# ============================================================================
if want 4; then
title "PASSE 4 — conformite au sujet"

if ! docker network inspect inception_inception >/dev/null 2>&1; then
    skip "PASSE 4" "la stack n'est pas demarree"
else
    check_out "T20 reseau dedie de type bridge" 'bridge' \
        docker network inspect inception_inception --format '{{.Driver}}'

    for v in mariadb_data wordpress_data; do
        if docker volume inspect "inception_$v" >/dev/null 2>&1; then
            ok "T20 volume nomme present : inception_$v"
            mp=$(docker volume inspect "inception_$v" --format '{{.Options.device}}' 2>/dev/null)
            case "$mp" in
                "$DATA"*) ok "T20 inception_$v stocke dans $mp" ;;
                ""|"<no value>") ko "T20 inception_$v n'a pas d'option device -> $DATA" ;;
                *) ko "T20 inception_$v stocke hors de $DATA ($mp)" ;;
            esac
        else ko "T20 volume nomme absent : inception_$v"; fi
    done

    # aucun chemin hote dans services.*.volumes : que des NOMS de volumes
    if grep -nE '^\s+-\s+[./~]' "$COMPOSE_FILE" | grep -vq '^\s*#'; then
        ko "T20 un bind mount semble present dans le compose (chemin commencant par . / ~)"
    else ok "T20 aucun bind mount dans services.*.volumes"; fi

    for c in mariadb wordpress nginx; do
        running "$c" || continue
        [ "$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$c")" = "always" ] \
            && ok "T20 $c : restart=always" || ko "T20 $c : restart != always"
    done

    # un seul port publie dans toute l'infra : le 443 de nginx
    pub=$(docker ps --filter label=com.docker.compose.project=inception \
            --format '{{.Names}} {{.Ports}}' | grep '\->' )
    n=$(printf '%s\n' "$pub" | grep -c '\->')
    if [ "$n" -eq 1 ] && printf '%s' "$pub" | grep -q 'nginx.*443'; then
        ok "T20 un seul port publie : 443 sur nginx"
    else
        ko "T20 $n port(s) publie(s) — un seul attendu (443/nginx)"
        printf '%s\n' "$pub" | sed 's/^/         /'
    fi

    for i in mariadb:1.0 wordpress:1.0 nginx:1.0; do
        docker image inspect "$i" >/dev/null 2>&1 || continue
        if docker history --no-trunc "$i" 2>/dev/null | grep -qiE 'password|passwd'; then
            ko "T20 $i : 'password' apparait dans les couches de l'image"
        else ok "T20 $i : aucun mot de passe dans les couches"; fi
    done

    # aucun hack pour garder un conteneur vivant
    if grep -rniE 'tail -f|sleep infinity|while true' srcs/ >/dev/null 2>&1; then
        ko "T20 tail -f / sleep infinity / while true trouve dans srcs/"
    else ok "T20 aucun tail -f / sleep infinity / while true"; fi
fi
fi

# ============================================================================
# PASSE 5 — TLS et point d'entree unique                     T22
# ============================================================================
if want 5; then
title "PASSE 5 — TLS et point d'entree"

if ! running nginx; then
    skip "PASSE 5" "nginx n'est pas demarre"
else
    check      "T22 TLS 1.2 accepte" curl -Isk --max-time 10 --tlsv1.2 --tls-max 1.2 "https://$DOMAIN"
    check      "T22 TLS 1.3 accepte" curl -Isk --max-time 10 --tlsv1.3 --tls-max 1.3 "https://$DOMAIN"
    check_fail "T22 TLS 1.0 refuse"  curl -Isk --max-time 10 --tlsv1.0 --tls-max 1.0 "https://$DOMAIN"
    check_fail "T22 TLS 1.1 refuse"  curl -Isk --max-time 10 --tlsv1.1 --tls-max 1.1 "https://$DOMAIN"
    note "les deux refus peuvent venir de ton curl/OpenSSL local plutot que de nginx ;"
    note "la preuve qui ne triche pas est le 'ssl_protocols' de ta conf nginx."

    if grep -rhE '^\s*ssl_protocols' srcs/requirements/nginx/ 2>/dev/null \
         | grep -q 'TLSv1.2.*TLSv1.3\|TLSv1.3.*TLSv1.2'; then
        ok "T22 ssl_protocols = TLSv1.2 TLSv1.3 dans la conf nginx"
    else
        ko "T22 ssl_protocols n'est pas exactement 'TLSv1.2 TLSv1.3'"
    fi

    check_out "T22 protocole negocie en TLSv1.2/1.3" 'TLSv1\.[23]' \
        sh -c "openssl s_client -connect $DOMAIN:443 -servername $DOMAIN </dev/null 2>/dev/null | grep Protocol"

    check_fail "T22 le port 80 est ferme" curl -Is --max-time 5 "http://$DOMAIN"

    if have ss; then
        n=$(ss -lntH 2>/dev/null | grep -cE ':(3306|9000)\b')
        [ "$n" -eq 0 ] && ok "T22 ni 3306 ni 9000 ouverts sur l'hote" \
                       || ko "T22 $n port(s) de service ouvert(s) sur l'hote"
    else
        skip "T22 ports ouverts sur l'hote" "ss absent"
    fi
fi
fi

# ============================================================================
# PASSE 6 — persistance (DESTRUCTIF, --full)                 T21
# ============================================================================
if want 6 && [ "$FULL" -eq 1 ]; then
title "PASSE 6 — persistance et redemarrage (destructif)"

if ! running wordpress; then
    skip "PASSE 6" "la stack n'est pas demarree"
else
    STAMP="check-persistance-$(date +%s)"
    if docker exec wordpress wp post create --post_title="$STAMP" --post_status=publish \
            --path=/var/www/html --allow-root >/dev/null 2>&1; then
        ok "T21 article temoin cree"
        $DC down >/dev/null 2>&1
        n=$(docker ps -aq --filter label=com.docker.compose.project=inception | grep -c .)
        [ "$n" -eq 0 ] && ok "T21 'down' a supprime tous les conteneurs" \
                       || ko "T21 $n conteneur(s) subsistent apres 'down'"
        $DC up -d >/dev/null 2>&1
        printf '         attente du redemarrage'
        for _ in $(seq 1 30); do
            docker exec wordpress wp core is-installed --path=/var/www/html --allow-root \
                >/dev/null 2>&1 && break
            printf '.'; sleep 2
        done; printf '\n'
        check_out "T21 l'article a survecu a down/up" "$STAMP" \
            docker exec wordpress wp post list --path=/var/www/html --allow-root --format=csv
        docker exec wordpress sh -c \
            "wp post delete \$(wp post list --path=/var/www/html --allow-root --format=ids --post_title='$STAMP') --force --path=/var/www/html --allow-root" \
            >/dev/null 2>&1
    else
        ko "T21 impossible de creer l'article temoin"
    fi

    before=$(docker inspect -f '{{.RestartCount}}' wordpress 2>/dev/null)
    docker kill --signal=SIGKILL wordpress >/dev/null 2>&1
    for _ in $(seq 1 20); do running wordpress && break; sleep 1; done
    if running wordpress; then
        after=$(docker inspect -f '{{.RestartCount}}' wordpress)
        ok "T21 wordpress est reparti seul apres SIGKILL (RestartCount $before -> $after)"
    else
        ko "T21 wordpress n'est pas reparti apres SIGKILL"
    fi

    [ -f "$DATA/wordpress/wp-config.php" ] && ok "T21 donnees WordPress sur l'hote" \
                                           || ko "T21 donnees WordPress absentes de l'hote"
    if sudo -n ls "$DATA/mariadb/ibdata1" >/dev/null 2>&1; then
        ok "T21 donnees MariaDB sur l'hote"
    else
        skip "T21 donnees MariaDB sur l'hote" "sudo requis : sudo ls $DATA/mariadb"
    fi
    note "reste a faire a la main : sudo reboot, puis docker ps -> les 3 conteneurs repartis."
fi
elif want 6; then
title "PASSE 6 — persistance (ignoree)"
skip "T21 tests de persistance" "destructifs : relance avec --full"
fi

# ============================================================================
# PASSE 7 — documentation                              T23 T24 T25
# ============================================================================
if want 7; then
title "PASSE 7 — documentation obligatoire"

for f in README.md USER_DOC.md DEV_DOC.md; do
    [ -f "$f" ] && ok "T23-25 present : $f" || ko "T23-25 manquant : $f"
done

if [ -f README.md ]; then
    exp="*This project has been created as part of the 42 curriculum by ${LOGIN}.*"
    if [ "$(head -1 README.md)" = "$exp" ]; then
        ok "T23 premiere ligne du README exacte"
    else
        ko "T23 premiere ligne du README incorrecte"
        note "attendu : $exp"
        note "trouve  : $(head -1 README.md)"
    fi
    for s in "Virtual Machines" "Secrets" "Host Network" "Bind Mounts"; do
        grep -qi "$s" README.md && ok "T23 comparaison presente : $s" \
                                || ko "T23 comparaison manquante : $s"
    done
    grep -qiE '\bAI\b|artificial intelligence' README.md \
        && ok "T23 section sur l'usage de l'IA presente" \
        || ko "T23 section sur l'usage de l'IA manquante"
fi

if [ -f DEV_DOC.md ]; then
    grep -qi 'env.example' DEV_DOC.md \
        && ok "T25 DEV_DOC explique la creation du .env" \
        || ko "T25 DEV_DOC ne mentionne pas .env.example"
    grep -qi 'secrets' DEV_DOC.md \
        && ok "T25 DEV_DOC explique la creation des secrets" \
        || ko "T25 DEV_DOC ne mentionne pas les secrets"
    grep -qi 'hosts' DEV_DOC.md \
        && ok "T25 DEV_DOC mentionne l'entree /etc/hosts" \
        || ko "T25 DEV_DOC oublie /etc/hosts (non reconstruit par make)"
fi
fi

# ============================================================================
printf '\n%s== Resultat%s\n' "$B" "$N"
printf '  %s%d OK%s   %s%d KO%s   %s%d ignores%s\n' \
       "$G" "$NB_OK" "$N" "$R" "$NB_KO" "$N" "$Y" "$NB_SKIP" "$N"
if [ "$NB_KO" -gt 0 ]; then
    printf '\n  A corriger :%b\n' "$FAILED"
    exit 1
fi
printf '\n  Reste a verifier a la main : navigateur sur https://%s + /wp-admin,\n' "$DOMAIN"
printf '  reboot de la VM, et relecture des trois .md par quelqu%sun d%sexterieur.\n' "'" "'"
exit 0
