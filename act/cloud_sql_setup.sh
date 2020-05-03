#!/usr/bin/env bash
# A version of https://github.com/graphile/starter/blob/master/heroku-setup.template
# adapted for instantiating a cloud sql instance
# via cloud_sql_proxy.
# Run the following in a different terminal before this script:
# cloud_sql_proxy -instances=$DATABASE_INSTANCE=tcp:2345

# exit on error
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

HARD=0

while [[ $# -gt 0 ]]
do
  key="$1"

  case $key in
    --hard)
      echo Dropping all roles and databases before setup
      HARD=1
      shift # past flag
      ;;
  esac

  case $key in
    -v|--verbose)
      echo Echoing all commands
      set -x
      shift # past flag
      ;;
  esac

done

########################################
#    THESE ARE THE CRITICAL SETTINGS   #
########################################

source $DIR/secrets.env
  # includes:
  # DATABASE_OWNER_PASSWORD
  # DATABASE_AUTHENTICATOR_PASSWORD

source $DIR/database_superuser.env
  # DATABASE_SUPERUSER_PASSWORD

DATABASE_NAME='todo_app'
DATABASE_HOST='localhost'
DATABASE_PORT=2345
DATABASE_SUPERUSER='postgres'

########################################
#    PLEASE PROOF-READ THE BELOW,      #
#    PARTICULARLY THE DATABASE SETUP   #
########################################

# Database roles
DATABASE_OWNER="${DATABASE_NAME}"
DATABASE_AUTHENTICATOR="${DATABASE_NAME}_authenticator"
DATABASE_VISITOR="${DATABASE_NAME}_visitor"

_AUTH="${DATABASE_SUPERUSER}:${DATABASE_SUPERUSER_PASSWORD}"
_CONNECTION="postgres://$_AUTH@${DATABASE_HOST}:${DATABASE_PORT}"

# We're using 'template1' because we know it should exist. We should not actually change this database.
SUPERUSER_TEMPLATE1_URL="$_CONNECTION/template1"
SUPERUSER_DATABASE_URL="$_CONNECTION/$DATABASE_NAME"

echo -e "\n\nTesting database connection"
psql -X1v ON_ERROR_STOP=1 "${SUPERUSER_TEMPLATE1_URL}" -c 'SELECT true AS success'

echo -e "\n\nCreating the database and the roles"

DROP_STATEMENTS=''
if [ $HARD -gt 0 ]
then
  DROP_STATEMENTS="
  -- If you want to scorch the earth beforehand, pass --hard
  DROP DATABASE ${DATABASE_NAME};
  DROP ROLE ${DATABASE_OWNER};
  DROP ROLE ${DATABASE_AUTHENTICATOR};
  DROP ROLE ${DATABASE_VISITOR};
  "
fi

psql -Xv ON_ERROR_STOP=1 "${SUPERUSER_TEMPLATE1_URL}" <<HERE
${DROP_STATEMENTS}

CREATE ROLE ${DATABASE_OWNER}
  WITH LOGIN PASSWORD '${DATABASE_OWNER_PASSWORD}';

GRANT ${DATABASE_OWNER} TO ${DATABASE_SUPERUSER};

CREATE ROLE ${DATABASE_AUTHENTICATOR}
  WITH LOGIN PASSWORD '${DATABASE_AUTHENTICATOR_PASSWORD}' 
  NOINHERIT;

CREATE ROLE ${DATABASE_VISITOR};

GRANT ${DATABASE_VISITOR} TO ${DATABASE_AUTHENTICATOR};

-- Create database
CREATE DATABASE ${DATABASE_NAME}
  OWNER ${DATABASE_OWNER};

-- Database permissions
REVOKE ALL ON DATABASE ${DATABASE_NAME} FROM PUBLIC;

GRANT ALL ON DATABASE ${DATABASE_NAME} TO ${DATABASE_OWNER};

GRANT CONNECT ON DATABASE ${DATABASE_NAME}
  TO ${DATABASE_AUTHENTICATOR};

HERE

echo -e "\n\nInstalling extensions into the database"

psql -X1v ON_ERROR_STOP=1 "${SUPERUSER_DATABASE_URL}" <<HERE
-- Add extensions
CREATE EXTENSION IF NOT EXISTS plpgsql WITH SCHEMA pg_catalog;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;
HERE

