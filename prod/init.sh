#! /bin/bash
# retrocompat wrapper
# everything now lives in ./start.sh
# AS root
set -ex
exec "$(dirname $(readlink -f "$0"))/start.sh $@"
