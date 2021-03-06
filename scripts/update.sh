#! /bin/bash
# to be run locally, as postgres user

function err {
  echo 'ERROR: '$1;
  exit 1;
}

# you can use: sudo su postgres -c ./scripts/update.sh
[ $(whoami) = 'postgres' ] || err "must be postgres (try: sudo su postgres -c $0)"

[ -e config.sh ] && . config.sh || err 'config.sh not found';

psql -p $DBPORT <<EOF
DROP DATABASE IF EXISTS $DBNAME;
CREATE DATABASE $DBNAME WITH ENCODING='UTF8' OWNER=$DBUSER;
EOF

psql -p $DBPORT $DBNAME <<EOF
CREATE SCHEMA pgcrypto AUTHORIZATION $DBUSER;
CREATE EXTENSION pgcrypto WITH SCHEMA pgcrypto;
EOF

# Install schemas
PGBASE=vendor/actimeo/pgproc/src
BASE=src

. scripts/files.inc

echo 'Installing SQL from files:'
for i in $FILES; do 
    echo " - $i";
done
(echo 'BEGIN TRANSACTION; ' && cat $FILES && echo 'COMMIT; ' ) |  PGPASSWORD=$DBPASS PGOPTIONS="--client-min-messages=warning" psql -p $DBPORT -v ON_ERROR_STOP=1 -q -h localhost -U $DBUSER $DBNAME

