# syntax=docker/dockerfile:1.3
# To slim down the final size, this image absoutly need to be squashed at the end of the build
# stages:
# - stage base: install & setup layout
# - stage final(base): copy results from build to a ligther image
#
# remember to sync with the bottom ENV & ARGS sections as those are not persisted in multistages
# ( See https://github.com/moby/moby/issues/37345 && https://github.com/moby/moby/issues/37622#issuecomment-412101935 )
# version: 3
ARG \
    APP_GROUP= \
    APP_TYPE=django \
    APP_USER= \
    BASE=corpusops/ubuntu-bare:focal \
    BASE_DIR=/code \
    BUILD_DEV= \
    CANONICAL_APT_MIRROR='http://archive.canonical.com/ubuntu/' \
    CFLAGS= \
    C_INCLUDE_PATH=/usr/include/gdal/ \
    CPLUS_INCLUDE_PATH=/usr/include/gdal/ \
    CPPLAGS= \
    DEBIAN_FRONTEND=noninteractive \
    DEV_DEPENDENCIES_PATTERN='^#\s*dev dep' \
    DEV_REQS=requirements-dev.txt \
    DOCS_FOLDERS='docs' \
    FORCE_PIP=0 \
    FORCE_PIPENV=0 \
    GPG_KEYS_SERVERS="hkp://p80.pool.sks-keyservers.net:80 hkp://ipv4.pool.sks-keyservers.net hkp://pgp.mit.edu:80" \
    HOST_USER_UID=1000 \
    LANG=fr_FR.utf8 \
    LANGUAGE=fr_FR \
    LDFLAGS= \
    LOCAL_DIR=/local \
    MINIMUM_PIPENV_VERSION=2020.11.15 \
    MINIMUM_PIP_VERSION=20.2.4 \
    MINIMUM_SETUPTOOLS_VERSION=50.3.2 \
    MINIMUM_WHEEL_VERSION=0.35.1 \
    PYTHONUNBUFFERED=1 \
    PY_VER=3.6 \
    REQS=requirements.txt \
    SECRET_KEY=build_time_key_rV2rH3qU0qC1oD6d \
    TZ=Europe/Paris \
    UBUNTU_APT_MIRROR='http://archive.ubuntu.com/ubuntu/' \
    VSCODE_VERSION= \
    WITH_VSCODE=
ARG \
    APP_GROUP="${APP_GROUP:-$APP_TYPE}" \
    APP_USER="${APP_USER:-$APP_TYPE}" \
    HELPERS=$BASE \
    HISTFILE="${LOCAL_DIR}/.bash_history" \
    IPYTHONDIR="${LOCAL_DIR}/.ipython" \
    MYSQL_HISTFILE="${LOCAL_DIR}/.mysql_history" \
    PATH="$BASE_DIR/sbin:$BASE_DIR/bin:$BASE_DIR/venv/bin:$BASE_DIR/.bin:$BASE_DIR/node_modules/.bin:/cops_helpers:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin" \
    PIPENV_REQ="pipenv>=${MINIMUM_PIP_VERSION}" \
    PIP_REQ="pip==${MINIMUM_PIP_VERSION}" \
    PIP_SRC=$BASE_DIR/pipsrc \
    PSQL_HISTORY="${LOCAL_DIR}/.psql_history" \
    SETUPTOOLS_REQ="setuptools>=${MINIMUM_SETUPTOOLS_VERSION}" \
    STRIP_HELPERS="forego confd remco" \
    VIRTUAL_ENV="$BASE_DIR/venv" \
    WHEEL_REQ="wheel>=${MINIMUM_WHEEL_VERSION}"
