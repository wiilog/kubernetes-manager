#!/bin/bash

declare -A BRANCH_PREFIXES
BRANCH_PREFIXES[prod]="master"
BRANCH_PREFIXES[rec]="recette"
BRANCH_PREFIXES[dev]="dev"

declare -A STORAGE_SIZES
STORAGE_SIZES[prod]=25
STORAGE_SIZES[rec]=10
STORAGE_SIZES[dev]=10
STORAGE_SIZES[custom]=10

NAME=$1; shift
ENVIRONMENTS=$@
if [ -z "$ENVIRONMENTS" ]; then
    ENVIRONMENTS=("rec" "prod")
fi

if [ -f ../configs/passwords/$NAME ]; then
    DATABASE_PASSWORD=$(cat ../configs/passwords/$NAME)
else
    DATABASE_PASSWORD=$(openssl rand -base64 16 | tr --delete =/+)

    # Make sure the password contains uppercase
    while [[ -z $(echo $DATABASE_PASSWORD | awk "/[a-z]/ && /[A-Z]/ && /[0-9]/") ]]; do
        DATABASE_PASSWORD=$(openssl rand -base64 16 | tr --delete =/+)
    done

    echo $DATABASE_PASSWORD > ../configs/passwords/$NAME
fi

declare -A DATABASE
DATABASE[host]=cb249510-001.dbaas.ovh.net
DATABASE[port]=35403
DATABASE[user]=$NAME
DATABASE[pass]=$DATABASE_PASSWORD

function wiistock() {
    kubectl --namespace=wiistock "$@"
}

function create_directories() {
    local NAME=$1
    local ENVIRONMENT
    shift

    for ENVIRONMENT in $@; do
        if [ $ENVIRONMENT == "custom" ]; then
            local FULL_NAME=$NAME
        else
            local FULL_NAME=$NAME-$ENVIRONMENT
        fi
        
        if [ -d ../configs/$FULL_NAME ]; then
            read -p "Instance \"$FULL_NAME\" already exists, uploads will be lost and data may get corrupted, continue? " REPLY

            if [[ ! $REPLY =~ ^[Yy1]$ ]]; then
                exit 0
            fi
        fi

        mkdir -p ../configs/$FULL_NAME
    done
}

function request_configuration() {
    echo ""
    echo "  Configuration"
    read -p "Replicas count:   " REPLICAS_COUNT

    if [ $ENVIRONMENTS == "custom" ]; then
        read -p "Environment:      " REAL_ENVIRONMENT
        read -p "Branch:           " BRANCH
        read -p "Send mails (y/n): " SEND_MAILS
        
        case "$SEND_MAILS" in 
            y|Y|1 ) NO_MAIL=0 ;;
            n|N|0 ) NO_MAIL=1 ;;
            * ) echo "Expected y/n for send mails" && exit 1 ;;
        esac
    else
        read -p "Branches suffix:  " BRANCHES_SUFFIX
        NO_MAIL=0
    fi

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
    if [[ "$@" == "custom" ]]; then
        echo "    Database  \"$NAME\""
    else
        for ENVIRONMENT in $@; do
            echo "    Database  \"$NAME$ENVIRONMENT\""
        done
    fi

    read
}

function request_volumes_creation() {
    local NAME=$1

    echo ""
    echo "Create the following partitions on OVH panel, allow access from the"
    echo "following 3 IPs and press enter when OVH is done creating them"

    shift
    for ENVIRONMENT in $@; do
        if [ "$ENVIRONMENT" == "custom" ]; then
            echo -e "    $NAME\t(10GO)\taccessible from\t51.210.121.167, 51.210.125.224, 51.210.127.44"
        else
            echo -e "    $NAME$ENVIRONMENT\t(${STORAGE_SIZES[$ENVIRONMENT]}GO)\taccessible from\t51.210.121.167, 51.210.125.224, 51.210.127.44"
        fi
    done

    read
}

function request_domains_creation() {
    local NAME=$1
    local DOMAIN=$2
    local IP=$(kubectl get service ingress-nginx-controller --namespace=ingress-nginx --no-headers | tr -s ' ' | cut -d ' ' -f 4)

    shift 2

    echo ""
    echo "Create the following domains and press enter when done"

    for ENVIRONMENT in $@; do
        if [ $ENVIRONMENT == "custom" ]; then
            local FULL_NAME=$NAME
        else
            local FULL_NAME=$NAME-$ENVIRONMENT
        fi
        
        echo -e "    $FULL_NAME.$DOMAIN\t with target\t $IP"
    done

    read
}

