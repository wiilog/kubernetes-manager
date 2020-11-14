#!/bin/bash

declare -A BRANCH_PREFIXES
BRANCH_PREFIXES[prod]="master"
BRANCH_PREFIXES[rec]="recette"
BRANCH_PREFIXES[dev]="dev"

declare -A STORAGE_SIZES
STORAGE_SIZES[prod]=25
STORAGE_SIZES[rec]=10
STORAGE_SIZES[dev]=10

NAME=$1; shift
ENVIRONMENTS=$@
if [ -z "$ENVIRONMENTS" ]; then
    ENVIRONMENTS=("rec" "prod")
fi

declare -A DATABASE
DATABASE[host]=cb249510-001.dbaas.ovh.net
DATABASE[port]=35403
DATABASE[user]=$NAME
DATABASE[pass]=$(openssl rand -base64 16 | tr --delete =/+)

function wiistock() {
    kubectl --namespace=wiistock "$@"
}

function request_configuration() {
    echo ""
    echo "  Configuration"
    read -p "Replicas count:   " REPLICAS_COUNT
    read -p "Branches suffix:  " BRANCHES_SUFFIX
    read -p "Base domain name: " DOMAIN
    read -p "Client:           " CLIENT
    read -p "Forbidden phones: " FORBIDDEN_PHONES
    echo ""
}

function request_databases_creation() {
    local NAME=$1

    echo "Create the following user with administrator rights on both databases"
    echo "on OVH panel and press enter when OVH is done creating everything"
    echo -e "    User      \"$NAME\"\tidentified by password\t${DATABASE[pass]}"
    
    shift
    for ENVIRONMENT in $@; do
        echo "    Database  \"$NAME$ENVIRONMENT\""
    done

    read
}

function request_volumes_creation() {
    local NAME=$1

    echo ""
    echo "Create the following partitions on OVH panel, allow access from the"
    echo "following 3 IPs and press enter when OVH is done creating them"

    shift
    for ENVIRONMENT in $@; do
        echo -e "    $NAME$ENVIRONMENT\t(${STORAGE_SIZES[$ENVIRONMENT]}GO)\taccessible from\t51.210.121.167, 51.210.125.224, 51.210.127.44"
    done

    read
}

function create_load_balancer() {
    local NAME=$1
    local DOMAIN=$2
    shift 2

    for ENVIRONMENT in $@; do
        if [[ -z $(wiistock get services | grep "$NAME-$ENVIRONMENT") ]]; then
            local BALANCER_CONFIG=../configs/$NAME/$ENVIRONMENT-balancer.yaml
            cp kubernetes/balancer.yaml $BALANCER_CONFIG
            sed -i "s|VAR:INSTANCE_NAME|$NAME-$ENVIRONMENT|g" $BALANCER_CONFIG
            wiistock apply -f $BALANCER_CONFIG
        fi
    done
}

