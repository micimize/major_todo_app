DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

source $DIR/secrets.env

cloud_sql_proxy -instances=$DATABASE_INSTANCE=tcp:2345 2>&1 | \
  sed "s/$DATABASE_INSTANCE/\$DATABASE_INSTANCE/"
