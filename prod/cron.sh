#! /bin/bash
# AS root
set -ex
export APP_TYPE="${APP_TYPE:-docker}"
export APP_USER="${APP_USER:-$APP_TYPE}"
export APP_GROUP="$APP_USER"
export USER_DIRS="build ."
for i in $USER_DIRS;do
    if [ ! -e "$i" ];then mkdir -p "$i";fi
    chown $APP_USER:$APP_GROUP "$i"
done
# load locales & default env
for i in /etc/environment /etc/default/locale;do if [ -e $i ];then . $i;fi;done
exec /usr/sbin/cron -f
