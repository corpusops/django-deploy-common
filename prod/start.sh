#! /bin/bash
NO_START=${NO_START-}
if [[ -z ${NO_START-} ]];then
    while true;do echo "start skipped" >&2;sleep 65535;done
fi
set -e
SCRIPTSDIR="$(dirname $(readlink -f "$0"))"
cd "$SCRIPTSDIR/.."
TOPDIR=$(pwd)
cd src
export APP_TYPE="${APP_TYPE:-docker}"
export APP_USER="${APP_USER:-$APP_TYPE}"
export APP_GROUP="$APP_USER"
export USER_DIRS=". public/media"
for i in $USER_DIRS;do
    if [ ! -e "$i" ];then mkdir -p "$i";fi
    chown $APP_USER:$APP_GROUP "$i"
done
if (find /etc/sudoers* -type f 2>/dev/null);then chown -Rf root:root /etc/sudoers*;fi
# load locales & default env
for i in /etc/environment /etc/default/locale;do if [ -e $i ];then . $i;fi;done
. ../venv/bin/activate
# Regenerate egg-info & be sure to have it in site-packages
regen_egg_info() {
    local f="$1"
    if [ -e "$f" ];then
        local e="$(dirname "$f")"
        echo "Reinstalling egg-info in: $e" >&2
        ( cd "$e" && gosu $APP_USER python setup.py egg_info ; )
    fi
}
set -x
NO_GUNICORN=${NO_GUNICORN-}
DEFAULT_IMAGE_MODE=gunicorn
if [[ -n $NO_GUNICORN ]];then
    DEFAULT_IMAGE_MODE=runserver
fi
export GUNICORN_WORKERS=${GUNICORN_WORKERS:-4}
export DJANGO_LISTEN=${DJANGO_LISTEN:-"0.0.0.0:8000"}
IMAGE_MODES="(gunicorn|runserver|celery_(worker|beat))"
IMAGE_MODE=${IMAGE_MODE:-${DEFAULT_IMAGE_MODE}}
export CELERY_LOGLEVEL=${CELERY_LOGLEVEL:-info}
NO_MIGRATE=${NO_MIGRATE-}
NO_COLLECT_STATIC=${NO_COLLECT_STATIC-}
export DJANGO_WSGI=${DJANGO_WSGI:-project.wsgi}
export DJANGO_CELERY=${DJANGO_CELERY:-project.celery:app}
export DJANGO_CELERY_BROKER="${DJANGO_CELERY_BROKER:-amqp}"
export DJANGO_CELERY_HOST="${DJANGO_CELERY_BROKER:-celery-broker}"
export DJANGO_CELERY_VHOST="${DJANGO_CELERY_VHOST:-}"
if [[ "$DJANGO_CELERY_BROKER" = "amqp" ]];then
    burl="amqp://${RABBITMQ_DEFAULT_USER}:${RABBITMQ_DEFAULT_PASS}@$DJANGO_CELERY_HOST/$DJANGO_CELERY_VHOST/"
elif [[ "$DJANGO_CELERY_BROKER" = "redis" ]];then
    burl="redis://$DJANGO_CELERY_HOST/"
fi
export DJANGO__CELERY_BROKER_URL="${DJANGO__CELERY_BROKER_URL:-$burl}"

#### USAGE
echo "Running in $IMAGE_MODE mode" >&2
if ( echo $1 | egrep -q -- "--help|-h|elp" );then
    echo "args:
-e SHELL_USER=\$USER -e IMAGE_MODE=$IMAGE_MODES \
    docker run <img> run either zeo or zope client in foreground (IMAGE_MODE: $IMAGE_MODES)

-e SHELL_USER=\$USER -e IMAGE_MODE=$IMAGE_MODES \
    docker run <img> \$COMMAND \$ARGS (default user: \$SHELL_USER)
  -> run interactive shell or command inside container environment
  "
  exit 0
fi

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

# regenerate any setup.py found as it can be an egg mounted from a docker volume
# without having a change to be built
while read f;do regen_egg_info "$f";done < <( \
  find "$TOPDIR/setup.py" "$TOPDIR/src" "$TOPDIR/lib" \
    -name setup.py -type f -maxdepth 2 -mindepth 0; )

# Run any migration
if [[ -z ${NO_MIGRATE} ]];then
    gosu $APP_USER ./manage.py migrate --noinput
fi
# Collect statics
if [[ -z ${NO_COLLECT_STATIC} ]];then
    gosu $APP_USER ./manage.py collectstatic --noinput
fi
# Run app
if [[ -z "$@" ]]; then
    if ! ( echo $IMAGE_MODE | egrep -q "$IMAGE_MODES" );then
        echo "Unknown image mode ($IMAGE_MODES): $IMAGE_MODE" >&2
        exit 1
    fi
    if [[ "$IMAGE_MODE" = "runserver" ]]; then
        exec gosu $APP_USER ./manage.py runserver $DJANGO_LISTEN
    else
        cfg="/etc/supervisor.d/$IMAGE_MODE"
        frep /code$cfg:$cfg --overwrite
        SUPERVISORD_CONFIGS="$cfg" exec /bin/supervisord.sh
    fi
else
    _shell $SHELL_USER "$@"
fi
