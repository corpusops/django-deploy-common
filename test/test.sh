#!/usr/bin/env bash
if [[ -n $DEBUG ]];then set -x;fi
set -e
readlinkf() {
    if ( uname | egrep -iq "darwin|bsd" );then
        if ( which greadlink 2>&1 >/dev/null );then
            greadlink -f "$@"
        elif ( which perl 2>&1 >/dev/null );then
            perl -MCwd -le 'print Cwd::abs_path shift' "$@"
        elif ( which python 2>&1 >/dev/null );then
            python -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$@"
        fi
    else
        val="$(readlink -f "$@")"
        if [[ -z "$val" ]];then
            val=$(readlink "$@")
        fi
        echo "$val"
    fi
}

out=$PWD/test/testproject
if [[ -n "$1" ]] && [ -e $1 ];then
    COOKIECUTTER="$1"
    shift
fi
u=${COOKIECUTTER-}


cd "$(dirname $(readlinkf $0 ))"/..


NO_INSTALL=${NO_INSTALL-}
if [[ -z "$NO_INSTALL" ]];then
deactivate || /bin/true
if [ ! -e local/venv ];then
    virtualenv --python=python3 local/venv
fi
fi

. local/venv/bin/activate

if [[ -z $NO_INSTALL ]];then
pip install -U cookiecutter
fi


NO_REGEN=${NO_REGEN-}
if [[ -z "$NO_REGEN" ]];then
rm -rf test/testproject
if [[ -z "$u" ]];then
    u="$HOME/.cookiecutters/cookiecutter-django"
    if [ ! -e "$u" ];then
        u="https://github.com/corpusops/$(basename $u).git"
    else
        cd "$u"
        git fetch origin
        git pull --rebase
    fi
fi
cookiecutter --no-input -o "$out" -f "$u" \
    name="testproject" \
    py_ver="3.7" \
    nginx_in_dev="y" \
    ssl_in_dev="y" \
    django_ver="2.2.4" \
    django_ver_1="2.2" \
    git_ns="ptest" \
    lname="testproject" \
    out_dir="." \
    tld_domain="mycorp.net" \
    app_type="django" \
    use_submodule_for_deploy_code="y" \
    dev_domain="dev-testproject.mycorp.net" \
    qa_domain="qa-testproject.mycorp.net" \
    staging_domain="staging-testproject.mycorp.net" \
    prod_domain="testproject.mycorp.net" \
    dev_alternate_domains="www.dev-testproject.mycorp.net" \
    qa_alternate_domains="www.qa-testproject.mycorp.net" \
    staging_alternate_domains="www.staging-testproject.mycorp.net" \
    prod_alternate_domains="www.testproject.mycorp.net" \
    staging_host="staging-docker-testproject.mycorp.net" \
    qa_host="qa-docker-testproject.mycorp.net" \
    dev_host="dev-docker-testproject.mycorp.net" \
    prod_host="testproject.mycorp.net" \
    staging_port="22" \
    remove_cron="" \
    enable_cron="" \
    qa_port="22" \
    dev_port="22" \
    django_project_name="testproject" \
    prod_port="22" \
    django_settings="testproject.settings" \
    mail_domain="mycorp.net" \
    infra_domain="mycorp.net" \
    git_server="gitlab.mycorp.net" \
    git_project_server="gitlab.mycorp.net" \
    git_scheme="https" \
    git_user="" \
    test_tests="" \
    test_linting="y" \
    haproxy="" \
    git_url="https://gitlab.mycorp.net" \
    git_project="testproject" \
    git_project_url="https://gitlab.mycorp.net/ptest/testproject" \
    fname_slug="testproject-testproject" \
    runner="<your ci runner>" \
    runner_tag="testproject-testproject-ci" \
    deploy_project_url="https://github.com/corpusops/django-deploy-common.git" \
    deploy_project_dir="local/django-deploy-common" \
    with_sentry="y" \
    docker_registry="registry.mycorp.net" \
    registry_is_gitlab_registry="" \
    simple_docker_image="testproject/testproject" \
    docker_image="registry.mycorp.net/testproject/testproject" \
    db_mode="postgis" \
    tz="Europe/Paris" \
    use_i18n="y" \
    use_l10n="y" \
    registry_user="" \
    registry_password="" \
    statics_uri="/static" \
    media_uri="/media" \
    use_tz="y" \
    language_code="fr-fr" \
    rabbitmq_image="corpusops/rabbitmq:3" \
    with_toolbar="y" \
    with_djextensions="y" \
    with_celery="" \
    celery_broker="rabbitmq" \
    celery_version="4.3.0" \
    celery_results_version="1.0.4" \
    postgis_image="corpusops/pgrouting:10.1-2.5.4" \
    postgresql_image="corpusops/postgres:11" \
    postgres_image="corpusops/postgres:11" \
    mysql_image="corpusops/mysql" \
    memcached_image="corpusops/memcached:alpine" \
    redis_image="corpusops/redis:4.0-alpine" \
    nginx_image="corpusops/nginx:1.14-alpine" \
    user_model="" \
    settings_account_default_http_protocol="http" \
    settings_use_x_forwarded_host="y" \
    settings_secure_ssl_redirect="y" \
    git_project_https_url="https://gitlab.mycorp.net/ptest/testproject" \
    settings_csrf_cookie_httponly="y" \
    no_lib="" \
    gunicorn_class="gevent" \
    dbsmartbackup_image="corpusops/dbsmartbackup:pgrouting-10.1" \
    cache_system="redis" \
    cache_image="corpusops/redis:4.0-alpine" \
    psycopg_req="==2.8.*" \
    session_engine_base="django.contrib.sessions.backends.db" \
    session_engine_prod="django.contrib.sessions.backends.db" \
    memcached_key_prefix="testproject" \
    with_apptest="" \
    with_drf="y" \
    with_ia_libs="" \
    cache_only_in_prod="" \
    with_bundled_front="" \
    node_version="10.16.0" \
    node_image="corpusops/node:10.16" \
    no_private="" \
    db_out_port="5436" \
     "$@"
fi


NO_SYNC=${NO_SYNC-}
if [[ -z $NO_SYNC ]];then
rsync -azv --delete ./ test/testproject/local/django-deploy-common/ --exclude=test/testproject --exclude=local --exclude=test
fi


cd test/testproject


NO_INIT=${NO_INIT-}
if [[ -z $NO_INIT ]];then
cp .env.dist .env
cp docker.env.dist docker.env
fi
GDAL_VERSION="${GDAL_VERSION:-2.2.3}"

if ! ( grep -iq gdal requirements.txt );then
    printf "GDAL==$GDAL_VERSION\n$(cat requirements.txt)" > requirements.txt
    echo libgdal-dev >> apt.txt
fi
./control.sh build django
# vim:set et sts=4 ts=4 tw=80:
