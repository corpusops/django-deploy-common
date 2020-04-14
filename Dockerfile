ARG BASE=corpusops/ubuntu-bare:bionic
FROM $BASE
ENV PYTHONUNBUFFERED 1
ENV DEBIAN_FRONTEND=noninteractive
ARG TZ=Europe/Paris
ARG BUILD_DEV=
ARG PY_VER=3.6
# See https://github.com/nodejs/docker-node/issues/380
ARG GPG_KEYS=B42F6819007F00F88E364FD4036A9C25BF357DD4
ARG GPG_KEYS_SERVERS="hkp://p80.pool.sks-keyservers.net:80 hkp://ipv4.pool.sks-keyservers.net hkp://pgp.mit.edu:80"

WORKDIR /code
ADD apt.txt /code/apt.txt

# setup project timezone, dependencies, user & workdir, gosu
RUN bash -c 'set -ex \
    && : "set correct timezone" \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone \
    && : "install packages" \
    && apt-get update -qq \
    && apt-get install -qq -y $(grep -vE "^\s*#" /code/apt.txt  | tr "\n" " ") \
    && apt-get clean all && apt-get autoclean \
    && : "project user & workdir" \
    && if ! ( getent passwd django &>/dev/null );then useradd -ms /bin/bash django --uid 1000;fi'

ADD --chown=django:django requirements*.txt tox.ini README.md /code/
ADD --chown=django:django src /code/src/
ADD --chown=django:django lib /code/lib/
ADD --chown=django:django private /code/private/

ARG VSCODE_VERSION=
ARG PYCHARM_VERSION=
ENV VSCODE_VERSION=$VSCODE_VERSION
ENV PYCHARM_VERSION=$PYCHARM_VERSION
ARG WITH_VSCODE=0
ENV WITH_VSCODE=$WITH_VSCODE
ARG WITH_PYCHARM=0
ARG CFLAGS=-I/usr/include/gdal
ARG LDFLAGS=
ENV CFLAGS=$CFLAGS
ENV LDFLAGS=$LDFLAGS
ENV WITH_PYCHARM=$WITH_PYCHARM

RUN bash -exc ': \
    && find /code -not -user django \
    | while read f;do chown django:django "$f";done \
    && gosu django:django bash -exc "python${PY_VER} -m venv venv \
    && venv/bin/pip install -U --no-cache-dir setuptools wheel pip \
    && venv/bin/pip install -U --no-cache-dir -r ./requirements.txt \
    && if [[ -n \"$BUILD_DEV\" ]];then \
      venv/bin/pip install -U --no-cache-dir \
      -r ./requirements.txt \
      -r ./requirements-dev.txt\
      && if [ "x$WITH_VSCODE" = "x1" ];then venv/bin/python -m pip install -U "ptvsd${VSCODE_VERSION}";fi \
      && if [ "x$WITH_PYCHARM" = "x1" ];then venv/vin/python -m pip install -U "pydevd-pycharm${PYCHARM_VERSION}";fi; \
    fi \
    && for i in public/static public/media;do if [ ! -e $i ];then mkdir -p $i;fi;done"'

# django basic setup
RUN gosu django:django bash -exc ': \
    && . venv/bin/activate &>/dev/null \
    && cd src \
    && : django settings only for building steps \
    && export SECRET_KEY=build_time_key \
    && : \
    && ./manage.py compilemessages \
    && cd - \
    '

ADD sys                             /code/sys
ADD local/django-deploy-common/     /code/local/django-deploy-common/
RUN bash -exc ': \
    && cd /code && for i in init;do if [ ! -e $i ];then mkdir -p $i;fi;done \
    && find /code -not -user django \
    | while read f;do chown django:django "$f";done \
    && cp -frnv /code/local/django-deploy-common/sys/* sys \
    && cp -frnv sys/* init \
    && ln -sf $(pwd)/init/init.sh /init.sh'

# image will drop privileges itself using gosu
CMD chmod 0644 /etc/cron.d/django

WORKDIR /code/src

CMD "/init.sh"
