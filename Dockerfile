# syntax=docker/dockerfile:1.3
# To slim down the final size, this image absoutly need to be squashed at the end of the build
# stages:
# - stage base: install & setup layout
# - stage final(base): copy results from build to a ligther image

ARG BASE=corpusops/ubuntu-bare:bionic
FROM $BASE AS base
USER root
# See https://github.com/nodejs/docker-node/issues/380
ARG APP_GROUP=
ARG APP_TYPE=django
ARG APP_USER=
ARG BUILD_DEV=
ARG CFLAGS=
ARG C_INCLUDE_PATH=/usr/include/gdal/
ARG CPLUS_INCLUDE_PATH=/usr/include/gdal/
ARG CPPLAGS=
ARG DEV_DEPENDENCIES_PATTERN='^#\s*dev dep'
ARG FORCE_PIP="0"
ARG FORCE_PIPENV="0"
ARG GPG_KEYS=B42F6819007F00F88E364FD4036A9C25BF357DD4
ARG GPG_KEYS_SERVERS="hkp://p80.pool.sks-keyservers.net:80 hkp://ipv4.pool.sks-keyservers.net hkp://pgp.mit.edu:80"
ARG HOST_USER_UID=1000
ARG LANG=fr_FR.utf8
ARG LANGUAGE=fr_FR
ARG LDFLAGS=
ARG MINIMUM_PIPENV_VERSION="2020.11.15"
ARG MINIMUM_PIP_VERSION="20.2.4"
ARG MINIMUM_SETUPTOOLS_VERSION="50.3.2"
ARG MINIMUM_WHEEL_VERSION="0.35.1"
ARG PIP_SRC=/code/pipsrc
ARG PY_VER=3.6
ARG TZ=Europe/Paris
ARG VSCODE_VERSION=
ARG WITH_VSCODE=0
#
ARG SETUPTOOLS_REQ="setuptools>=${MINIMUM_SETUPTOOLS_VERSION}"
ARG PIP_REQ="pip==${MINIMUM_PIP_VERSION}"
ARG PIPENV_REQ="pipenv>=${MINIMUM_PIP_VERSION}"
ARG WHEEL_REQ="wheel>=${MINIMUM_WHEEL_VERSION}"
#
ENV \
    APP_TYPE="$APP_TYPE" \
    BUILD_DEV="$BUILD_DEV" \
    APP_USER="${APP_USER:-$APP_TYPE}" \
    APP_GROUP="${APP_GROUP:-$APP_TYPE}" \
    CFLAGS="$CFLAGS" \
    C_INCLUDE_PATH="$C_INCLUDE_PATH" \
    CPLUS_INCLUDE_PATH="$CPLUS_INCLUDE_PATH" \
    CPPLAGS="$CPPFLAGS" \
    DEBIAN_FRONTEND="noninteractive" \
    LANG="$LANG" \
    LC_ALL="$LANG" \
    LDFLAGS="$LDFLAGS" \
    PIP_SRC="$PIP_SRC" \
    PYTHONUNBUFFERED="1" \
    PY_VER="$PY_VER" \
    VSCODE_VERSION="$VSCODE_VERSION" \
    WITH_VSCODE="$WITH_VSCODE"
WORKDIR /code
ADD apt.txt ./
RUN bash -exc ': \
    \
    && : "install packages" \
    && apt-get update  -qq \
    && apt-get install -qq -y $(sed -re "/$DEV_DEPENDENCIES_PATTERN/,$ d" apt.txt|grep -vE "^\s*#"|tr "\n" " " ) \
    && apt-get clean all && apt-get autoclean && rm -rf /var/lib/apt/lists/* \
  '

RUN bash -exc ': \
    \
    && : "setup project user & workdir, and ssh">&2\
    && for g in $APP_GROUP;do if !( getent group ${g} &>/dev/null );then groupadd ${g};fi;done \
    && if !( getent passwd ${APP_USER} &>/dev/null );then useradd -g ${APP_GROUP} -ms /bin/bash ${APP_USER} --uid ${HOST_USER_UID} --home-dir /home/${APP_USER};fi \
    && if [ ! -e /home/${APP_USER}/.ssh ];then mkdir /home/${APP_USER}/.ssh;fi \
    && chown -R ${APP_USER}:${APP_GROUP} /home/${APP_USER} . \
    && chmod 2755 . \
    \
    && : "set locale"\
    && export INSTALL_LOCALES="${LANG}" INSTALL_DEFAULT_LOCALE="${LANG}" \
    && if [ -e /usr/bin/setup_locales.sh ];then /usr/bin/setup_locales.sh; \
       elif [ -e /bin/setup_locales.sh ];then /bin/setup_locales.sh; \
       else localedef -i ${LANGUAGE} -c -f ${CHARSET} -A /usr/share/locale/locale.alias ${LANGUAGE}.${CHARSET};\
       fi\
    \
    && : "setup project timezone"\
    && date && : "set correct timezone" \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
    '

FROM base AS appsetup
RUN bash -exc ': \
    && : "install dev packages" \
    && apt-get update  -qq \
    && apt-get install -qq -y $(cat apt.txt|grep -vE "^\s*#"|tr "\n" " " ) \
    && apt-get clean all && apt-get autoclean && rm -rf /var/lib/apt/lists/* \
    '