function clear_instance() {
    local NAME=$1
    local ENVIRONMENT=$2

    if [ $ENVIRONMENT == "custom" ]; then
        local FULL_NAME=$NAME
    else
        local FULL_NAME=$NAME-$ENVIRONMENT
    fi

    # Delete the previous instance if it exists
    if [ -f ../configs/$FULL_NAME/deployment.yaml ]; then
        kubectl delete -f ../configs/$FULL_NAME/deployment.yaml 2> /dev/null
    fi

    # Delete anything with the same name
    wiistock delete ingress $FULL_NAME                    2> /dev/null
    wiistock delete service $FULL_NAME                    2> /dev/null
    wiistock delete secret $FULL_NAME-tls                 2> /dev/null
    wiistock delete deployment $FULL_NAME                 2> /dev/null
    wiistock delete pvc $FULL_NAME-uploads                2> /dev/null
    wiistock delete pv wiistock-$FULL_NAME-uploads-pv     2> /dev/null
}

function create_deployment() {
    local NAME=${1}
    local ENVIRONMENT=${2}
    local REPLICAS_COUNT=${3}
    local DOMAIN=${4}
    local BRANCH=${5}
    local CLIENT=${6}
    local NO_MAIL=${7}

    if [ $ENVIRONMENT == "custom" ]; then
        local FULL_NAME=$NAME
        local FULL_NAME_GLUED=$NAME
        local FULL_DOMAIN=$NAME.$DOMAIN
        local REAL_ENVIRONMENT=$REAL_ENVIRONMENT
    else
        local FULL_NAME=$NAME-$ENVIRONMENT
        local FULL_NAME_GLUED=$NAME$ENVIRONMENT
        local FULL_DOMAIN=$FULL_NAME.$DOMAIN
        local REAL_ENVIRONMENT=$ENVIRONMENT
    fi

    local CONFIG=../configs/$FULL_NAME/deployment.yaml
    local STORAGE_SIZE=$((${STORAGE_SIZES[$ENVIRONMENT]}))
    local DASHBOARD_TOKEN=$(openssl rand -base64 32 | tr --delete =/)
    local SECRET=$(openssl rand -base64 8 | tr --delete =/)

    cp kubernetes/deployment.yaml $CONFIG
    sed -i "s|VAR:INSTANCE_NAME|$FULL_NAME|g"   $CONFIG
    sed -i "s|VAR:REPLICAS_COUNT|$REPLICAS_COUNT|g"     $CONFIG
    sed -i "s|VAR:BRANCH|$BRANCH|g"                     $CONFIG
    sed -i "s|VAR:PARTITION_NAME|$FULL_NAME_GLUED|g"    $CONFIG
    sed -i "s|VAR:UPLOADS_STORAGE|$STORAGE_SIZE|g"      $CONFIG
    sed -i "s|VAR:DOMAIN|$FULL_DOMAIN|g"                $CONFIG
    sed -i "s|VAR:DATABASE_HOST|${DATABASE[host]}|g"    $CONFIG
    sed -i "s|VAR:DATABASE_PORT|${DATABASE[port]}|g"    $CONFIG
    sed -i "s|VAR:DATABASE_USER|${DATABASE[user]}|g"    $CONFIG
    sed -i "s|VAR:DATABASE_PASS|${DATABASE[pass]}|g"    $CONFIG
    sed -i "s|VAR:DATABASE_NAME|$FULL_NAME_GLUED|g"     $CONFIG
    sed -i "s|VAR:ENV|$REAL_ENVIRONMENT|g"              $CONFIG
    sed -i "s|VAR:SECRET|$SECRET|g"                     $CONFIG
    sed -i "s|VAR:CLIENT|$CLIENT|g"                     $CONFIG
    sed -i "s|VAR:URL|https://$FULL_DOMAIN|g"           $CONFIG
    sed -i "s|VAR:FORBIDDEN_PHONES|$FORBIDDEN_PHONES|g" $CONFIG
    sed -i "s|VAR:DASHBOARD_TOKEN|$DASHBOARD_TOKEN|g"   $CONFIG
    sed -i "s|VAR:NO_MAIL|$NO_MAIL|g"                   $CONFIG
    wiistock apply -f $CONFIG
}

create_directories $NAME ${ENVIRONMENTS[@]}

request_configuration
request_databases_creation $NAME ${ENVIRONMENTS[@]}
request_volumes_creation $NAME ${ENVIRONMENTS[@]}
request_domains_creation $NAME $DOMAIN ${ENVIRONMENTS[@]}

for ENVIRONMENT in ${ENVIRONMENTS[@]}; do
    clear_instance $NAME $ENVIRONMENT &
done
wait

for ENVIRONMENT in ${ENVIRONMENTS[@]}; do
    if [ "$ENVIRONMENT" == "prod" ] || [ "$ENVIRONMENT" == "custom" ]; then
        REPLICAS_FOR_ENV=$REPLICAS_COUNT
    else
        REPLICAS_FOR_ENV=1
    fi

    if [ -z "$BRANCH" ]; then
        BRANCH=${BRANCH_PREFIXES[$ENVIRONMENT]}-$BRANCHES_SUFFIX
    fi

    create_deployment $NAME $ENVIRONMENT $REPLICAS_FOR_ENV \
        $DOMAIN \
        $BRANCH \
        $CLIENT \
        $NO_MAIL &
done
wait
