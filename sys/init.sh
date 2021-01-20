#!/bin/bash
SDEBUG=${SDEBUG-}
SCRIPTSDIR="$(dirname $(readlink -f "$0"))"
ODIR=$(pwd)
cd "$SCRIPTSDIR/.."
TOPDIR=$(pwd)

# now be in stop-on-error mode
set -e

# export back the gateway ip as a host if ip is available in container
if ( ip -4 route list match 0/0 &>/dev/null );then
    ip -4 route list match 0/0 \
        | awk '{print $3" host.docker.internal"}' >> /etc/hosts
fi

PYCHARM_DIRS="${PYCHARM_DIRS:-"/opt/pycharm /opt/.pycharm /opt/.pycharm_helpers"}"
OPYPATH="${PYTHONPATH-}"
for i in $PYCHARM_DIRS;do
    if [ -e "$i" ];then
        IMAGE_MODE="${FORCE_IMAGE_MODE-pycharm}"
        break
    fi
done

# load locales & default env
# load this first as it resets $PATH
for i in /etc/environment /etc/default/locale;do
    if [ -e $i ];then . $i;fi
done

# load virtualenv if any
for VENV in ./venv ../venv;do
    if [ -e $VENV ];then . $VENV/bin/activate;break;fi
done

PROJECT_DIR=$TOPDIR
if [ -e src ];then
    PROJECT_DIR=$TOPDIR/src
fi
# activate shell debug if SDEBUG is set
if [[ -n $SDEBUG ]];then set -x;fi

DEFAULT_IMAGE_MODE=gunicorn
NO_GUNICORN=${NO_GUNICORN-}
if [[ -n $NO_GUNICORN ]];then
    # retro compat with old setups
    DEFAULT_IMAGE_MODE=fg
fi
export IMAGE_MODE=${IMAGE_MODE:-${DEFAULT_IMAGE_MODE}}
IMAGE_MODES="(cron|gunicorn|fg|celery_worker|celery_beat)"
NO_START=${NO_START-}
DJANGO_CONF_PREFIX="${DJANGO_CONF_PREFIX:-"DJANGO__"}"
DEFAULT_NO_MIGRATE=
DEFAULT_NO_COMPILE_MESSAGES=
DEFAULT_NO_STARTUP_LOGS=
DEFAULT_NO_COLLECT_STATIC=
if [[ -n $@ ]];then
    DEFAULT_NO_STARTUP_LOGS=1
    DEFAULT_NO_MIGRATE=1
    DEFAULT_NO_COMPILE_MESSAGES=1
    DEFAULT_NO_COLLECT_STATIC=1
fi
NO_STARTUP_LOGS=${NO_STARTUP_LOGS-${NO_MIGRATE-$DEFAULT_NO_STARTUP_LOGS}}
NO_MIGRATE=${NO_MIGRATE-$DEFAULT_NO_MIGRATE}
NO_COMPILE_MESSAGES=${NO_COMPILE_MESSAGES-$DEFAULT_NO_COMPILE_MESSAGES}
NO_COLLECT_STATIC=${NO_COLLECT_STATIC-$DEFAULT_NO_COLLECT_STATIC}
NO_IMAGE_SETUP="${NO_IMAGE_SETUP:-"1"}"
FORCE_IMAGE_SETUP="${FORCE_IMAGE_SETUP:-"1"}"
DO_IMAGE_SETUP_MODES="${DO_IMAGE_SETUP_MODES:-"fg|gunicorn"}"
export PIP_SRC=${PIP_SRC:-/code/pipsrc}
NO_PIPENV_INSTALL=${NO_PIPENV_INSTALL-1}
PIPENV_INSTALL_ARGS="${PIPENV_INSTALL_ARGS-"--ignore-pipfile"}"

FINDPERMS_PERMS_DIRS_CANDIDATES="${FINDPERMS_PERMS_DIRS_CANDIDATES:-"public private"}"
FINDPERMS_OWNERSHIP_DIRS_CANDIDATES="${FINDPERMS_OWNERSHIP_DIRS_CANDIDATES:-"public private data"}"
export APP_TYPE="${APP_TYPE:-django}"
export APP_USER="${APP_USER:-$APP_TYPE}"
export APP_GROUP="$APP_USER"
export EXTRA_USER_DIRS="${EXTRA_USER_DIRS-}"
export USER_DIRS="${USER_DIRS:-". public/media data /logs/cron ${EXTRA_USER_DIRS}"}"
SHELL_USER=${SHELL_USER:-${APP_USER}}


