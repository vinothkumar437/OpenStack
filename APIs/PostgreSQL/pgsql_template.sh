#!/bin/sh

#abort on error
set -e

function usage
{
    echo "usage: pgsql_template -PGSQL_ROOT_PASSWORD AN_ARG -PGSQL_USER AN_ARG -PGSQL_PASSWORD AN_ARG -PGSQL_DATABASE AN_ARG"
    echo "   ";
    echo "  -PGSQL_ROOT_PASSWORD            : PGSQL Root User Password";
    echo "  -PGSQL_USER                     : PGSQL Username";
    echo "  -PGSQL_PASSWORD                 : PGSQL Password";
    echo "  -PGSQL_DATABASE                 : Database name";
    echo "  -h | --help                     : This message";
}

function parse_args
{
  # positional args
  args=()

  # named args
  while [ "$1" != "" ]; do
      case "$1" in
          -PGSQL_ROOT_PASSWORD )               PGSQL_ROOT_PASSWORD="$2";             shift;;
          -PGSQL_USER )                        PGSQL_USER="$2";     shift;;
          -PGSQL_PASSWORD )                    PGSQL_PASSWORD="$2";      shift;;
          -PGSQL_DATABASE )                    PGSQL_DATABASE="$2";     shift;;
          -h | --help )                 usage;                   exit;; # quit and show usage
          * )                           args+=("$1")             # if no match, add it to the positional args
      esac
      shift # move to next kv pair
  done

  # validate required args
  if [[ -z "${PGSQL_ROOT_PASSWORD}" || -z "${PGSQL_USER}" || -z "${PGSQL_PASSWORD}" || -z "${PGSQL_DATABASE}" ]]; then
      echo "Invalid arguments"
      usage
      exit;
  fi
}

function run
{
  parse_args "$@"

  PGSQL_EMAIL=$PGSQL_USER"@infosysitdbaas.local"
  echo "you passed in...\n"
  echo "PGSQL_ROOT_PASSWORD: $PGSQL_ROOT_PASSWORD"
  echo "PGSQL_USER: $PGSQL_USER"
  echo "PGSQL_PASSWORD: $PGSQL_PASSWORD"
  echo "PGSQL_DATABASE: $PGSQL_DATABASE"
  mkdir /var/lib/pgsql/12
  chown -R postgres:postgres /var/lib/pgsql/12
  mkdir /var/lib/pgsql/12/backups
  chown -R postgres:postgres /var/lib/pgsql/12/backups
  echo "#PostgreSQL Initialization"
  /usr/pgsql-12/bin/postgresql-12-setup initdb
  echo "#Enable and start the service"
  systemctl enable postgresql-12.service
  systemctl start postgresql-12.service
  echo "#Assign the password for the superuser"
  sudo -i -u postgres psql -U postgres -d postgres -c "alter user postgres with password '$PGSQL_ROOT_PASSWORD';"
  systemctl restart postgresql-12.service
  sed -i ' s/^/#/'   /var/lib/pgsql/12/data/pg_hba.conf
  echo "listen_addresses = '*'" >> /var/lib/pgsql/12/data/postgresql.conf
  echo "local all all md5" >> /var/lib/pgsql/12/data/pg_hba.conf
  echo "host all all 0.0.0.0/0 md5" >> /var/lib/pgsql/12/data/pg_hba.conf
  touch /root/.pgpass
  echo "localhost:*:*:postgres:$PGSQL_ROOT_PASSWORD" > /root/.pgpass
  chmod 0600 /root/.pgpass
  systemctl restart postgresql-12.service
  systemctl enable httpd.service
  systemctl start httpd.service
  psql -U postgres -d postgres -c "create database $PGSQL_DATABASE"
  psql -U postgres -d postgres -c "CREATE USER $PGSQL_USER WITH PASSWORD '$PGSQL_PASSWORD'"
  psql -U postgres -d postgres -c "ALTER USER $PGSQL_USER WITH CREATEDB SUPERUSER"
  psql -U postgres -d postgres -c "ALTER USER $PGSQL_USER WITH CREATEROLE"
  psql -U postgres -d postgres -c "ALTER USER $PGSQL_USER WITH REPLICATION"
  WEB_CONSOLE=$( expect -c "
  set timeout 10
  spawn sudo /usr/pgadmin4/bin/setup-web.sh
  expect \"Email address:\"
  send \"$PGSQL_EMAIL\r\"
  expect \"Password:\"
  send \"$PGSQL_PASSWORD\r\"
  expect \"Retype password:\"
  send \"$PGSQL_PASSWORD\r\"
  expect \"The Apache web server is not running. We can enable and start the web server for you to finish pgAdmin 4 installation. Continue (y/n)?\"
  send \"y\r\"
  expect eof
  " )
  echo $WEB_CONSOLE
  echo "Successfully Created"
}

run "$@";