#
FROM $HELPERS AS helpers
FROM $BASE AS base
USER root
# inherit all global args (think to sync this block with runner stage)
ARG \
    UBUNTU_APT_MIRROR CANONICAL_APT_MIRROR BASE VIRTUAL_ENV BASE_DIR PATH APP_GROUP APP_TYPE APP_USER STRIP_HELPERS \
    BUILD_DEV DEBIAN_FRONTEND HOST_USER_UID LANG LANGUAGE TZ \
    LDFLAGS CFLAGS C_INCLUDE_PATH CPLUS_INCLUDE_PATH CPPLAGS \
    FORCE_PIP FORCE_PIPENV WHEEL_REQ PIPENV_REQ PIP_REQ PIP_SRC SETUPTOOLS_REQ REQS DEV_REQS\
    MINIMUM_PIPENV_VERSION MINIMUM_PIP_VERSION MINIMUM_SETUPTOOLS_VERSION MINIMUM_WHEEL_VERSION \
    PYTHONUNBUFFERED PY_VER DEV_DEPENDENCIES_PATTERN SECRET_KEY \
    LOCAL_DIR HISTFILE PSQL_HISTORY MYSQL_HISTFILE IPYTHONDIR \
    VSCODE_VERSION WITH_VSCODE DOCS_FOLDERS
ENV \
    APP_TYPE="$APP_TYPE" \
    APP_GROUP="${APP_GROUP}" \
    APP_USER="${APP_USER}" \
    BASE_DIR="$BASE_DIR" \
    BUILD_DEV="$BUILD_DEV" \
    CFLAGS="$CFLAGS" \
    C_INCLUDE_PATH="$C_INCLUDE_PATH" \
    CPLUS_INCLUDE_PATH="$CPLUS_INCLUDE_PATH" \
    CPPLAGS="$CPPFLAGS" \
    DEBIAN_FRONTEND="$DEBIAN_FRONTEND" \
    HISTFILE="$HISTFILE" \
    IPYTHONDIR="$IPYTHONDIR" \
    LANG="$LANG" \
    LC_ALL="$LANG" \
    LDFLAGS="$LDFLAGS" \
    LOCAL_DIR="$LOCAL_DIR" \
    MYSQL_HISTFILE="$MYSQL_HISTFILE" \
    PATH="$PATH" \
    PIP_SRC="$PIP_SRC" \
    PSQL_HISTORY="$PSQL_HISTORY" \
    PYTHONUNBUFFERED="$PYTHONUNBUFFERED" \
    PY_VER="$PY_VER" \
    TZ="$TZ" \
    VIRTUAL_ENV="$VIRTUAL_ENV" \
    VSCODE_VERSION="$VSCODE_VERSION" \
    WITH_VSCODE="$WITH_VSCODE"
WORKDIR $BASE_DIR
USER root
ADD apt.txt ./
RUN \
    --mount=type=cache,id=cops${BASE}apt,target=/var/cache/apt \
    --mount=type=cache,id=cops${BASE}list,target=/var/lib/apt/lists \
    bash -c 'set -exo pipefail \
    && if [ "x${UBUNTU_APT_MIRROR}" != "x" ];then echo "Using UBUNTU_APT_MIRROR: ${UBUNTU_APT_MIRROR}";         sed -i -re "s!(deb(-src)?\s+)http.?[:]//(archives?.ubuntu.com/ubuntu/)!\1${UBUNTU_APT_MIRROR}!g" $(find /etc/apt/sources.list* -type f);fi \
    && if [ "x${CANONICAL_APT_MIRROR}" != "x" ];then echo "Using CANONICAL_APT_MIRROR: ${CANONICAL_APT_MIRROR}";sed -i -re "s!(deb(-src)?\s+)http.?[:]//(archives?.canonical.com/ubuntu/)!\1${CANONICAL_APT_MIRROR}!g" $(find /etc/apt/sources.list* -type f);fi \
    && : "$(date): install packages" \
    && rm -f /etc/apt/apt.conf.d/docker-clean || true;echo "Binary::apt::APT::Keep-Downloaded-Packages \"true\";" > /etc/apt/apt.conf.d/keep-cache \
    && osver=$(. /etc/os-release && echo $VERSION_CODENAME ) \
    && : use postgresql.org repos \
    && if (grep -q -E ^postgresql apt.txt);then \
         apt update -qq && apt install -y curl ca-certificates gnupg; \
         ( curl https://www.postgresql.org/media/keys/ACCC4CF8.asc|gpg --dearmor|tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg >/dev/null||true; ); \
         ( echo "deb http://apt.postgresql.org/pub/repos/apt ${osver}-pgdg main" > /etc/apt/sources.list.d/pgdg.list); \
    fi \
    && : "install packages" \
    && apt-get update  -qq \
    && sed -i -re "s/(python-?)[0-9]\.[0-9]+/\1$PY_VER/g" apt.txt \
    && apt-get install -qq -y --no-install-recommends $(sed -re "/$DEV_DEPENDENCIES_PATTERN/,$ d" apt.txt|grep -vE "^\s*#"|tr "\n" " " ) \
    && printf "virtualenv\n${SETUPTOOLS_REQ}\n${PIP_REQ}\n${WHEEL_REQ}\n\n" > pip_reqs.txt \
    && : "$(date) end" \
    '