# django variables
export GUNICORN_CLASS=${GUNICORN_CLASS:-sync}
export GUNICORN_EXTRA_ARGS="${GUNICORN_EXTRA_ARGS-}"
export GUNICORN_WORKERS=${GUNICORN_WORKERS:-4}
export DJANGO_WSGI=${DJANGO_WSGI:-project.wsgi}
export DJANGO_LISTEN=${DJANGO_LISTEN:-"0.0.0.0:8000"}

# Celery variables
export CELERY_LOGLEVEL=${CELERY_LOGLEVEL:-info}
export DJANGO_CELERY=${DJANGO_CELERY:-project.celery:app}
export DJANGO_CELERY_BROKER="${DJANGO_CELERY_BROKER:-amqp}"
export DJANGO_CELERY_HOST="${DJANGO_CELERY_HOST:-celery-broker}"
export DJANGO_CELERY_VHOST="${DJANGO_CELERY_VHOST:-}"
if ( echo "$DJANGO_CELERY_BROKER" | egrep -q "rabbitmq|amqp" );then
    burl="amqp://${RABBITMQ_DEFAULT_USER}:${RABBITMQ_DEFAULT_PASS}@$DJANGO_CELERY_HOST/$DJANGO_CELERY_VHOST/"
elif [[ "$DJANGO_CELERY_BROKER" = "redis" ]];then
    burl="redis://$DJANGO_CELERY_HOST/"
fi
export DJANGO__CELERY_BROKER_URL="${DJANGO__CELERY_BROKER_URL:-$burl}"


log() {
    echo "$@" >&2;
}

vv() {
    log "$@";"$@";
}

# Regenerate egg-info & be sure to have it in site-packages
regen_egg_info() {
    local f="$1"
    if [ -e "$f" ];then
        local e="$(dirname "$f")"
        echo "Reinstalling egg-info in: $e" >&2
        if ! ( cd "$e" && gosu $APP_USER python setup.py egg_info >/dev/null 2>&1; );then
            ( cd "$e" && gosu $APP_USER python setup.py egg_info 2>&1; )
        fi
    fi
}

