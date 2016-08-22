#! /bin/sh

# Create database
psql -c "create user $DBUSER password '$DBPASS'" -U postgres
psql -c "CREATE DATABASE $DBNAME WITH ENCODING='UTF8' owner=$DBUSER" -U postgres
PGPASSWORD=$DBPASS psql $DBNAME -c "CREATE SCHEMA pgcrypto AUTHORIZATION $DBUSER;"
psql $DBNAME -c "CREATE EXTENSION pgcrypto WITH SCHEMA pgcrypto;" -U postgres

# Install schemas
PGBASE=vendor/actimeo/pgproc/src
BASE=src
FILES="$PGBASE/sql/*.sql $PGBASE/plpgsql/*.sql"
FILES="$FILES $BASE/portal/sql/portal.sql $BASE/portal/sql/comments.sql $BASE/portal/sql/mainview_*.sql $BASE/portal/sql/personview_*.sql $BASE/portal/plpgsql/*.sql"
FILES="$FILES $BASE/organ/sql/organ.sql $BASE/organ/sql/comments.sql $BASE/organ/plpgsql/*.sql"
FILES="$FILES $BASE/login/sql/auth.sql $BASE/login/sql/comments.sql $BASE/login/plpgsql/*.sql"
FILES="$FILES $BASE/pgdoc/sql/schema.sql $BASE/pgdoc/sql/*.sql"

echo 'Installing SQL from files:'
for i in $FILES; do 
    echo " - $i";
done
(echo 'BEGIN TRANSACTION; ' && cat $FILES && echo 'COMMIT; ' ) |  PGPASSWORD=$DBPASS PGOPTIONS="--client-min-messages=warning" psql -v ON_ERROR_STOP=1 -q -h localhost -U $DBUSER $DBNAME

#bash ./install.sh
#bash ./update.sh
echo "<?php \$pg_host = 'localhost'; \$pg_user = '$DBUSER'; \$pg_pass = '$DBPASS'; \$pg_database = '$DBNAME';" > config.inc.php