RUN \
    --mount=type=bind,from=helpers,target=/s \
    bash -c 'set -exo pipefail \
    && : "$(date): setup project user & workdir"\
    && for g in $APP_GROUP;do if !( getent group ${g} &>/dev/null );then groupadd ${g};fi;done \
    && if !( getent passwd ${APP_USER} &>/dev/null );then useradd -g ${APP_GROUP} -ms /bin/bash ${APP_USER} --uid ${HOST_USER_UID} --home-dir /home/${APP_USER};fi \
    && if [ ! -e $LOCAL_DIR ];then mkdir -p $LOCAL_DIR;fi \
    \
    && : "$(date): inject corpusops helpers"\
    && for i in /cops_helpers/ /etc/supervisor.d/ /etc/rsyslog.d/ /etc/rsyslog.conf /etc/rsyslog.conf.frep /etc/cron.d/ /etc/logrotate.d/;do \
        if [ -e /s$i ] || [ -h /s$i ];then rsync -aAH --numeric-ids /s${i} ${i};fi\
        && cd /cops_helpers && rm -rfv $STRIP_HELPERS;\
    done \
    && : "$(date): set locale" \
    && export INSTALL_LOCALES="${LANG}" INSTALL_DEFAULT_LOCALE="${LANG}" \
    && if (command -v setup_locales.sh);then setup_locales.sh; \
       else localedef -i ${LANGUAGE} -c -f ${CHARSET} -A /usr/share/locale/locale.alias ${LANGUAGE}.${CHARSET};\
       fi\
    \
    && : "$(date): setup project timezone"\
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
    && : "$(date) end" \
    '

FROM base AS appsetup
# inherit all global args (think to sync this block with runner stage)
ARG \
    UBUNTU_APT_MIRROR CANONICAL_APT_MIRROR BASE VIRTUAL_ENV BASE_DIR PATH APP_GROUP APP_TYPE APP_USER STRIP_HELPERS \
    BUILD_DEV DEBIAN_FRONTEND HOST_USER_UID LANG LANGUAGE TZ \
    LDFLAGS CFLAGS C_INCLUDE_PATH CPLUS_INCLUDE_PATH CPPLAGS \
    FORCE_PIP FORCE_PIPENV WHEEL_REQ PIPENV_REQ PIP_REQ PIP_SRC SETUPTOOLS_REQ REQS DEV_REQS\
    MINIMUM_PIPENV_VERSION MINIMUM_PIP_VERSION MINIMUM_SETUPTOOLS_VERSION MINIMUM_WHEEL_VERSION \
    PYTHONUNBUFFERED PY_VER DEV_DEPENDENCIES_PATTERN SECRET_KEY \
    LOCAL_DIR HISTFILE PSQL_HISTORY MYSQL_HISTFILE IPYTHONDIR \
    VSCODE_VERSION WITH_VSCODE DOCS_FOLDERS