# Install now python deps without editable filter
ADD --chown=${APP_TYPE}:${APP_TYPE} lib lib/
# warning: requirements adds are done via the *txt glob
ADD --chown=${APP_TYPE}:${APP_TYPE} setup.* *.ini *.rst *.md *.txt README* requirements* /code/
# only bring minimal py for now as we get only deps (CI optims)
ADD --chown=${APP_TYPE}:${APP_TYPE} src /code/src/
ADD --chown=${APP_TYPE}:${APP_TYPE} private  /code/private/

RUN bash -exc ': \
    && date && find /code -not -user ${APP_TYPE} \
    | while read f;do chown ${APP_TYPE}:${APP_TYPE} "$f";done \
    && gosu ${APP_TYPE}:${APP_TYPE} bash -exc "if [ ! -e venv ];then python${PY_VER} -m venv venv;fi \
    && if [ ! -e requirements ];then mkdir requirements;fi \
    && devreqs=requirements-dev.txt && reqs=requirements.txt \
    && : handle retrocompat with both old and new layouts /requirements.txt and /requirements/requirements.txt \
    && find -maxdepth 1 -iname \"requirement*txt\" -or -name \"Pip*\" | sed -re \"s|./||\" \
    | while read r;do mv -vf \${r} requirements && ln -fsv requirements/\${r};done \
    && venv/bin/pip install -U --no-cache-dir \"\${SETUPTOOLS_REQ}\" \"\${WHEEL_REQ}\" \"\${PIPENV_REQ}\" \"\${PIP_REQ}\" \
    && set +x && . venv/bin/activate && set -x\
    && if [ -e Pipfile ] || [ \"x${FORCE_PIPENV}\" = \"x1\" ];then \
        pipenv_args=\"\" \
        && if [[ -n \"$BUILD_DEV\" ]];then pipenv_args=\"--dev\";fi \
        && venv/bin/pipenv install \${pipenv_args}; \
    elif [ -e \${reqs} ] || [ \"x${FORCE_PIP}\" = \"x1\" ];then \
       venv/bin/pip install -U --no-cache-dir -r \${reqs} \
       && if [[ -n \"$BUILD_DEV\" ]] && [ -e \${devreqs} ];then \
           venv/bin/pip install -U --no-cache-dir -r \${reqs} -r \${devreqs}; \
       fi; \
    fi \
    && if [ \"x$WITH_VSCODE\" = \"x1\" ];then  venv/bin/python -m pip install -U \"ptvsd${VSCODE_VERSION}\";fi \
    && if [ -e setup.py ];then venv/bin/python -m pip install --no-deps -e .;fi \
    && date \
    "'

FROM appsetup AS final
# ${APP_TYPE} basic setup
RUN gosu ${APP_TYPE}:${APP_TYPE} bash -exc ': \
    && for i in data public/static public/media;do if [ ! -e $i ];then mkdir -p $i;fi;done \
    && . venv/bin/activate &>/dev/null \
    && cd src \
    && : ${APP_TYPE} settings only for building steps \
    && export SECRET_KEY=build_time_key \
    && : \
    && ./manage.py compilemessages \
    && cd - \
    '
ADD --chown=${APP_TYPE}:${APP_TYPE} sys                          /code/sys
ADD --chown=${APP_TYPE}:${APP_TYPE} local/${APP_TYPE}-deploy-common/  /code/local/${APP_TYPE}-deploy-common/
ADD --chown=${APP_TYPE}:${APP_TYPE} doc*                         /code/docs/

# if we found a static dist inside the sys directory, it has been injected during
# the CI process, we just unpack it
RUN bash -exc ': \
    && : "alter rights and ownerships of ssh keys" \
    && chmod 0700 /home/${APP_USER}/.ssh \
    && (chmod 0600 /home/${APP_USER}/.ssh/* || true) \
    && (chmod 0644 /home/${APP_USER}/.ssh/*.pub || true) \
    && (chown -R ${APP_USER}:${APP_GROUP} /home/${APP_USER}/.ssh/* || true) \
    \
    && : "create layout" \
    && mkdir -vp sys init local/${APP_TYPE}-deploy-common >&2\
    && if [ -e sys/statics ];then\
     while read f;do tar xf ${f};done \
      < <(find sys/statics -name "*.tar"); \
     while read f;do tar xJf ${f};done \
      < <(find sys/statics -name "*.txz" -or -name "*.xz"); \
     while read f;do tar xjf ${f};done \
      < <(find sys/statics -name "*.tbz2" -or -name "*.bz2"); \
     while read f;do tar xzf ${f};done \
      < <(find sys/statics -name "*.tgz" -or -name "*.gz"); \
    fi \
    && rm -rfv sys/statics \
    \
    && : "assemble init" \
    && cp -frnv local/${APP_TYPE}-deploy-common/sys/* sys \
    && cp -frnv sys/* init \
    \
    && : "connect init.sh" \
    && ln -sf $(pwd)/init/init.sh /init.sh \
    \
    && : "latest fixperm" \
    && find $(pwd) -not -user ${APP_USER} | ( set +x;while read f;do chown ${APP_USER}:${PHP_GROUP} "$f";done ) \
    && find sys/etc/cron.d -type f|xargs chmod -vf 0644 \
    '

FROM base AS runner
RUN --mount=type=bind,from=final,target=/s bash -exc ': \
    && for i in /init.sh /home/ /code/;do rsync -aAH --numeric-ids /s${i} ${i};done \
    '
WORKDIR /code/src
ADD --chown=${APP_TYPE}:${APP_TYPE} .git                         /code/.git
# image will drop privileges itself using gosu at the end of the entrypoint
CMD "/init.sh"