function print_load_balancers() {
    local NAME=$1
    local DOMAIN=$2

    shift 2

    echo ""
    echo "Waiting for load balancers to get their IP assigned"

    for ENVIRONMENT in $@; do
        while [[ ! $(wiistock get services | grep $NAME-$ENVIRONMENT | tr -s ' ' | cut -d ' ' -f 4) =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do
            sleep 2
        done
    done
    
    echo "Create the following domains and press enter when done"

    for ENVIRONMENT in $@; do
        local IP=$(wiistock get services | grep $NAME-$ENVIRONMENT | tr -s ' ' | cut -d ' ' -f 4)
        echo -e "    $NAME-$ENVIRONMENT.$DOMAIN\t with target\t $IP"
    done

    read
}

function clear_instance() {
    local NAME=$1
    local ENVIRONMENT=$2

    wiistock delete deployment $NAME-$ENVIRONMENT                  2> /dev/null
    wiistock delete pvc $NAME-$ENVIRONMENT-letsencrypt             2> /dev/null
    wiistock delete pvc $NAME-$ENVIRONMENT-uploads                 2> /dev/null
    wiistock delete pv wiistock-$NAME-$ENVIRONMENT-letsencrypt-pv  2> /dev/null
    wiistock delete pv wiistock-$NAME-$ENVIRONMENT-uploads-pv      2> /dev/null
}

function create_deployment() {
    local NAME=${1}
    local ENVIRONMENT=${2}
    local REPLICAS_COUNT=${3}
    local DOMAIN=${4}
    local BRANCH_SUFFIX=${5}
    local CLIENT=${6}
    
    local CONFIG=../configs/$NAME/$ENVIRONMENT-deployment.yaml
    local BRANCH="${BRANCH_PREFIXES[$ENVIRONMENT]}-$BRANCH_SUFFIX"
    local FULL_DOMAIN=$NAME-$ENVIRONMENT.$DOMAIN
    local STORAGE_SIZE=$((${STORAGE_SIZES[$ENVIRONMENT]} - 1))
    local DASHBOARD_TOKEN=$(openssl rand -base64 32 | tr --delete =/)
    local SECRET=$(openssl rand -base64 8 | tr --delete =/)
    local LOGGER_URL="https://logs.$DOMAIN"

    cp kubernetes/deployment.yaml $CONFIG
    sed -i "s|VAR:INSTANCE_NAME|$NAME-$ENVIRONMENT|g"   $CONFIG
    sed -i "s|VAR:REPLICAS_COUNT|$REPLICAS_COUNT|g"     $CONFIG
    sed -i "s|VAR:BRANCH|$BRANCH|g"                     $CONFIG
    sed -i "s|VAR:PARTITION_NAME|$NAME$ENVIRONMENT|g"   $CONFIG
    sed -i "s|VAR:UPLOADS_STORAGE|$STORAGE_SIZE|g"      $CONFIG
    sed -i "s|VAR:DOMAIN|$FULL_DOMAIN|g"                $CONFIG
    sed -i "s|VAR:DATABASE_HOST|${DATABASE[host]}|g"    $CONFIG
    sed -i "s|VAR:DATABASE_PORT|${DATABASE[port]}|g"    $CONFIG
    sed -i "s|VAR:DATABASE_USER|${DATABASE[user]}|g"    $CONFIG
    sed -i "s|VAR:DATABASE_PASS|${DATABASE[pass]}|g"    $CONFIG
    sed -i "s|VAR:DATABASE_NAME|$NAME$ENVIRONMENT|g"    $CONFIG
    sed -i "s|VAR:ENV|prod|g"                           $CONFIG
    sed -i "s|VAR:SECRET|$SECRET|g"                     $CONFIG
    sed -i "s|VAR:CLIENT|$CLIENT|g"                     $CONFIG
    sed -i "s|VAR:URL|https://$FULL_DOMAIN|g"           $CONFIG
    sed -i "s|VAR:LOGGER|$LOGGER_URL|g"                 $CONFIG
    sed -i "s|VAR:FORBIDDEN_PHONES|$FORBIDDEN_PHONES|g" $CONFIG
    sed -i "s|VAR:DASHBOARD_TOKEN|$DASHBOARD_TOKEN|g"   $CONFIG
    wiistock apply -f $CONFIG
}

request_configuration
request_databases_creation $NAME ${ENVIRONMENTS[@]}
request_volumes_creation $NAME ${ENVIRONMENTS[@]}

create_load_balancer $NAME $DOMAIN ${ENVIRONMENTS[@]}
print_load_balancers $NAME $DOMAIN ${ENVIRONMENTS[@]}

for ENVIRONMENT in  ${ENVIRONMENTS[@]}; do
    clear_instance $NAME $ENVIRONMENT &
done
wait

for ENVIRONMENT in  ${ENVIRONMENTS[@]}; do
    if [ $ENVIRONMENT == "prod" ]; then
        REPLICAS_FOR_ENV=$REPLICAS_COUNT
    else
        REPLICAS_FOR_ENV=1
    fi

    create_deployment $NAME $ENVIRONMENT $REPLICAS_FOR_ENV \
        $DOMAIN \
        $BRANCHES_SUFFIX \
        $CLIENT &
done
wait