RUN \
    --mount=type=cache,id=cops${BASE}apt,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,id=cops${BASE}list,target=/var/lib/apt/lists,sharing=locked \
    bash -c 'set -exo pipefail \
    && : "$(date)install dev packages"\
    && apt-get update  -qq \
    && apt-get install -qq -y --no-install-recommends $(cat apt.txt|grep -vE "^\s*#"|tr "\n" " " ) \
    && : "$(date) end"'

# Handle images refresh (rebuild from BASE_IMAGE where BASE_IMAGE is an older version of this image)
RUN for i in keys/* $DOCS_FOLDERS init sys local/${APP_TYPE}-deploy-common .git public/static/* lib src private \
             setup.* *.ini *.rst *.md *.txt README* requirements* \
    ;do if ! ( echo "$i" | egrep -q "pip_reqs.txt" );then ( rm -vrf $i || true );fi;done


# Install now app deps without editable filter
ADD --chown=${APP_TYPE}:${APP_TYPE} lib lib/
# warning: requirements adds are done via the *txt glob
ADD --chown=${APP_TYPE}:${APP_TYPE} setup.* *.ini *.rst *.md *.txt README* requirements* ./
# only bring minimal app for now as we get only deps (CI optims)
ADD --chown=${APP_TYPE}:${APP_TYPE} src      ./src/
ADD --chown=${APP_TYPE}:${APP_TYPE} local/${APP_TYPE}-deploy-common/sys/init.sh init/
ADD --chown=${APP_TYPE}:${APP_TYPE} sys/*t*s*                                   init/
ADD --chown=${APP_TYPE}:${APP_TYPe} sys/ssh/*                                   sys/ssh/
RUN \
    --mount=type=cache,id=cops${APP_TYPE}pip${BUILD_DEV},target=/home/$APP_USER/.cache/pip \
    : "fixperms and ssh configuration" \
    && init/init.sh fixperms \
    && gosu $APP_USER bash -c 'set -exo pipefail \
    && : "$(date): Application installation" \
    && set -x \
    && if [ ! -e venv ];then python${PY_VER} -m venv venv;fi \
    && if [ ! -e requirements ];then mkdir requirements;fi \
    \
    && : "handle both old and new layouts: /code/requirements.txt /code/requirements/requirements.txt" \
    && find -maxdepth 1 -iname "requirement*txt" -or -name "Pip*" | sed -re "s|./||" \
    | while read r;do mv -vf ${r} requirements && ln -fsv requirements/${r};done \
    && python -m pip install -U -r pip_reqs.txt \
    && if [ -e Pipfile ] || [ "x${FORCE_PIPENV}" = "x1" ];then \
        pipenv_args="" \
        && python -m pip install -U ${PIPENV_REQ} \
        && if [[ -n "$BUILD_DEV" ]];then pipenv_args="--dev";fi \
        && pipenv install ${pipenv_args}; \
    elif [ -e ${REQS} ] || [ "x${FORCE_PIP}" = "x1" ];then \
       if [[ -n "$BUILD_DEV" ]] && [ -e ${DEV_REQS} ];then \
        python -m pip install -U -r ${REQS} -r ${DEV_REQS}; \
       else \
        python -m pip install -U -r ${REQS}; \
       fi; \
    fi \
    && if [ "x$WITH_VSCODE" = "x1" ];then python -m pip install -U "ptvsd${VSCODE_VERSION}";fi \
    && if [ -e setup.py ];then python -m pip install --no-deps -e .;fi \
    && : "$(date) end"'
# We make an intermediary init folder to allow to have the
#
# entrypoint mounted as a volume in dev
# cp -frnv => keeps existing stuff, add new stuff, this allows for existing files in project
# overriding the common stuff
# common -> sys
# sys -> init
# ==> init contains files from both local sys and common, common cannot override content from local sys
FROM appsetup AS final
# inherit all global args (think to sync this block with runner stage)
ARG \
    UBUNTU_APT_MIRROR CANONICAL_APT_MIRROR BASE VIRTUAL_ENV BASE_DIR PATH APP_GROUP APP_TYPE APP_USER STRIP_HELPERS \
    BUILD_DEV DEBIAN_FRONTEND HOST_USER_UID LANG LANGUAGE TZ \
    LDFLAGS CFLAGS C_INCLUDE_PATH CPLUS_INCLUDE_PATH CPPLAGS \
    FORCE_PIP FORCE_PIPENV WHEEL_REQ PIPENV_REQ PIP_REQ PIP_SRC SETUPTOOLS_REQ REQS DEV_REQS\
    MINIMUM_PIPENV_VERSION MINIMUM_PIP_VERSION MINIMUM_SETUPTOOLS_VERSION MINIMUM_WHEEL_VERSION \
    PYTHONUNBUFFERED PY_VER DEV_DEPENDENCIES_PATTERN SECRET_KEY \
    LOCAL_DIR HISTFILE PSQL_HISTORY MYSQL_HISTFILE IPYTHONDIR \
    VSCODE_VERSION WITH_VSCODE DOCS_FOLDERS
RUN gosu $APP_TYPE bash -c 'set -exo pipefail \
    && : "$(date) ${APP_TYPE} basic setup" \
    && for i in data public/static public/media;do if [ ! -e $i ];then mkdir -p $i;fi;done \
    \
    && : "$(date) ${APP_TYPE} settings only for building steps" \
    && echo $PATH \
    && cd src && ./manage.py compilemessages \
    && : "$(date) end"'

ADD --chown=${APP_TYPE}:${APP_TYPE} sys                          $BASE_DIR/sys
ADD --chown=${APP_TYPE}:${APP_TYPE} local/${APP_TYPE}-deploy-common/  $BASE_DIR/local/${APP_TYPE}-deploy-common/
ADD --chown=${APP_TYPE}:${APP_TYPE} $DOCS_FOLDERS                $BASE_DIR/docs/

RUN bash -c 'set -exo pipefail \
    && : "inject any SSH config & configure ssh client" \
    && for i in keys sys/ssh;do if [ -e $i ];then cp -rfv $i/. /home/${APP_USER}/.ssh;fi;done \
    && chmod -R 0700 /home/${APP_USER}/.ssh \
    && find /home/${APP_USER}/.ssh -type f               | while read f;do chmod 0600 "$f";done \
    && find /home/${APP_USER}/.ssh -type f -name "*.pub" | while read f;do chmod 0644 "$f";done \
    && chown -R ${APP_USER}:${APP_GROUP} /home/${APP_USER}/.ssh \
    \
    && : "$(date) end"'

USER root
RUN set -e \
    && bash -c 'set -exo pipefail \
    && : "create layout" \
    && mkdir -vp sys init local/${APP_TYPE}-deploy-common/sys \
    && : "if we found a static dist inside the sys directory, it has been injected during" \
    && : "the CI process, we just unpack it" \
    && if [ -e sys/statics ];then : "unpack" \
        && while read f;do tar xf  ${f};done < <(find sys/statics -name "*.tar") \
        && while read f;do tar xJf ${f};done < <(find sys/statics -name "*.txz"  -or -name "*.xz") \
        && while read f;do tar xjf ${f};done < <(find sys/statics -name "*.tbz2" -or -name "*.bz2") \
        && while read f;do tar xzf ${f};done < <(find sys/statics -name "*.tgz"  -or -name "*.gz") \
        && rm -rfv sys/statics;\
    fi \
    && : "assemble init" \
    && : "We make an intermediary init folder to allow to have the entrypoint mounted as a volume in dev" \
    && : "The idea is to have a glue git submodule inside local/$APP_TYPE-deploy-common which           " \
    && : "has most of the common deploy code but any file inside sys/ may override the file             " \
    && : "inside the same location at local/$APP_TYPE-deploy-common/sys/*                               " \
    && for i in init.sh etc sbin scripts;do for j in local/${APP_TYPE}-deploy-common/sys sys;do if [ -e $j/$i ];then cp -frv $j/$i init;fi;done;done \
    \
    && : "connect init.sh" \
    && ln -sf $(pwd)/init/init.sh /init.sh \
    \
    && : "latest fixperms" \
    && init/init.sh fixperms'

WORKDIR $BASE_DIR/src

ARG DBSETUP_SH=https://raw.githubusercontent.com/corpusops/docker-images/master/rootfs/bin/project_dbsetup.sh
ADD --chmod=755 $DBSETUP_SH $BASE_DIR/bin/
ADD --chown=${APP_TYPE}:${APP_TYPE} .git                         $BASE_DIR/.git
CMD "/init.sh"

FROM base AS runner
# inherit all global args (think to sync this block with runner stage)
ARG \
    UBUNTU_APT_MIRROR CANONICAL_APT_MIRROR BASE VIRTUAL_ENV BASE_DIR PATH APP_GROUP APP_TYPE APP_USER STRIP_HELPERS \
    BUILD_DEV DEBIAN_FRONTEND HOST_USER_UID LANG LANGUAGE TZ \
    LDFLAGS CFLAGS C_INCLUDE_PATH CPLUS_INCLUDE_PATH CPPLAGS \
    FORCE_PIP FORCE_PIPENV WHEEL_REQ PIPENV_REQ PIP_REQ PIP_SRC SETUPTOOLS_REQ REQS DEV_REQS\
    MINIMUM_PIPENV_VERSION MINIMUM_PIP_VERSION MINIMUM_SETUPTOOLS_VERSION MINIMUM_WHEEL_VERSION \
    PYTHONUNBUFFERED PY_VER DEV_DEPENDENCIES_PATTERN SECRET_KEY \
    LOCAL_DIR HISTFILE PSQL_HISTORY MYSQL_HISTFILE IPYTHONDIR \
    VSCODE_VERSION WITH_VSCODE DOCS_FOLDERS
ENV \
    APP_TYPE="$APP_TYPE" \
    APP_GROUP="${APP_GROUP}" \
    APP_USER="${APP_USER}" \
    BASE_DIR="$BASE_DIR" \
    BUILD_DEV="$BUILD_DEV" \
    CFLAGS="$CFLAGS" \
    C_INCLUDE_PATH="$C_INCLUDE_PATH" \
    CPLUS_INCLUDE_PATH="$CPLUS_INCLUDE_PATH" \
    CPPLAGS="$CPPFLAGS" \
    DEBIAN_FRONTEND="$DEBIAN_FRONTEND" \
    HISTFILE="$HISTFILE" \
    IPYTHONDIR="$IPYTHONDIR" \
    LANG="$LANG" \
    LC_ALL="$LANG" \
    LDFLAGS="$LDFLAGS" \
    LOCAL_DIR="$LOCAL_DIR" \
    MYSQL_HISTFILE="$MYSQL_HISTFILE" \
    PATH="$PATH" \
    PIP_SRC="$PIP_SRC" \
    PSQL_HISTORY="$PSQL_HISTORY" \
    PYTHONUNBUFFERED="$PYTHONUNBUFFERED" \
    PY_VER="$PY_VER" \
    TZ="$TZ" \
    VIRTUAL_ENV="$VIRTUAL_ENV" \
    VSCODE_VERSION="$VSCODE_VERSION" \
    WITH_VSCODE="$WITH_VSCODE"
RUN --mount=type=bind,from=final,target=/s \
    for i in /init.sh /home/ $BASE_DIR/ \
             /cops_helpers/ /etc/supervisor.d/ /etc/rsyslog.d/ /etc/rsyslog.conf /etc/rsyslog.conf.frep /etc/cron.d/ /etc/logrotate.d/ \
    ;do if [ -e /s${i} ] || [ -h /s${i} ];then rsync -aAH --numeric-ids /s${i} ${i};fi;done \
    && init/init.sh fixperms
WORKDIR $BASE_DIR/src
ADD --chown=${APP_TYPE}:${APP_TYPE} .git                         $BASE_DIR/.git
# image will drop privileges itself using gosu at the end of the entrypoint
CMD "/init.sh"