#  shell: Run interactive shell inside container
_shell() {
    local pre=""
    local user="$APP_USER"
    if [[ -n $1 ]];then user=$1;shift;fi
    local bargs="$@"
    local NO_VIRTUALENV=${NO_VIRTUALENV-}
    local NO_NVM=${NO_VIRTUALENV-}
    local NVMRC=${NVMRC:-.nvmrc}
    local NVM_PATH=${NVM_PATH:-..}
    local NVM_PATHS=${NVMS_PATH:-${NVM_PATH}}
    local VENV_NAME=${VENV_NAME:-venv}
    local VENV_PATHS=${VENV_PATHS:-./$VENV_NAME ../$VENV_NAME}
    local DOCKER_SHELL=${DOCKER_SHELL-}
    local pre="DOCKER_SHELL=\"$DOCKER_SHELL\";touch \$HOME/.control_bash_rc;
    if [ \"x\$DOCKER_SHELL\" = \"x\" ];then
        if ( bash --version >/dev/null 2>&1 );then \
            DOCKER_SHELL=\"bash\"; else DOCKER_SHELL=\"sh\";fi;
    fi"
    if [[ -z "$NO_NVM" ]];then
        if [[ -n "$pre" ]];then pre=" && $pre";fi
        pre="for i in $NVM_PATHS;do \
        if [ -e \$i/$NVMRC ] && ( nvm --help > /dev/null );then \
            printf \"\ncd \$i && nvm install \
            && nvm use && cd - && break\n\">>\$HOME/.control_bash_rc; \
        fi;done $pre"
    fi
    if [[ -z "$NO_VIRTUALENV" ]];then
        if [[ -n "$pre" ]];then pre=" && $pre";fi
        pre="for i in $VENV_PATHS;do \
        if [ -e \$i/bin/activate ];then \
            printf \"\n. \$i/bin/activate\n\">>\$HOME/.control_bash_rc && break;\
        fi;done $pre"
    fi
    if [[ -z "$bargs" ]];then
        bargs="$pre && if ( echo \"\$DOCKER_SHELL\" | grep -q bash );then \
            exec bash --init-file \$HOME/.control_bash_rc -i;\
            else . \$HOME/.control_bash_rc && exec sh -i;fi"
    else
        bargs="$pre && . \$HOME/.control_bash_rc && \$DOCKER_SHELL -c \"$bargs\""
    fi
    export TERM="$TERM"; export COLUMNS="$COLUMNS"; export LINES="$LINES"
    exec gosu $user sh $( if [[ -z "$bargs" ]];then echo "-i";fi ) -c "$bargs"
}

#  configure: generate configs from template at runtime
configure() {
    if [[ -n $NO_CONFIGURE ]];then return 0;fi
    for i in $USER_DIRS;do
        if [ ! -e "$i" ];then mkdir -p "$i" >&2;fi
        chown $APP_USER:$APP_GROUP "$i"
    done
    if (find /etc/sudoers* -type f >/dev/null 2>&1);then chown -Rf root:root /etc/sudoers*;fi
    # regenerate any setup.py found as it can be an egg mounted from a docker volume
    # without having a chance to be built
    while read f;do regen_egg_info "$f";done < <( \
        find "$TOPDIR/setup.py" "$TOPDIR/src" "$TOPDIR/lib" \
        -maxdepth 2 -mindepth 0 -name setup.py -type f 2>/dev/null; )
    # copy only if not existing template configs from common deploy project
    # and only if we have that common deploy project inside the image
    if [ ! -e etc ];then mkdir etc;fi
    for i in sys/etc local/*deploy-common/etc local/*deploy-common/sys/etc;do
        if [ -d $i ];then cp -rfnv $i/* etc >&2;fi
    done
    # install with envsubst any template file to / (eg: logrotate & cron file)
    for i in $(find etc -name "*.envsubst" -type f 2>/dev/null);do
        di="/$(dirname $i)" \
            && if [ ! -e "$di" ];then mkdir -pv "$di" >&2;fi \
            && cp "$i" "/$i" \
            && CONF_PREFIX="$DJANGO_CONF_PREFIX" confenvsubst.sh "/$i" \
            && rm -f "/$i"
    done
    # install wtih frep any template file to / (eg: logrotate & cron file)
    for i in $(find etc -name "*.frep" -type f 2>/dev/null);do
        d="$(dirname "$i")/$(basename "$i" .frep)" \
            && di="/$(dirname $d)" \
            && if [ ! -e "$di" ];then mkdir -pv "$di" >&2;fi \
            && echo "Generating with frep $i:/$d" >&2 \
            && frep "$i:/$d" --overwrite
    done
}

#  services_setup: when image run in daemon mode: pre start setup
#               like database migrations, etc
services_setup() {
    if [[ -z $NO_IMAGE_SETUP ]];then
        if [[ -n $FORCE_IMAGE_SETUP ]] || ( echo $IMAGE_MODE | egrep -q "$DO_IMAGE_SETUP_MODES" ) ;then
            : "continue services_setup"
        else
            log "No image setup"
            return 0
        fi
    else
        if [[ -n $SDEBUG ]];then
            log "Skip image setup"
            return 0
        fi
    fi
    # alpine linux has /etc/crontabs/ and ubuntu based vixie has /etc/cron.d/
    if [ -e /etc/cron.d ] && [ -e /etc/crontabs ];then cp -fv /etc/crontabs/* /etc/cron.d >&2;fi
    # Run any migration
    if [[ -z ${NO_MIGRATE} ]];then
        ( cd $PROJECT_DIR \
            && gosu $APP_USER ./manage.py migrate --noinput )
    fi
    # Compile gettext messages
    if [[ -z ${NO_COMPILE_MESSAGES} ]];then
        ( cd $PROJECT_DIR \
            && gosu $APP_USER ./manage.py compilemessages )
    fi
    # Collect statics
    if [[ -z ${NO_COLLECT_STATIC} ]];then
        ( cd $PROJECT_DIR \
            && gosu $APP_USER ./manage.py collectstatic --noinput )
    fi
}

fixperms() {
    if [[ -n $NO_FIXPERMS ]];then return 0;fi
    for i in /etc/{crontabs,cron.d} /etc/logrotate.d /etc/supervisor.d;do
        if [ -e $i ];then
            while read f;do
                chown -R root:root "$f"
                chmod 0640 "$f"
            done < <(find "$i" -type f)
        fi
    done
    for i in $USER_DIRS;do
        if [ -e "$i" ];then
            chown $APP_USER:$APP_GROUP "$i"
        fi
    done
    while read f;do chmod 0755 "$f";done < \
        <(find $FINDPERMS_PERMS_DIRS_CANDIDATES -type d \
          -not \( -perm 0755 2>/dev/null\) |sort)
    while read f;do chmod 0644 "$f";done < \
        <(find $FINDPERMS_PERMS_DIRS_CANDIDATES -type f \
          -not \( -perm 0644 2>/dev/null\) |sort)
    while read f;do chown $APP_USER:$APP_USER "$f";done < \
        <(find $FINDPERMS_OWNERSHIP_DIRS_CANDIDATES \
          \( -type d -or -type f \) \
             -and -not \( -user $APP_USER -and -group $APP_GROUP \)  2>/dev/null|sort)
}

#  usage: print this help
usage() {
    drun="docker run --rm -it <img>"
    echo "EX:
$drun [-e NO_COLLECT_STATIC=1] [-e NO_MIGRATE=1] [ -e FORCE_IMAGE_SETUP] [-e IMAGE_MODE=\$mode]
    docker run <img>
        run either django, cron, or celery beat|worker daemon
        (IMAGE_MODE: $IMAGE_MODES)

$drun \$args: run commands with the context ignited inside the container
$drun [ -e FORCE_IMAGE_SETUP=1] [ -e NO_IMAGE_SETUP=1] [-e SHELL_USER=\$ANOTHERUSER] [-e IMAGE_MODE=\$mode] [\$command[ \args]]
    docker run <img> \$COMMAND \$ARGS -> run command
    docker run <img> shell -> interactive shell
(default user: $SHELL_USER)
(default mode: $IMAGE_MODE)

If FORCE_IMAGE_SETUP is set: run migrate/collect static
If NO_IMAGE_SETUP is set: migrate/collect static is skipped, no matter what
If NO_START is set: start an infinite loop doing nothing (for dummy containers in dev)
"
  exit 0
}

do_fg() {
    ( cd $PROJECT_DIR \
        && exec gosu $APP_USER ./manage.py runserver $DJANGO_LISTEN )
}

if ( echo $1 | egrep -q -- "--help|-h|help" );then
    usage
fi

if [[ -n ${NO_START-} ]];then
    while true;do echo "start skipped" >&2;sleep 65535;done
    exit $?
fi

# Run app
pre() {
    configure
    # fixperms may have to be done on first run
    if ! ( services_setup );then
        fixperms
        services_setup
    fi
    fixperms
}

# reinstall in develop any missing editable dep
if [ -e Pipfile ] && ( egrep -q  "editable\s*=\s*true" Pipfile ) && [[ -z "$(ls -1 ${PIP_SRC}/ | grep -vi readme)" ]] && [[ "$NO_PIPENV_INSTALL" != "1" ]];then
    pipenv install $PIPENV_INSTALL_ARGS 1>&2
fi

# only display startup logs when we start in daemon mode
# and try to hide most when starting an (eventually interactive) shell.
if ! ( echo "$NO_STARTUP_LOGS" | egrep -iq "^(no?)?$" );then pre 2>/dev/null;else pre;fi

if [[ $IMAGE_MODE = "pycharm" ]];then
    export VENV=$VENV
    cmdargs="$@"
    for i in ${PYCHARM_DIRS};do if [ -e "$i" ];then chown -Rf $APP_USER "$i";fi;done
    subshell="set -e"
    subshell="$subshell;if [ -e \$VENV ];then . \$VENV/bin/activate;fi"
    subshell="$subshell;cd $ODIR"
    subshell="$subshell;export PYTHONPATH=\"$OPYPATH:\${PYTHONPATH-}·\""
    subshell="$subshell;python $cmdargs"
    exec gosu $APP_USER bash -lc "$subshell"
fi

if [[ -z "$@" ]]; then
    if ! ( echo $IMAGE_MODE | egrep -q "$IMAGE_MODES" );then
        log "Unknown image mode ($IMAGE_MODES): $IMAGE_MODE"
        exit 1
    fi
    log "Running in $IMAGE_MODE mode"
    if [[ "$IMAGE_MODE" = "fg" ]]; then
        do_fg
    else
        cfg="/etc/supervisor.d/$IMAGE_MODE"
        if [ ! -e $cfg ];then
            log "Missing: $cfg"
            exit 1
        fi
        SUPERVISORD_CONFIGS="/etc/supervisor.d/rsyslog $cfg" exec /bin/supervisord.sh
    fi
else
    if [[ "${1-}" = "shell" ]];then shift;fi
    # retrocompat with old images
    cmd="$@"
    if ( echo "$cmd" |egrep -q "tox.*/bin/sh -c tests" );then
        cmd="$( echo "${cmd}"|sed -r \
            -e "s/-c tests/-exc '.\/manage.py test/" -e "s/$/'/g" )"
    fi
    ( cd $PROJECT_DIR && _shell $SHELL_USER "$cmd" )
fi
