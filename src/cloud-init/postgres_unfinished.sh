postgres_service() {
    SERVICE=postgres
    IMAGE=postgres
    ## Main postgres config:
    if [ ! -f /etc/sysconfig/${SERVICE} ]; then
        cat <<EOF > /etc/sysconfig/${SERVICE}
POSTGRES_PASSWORD=$(openssl rand -base64 32)
EOF
    fi
    ## Template to create users and databases
    db_template() {
        DB=$1
        DB_USER=$DB
        mkdir -p /etc/sysconfig/${SERVICE}.d
        if [ ! -f /etc/sysconfig/${SERVICE}.d/${DB}-DDL.sh ]; then
            DB_PASSWORD=$(openssl rand -base64 32)
            cat <<EOF > /etc/sysconfig/${SERVICE}.d/${DB}-credentials
POSTGRES_USER=${DB_USER}
POSTGRES_PASSWORD=${DB_PASSWORD}
EOF
            cat <<EOF > /etc/sysconfig/${SERVICE}.d/${DB}-DDL.sh
#!/bin/bash -e

psql -v ON_ERROR_STOP=1 --username postgres --dbname postgres <<-EOSQL
    CREATE USER ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';
    CREATE DATABASE ${DB};
    GRANT ALL PRIVILEGES ON DATABASE ${DB} TO ${DB_USER};
EOSQL
EOF
        fi
    }
    ## Create all databases and users:
    db_template phoenix
    ## Create and start postgres service:
    POSTGRES_UID=999
    chown ${POSTGRES_UID}:root -R /etc/sysconfig/${SERVICE}.d
    write_container_service ${SERVICE} ${IMAGE} "--pod new:${SERVICE}-pod -v ${SERVICE}-data:/var/lib/postgresql/data -v /etc/sysconfig/${SERVICE}.d:/docker-entrypoint-initdb.d"
    systemctl enable --now ${SERVICE}
}
