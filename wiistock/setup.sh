#!/bin/bash

declare -A BRANCH_PREFIXES
BRANCH_PREFIXES[prod]="master"
BRANCH_PREFIXES[rec]="recette"
BRANCH_PREFIXES[qa]="recette"
BRANCH_PREFIXES[dev]="dev"

INSTANCE_NAME=$1
mkdir -p ../configs/$INSTANCE_NAME

declare -A DATABASE
DATABASE[host]=cb249510-001.dbaas.ovh.net
DATABASE[port]=35403
DATABASE[user]=$INSTANCE_NAME
DATABASE[pass]=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)

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
    echo "Create the following 20GO partitions on OVH panel, allow access from the"
    echo "following 3 IPs and press enter when OVH is done creating them"

    shift
    for ENVIRONMENT in $@; do
        echo -e "    $NAME$ENVIRONMENT\taccessible from\t51.210.121.167, 51.210.125.224, 51.210.127.44"
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

function create_load_balancer() {
    local NAME=$1
    local DOMAIN=$2
    local ENVIRONMENT=$3

    if [[ -z $(wiistock get services | grep "$INSTANCE_NAME-$ENVIRONMENT") ]]; then
        local BALANCER_CONFIG=../configs/$NAME/$ENVIRONMENT-balancer.yaml
        cp balancer.yaml $BALANCER_CONFIG
        sed -i "s|VAR:INSTANCE_NAME|$INSTANCE_NAME-$ENVIRONMENT|g" $BALANCER_CONFIG
        wiistock apply -f $BALANCER_CONFIG
    fi
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
    local DASHBOARD_TOKEN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    local SECRET=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)
    local LOGGER_URL="https://logs.$DOMAIN"

    cp deployment.yaml $CONFIG
    sed -i "s|VAR:INSTANCE_NAME|$NAME-$ENVIRONMENT|g"   $CONFIG
    sed -i "s|VAR:REPLICAS_COUNT|$REPLICAS_COUNT|g"     $CONFIG
    sed -i "s|VAR:BRANCH|$BRANCH|g"                     $CONFIG
    sed -i "s|VAR:PARTITION_NAME|$NAME$ENVIRONMENT|g"   $CONFIG
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
request_databases_creation $INSTANCE_NAME "prod" "rec"
request_volumes_creation $INSTANCE_NAME "prod" "rec"

clear_instance $INSTANCE_NAME "rec"  &
clear_instance $INSTANCE_NAME "prod" &
create_load_balancer $INSTANCE_NAME $DOMAIN "rec"  &
create_load_balancer $INSTANCE_NAME $DOMAIN "prod" &
wait

print_load_balancers $INSTANCE_NAME $DOMAIN "rec" "prod"

create_deployment $INSTANCE_NAME "rec" 1 \
    $DOMAIN \
    $BRANCHES_SUFFIX \
    $CLIENT &

create_deployment $INSTANCE_NAME "prod" $REPLICAS_COUNT \
    $DOMAIN \
    $BRANCHES_SUFFIX \
    $CLIENT &

wait