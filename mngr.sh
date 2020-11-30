#!/bin/bash

PROGRAM_NAME=$(basename $0)
SCRIPT_DIRECTORY=$(dirname $BASH_SOURCE)
COMMAND=$1

function wiistock() {
    kubectl --namespace=wiistock "$@"
}

function activate_maintenance() {
    local INSTANCE=$1
    local PODS=$(wiistock get pods -l app=$INSTANCE | grep "Running" | tr -s ' ' | cut -d ' ' -f 1)
    local PODS_COUNT=$(echo $PODS | wc -w)

    echo "Rolling $PODS_COUNT pods to maintainance mode"
    
    local POD
    for POD in $PODS; do
        wiistock exec $POD -- /bootstrap/maintenance.sh
    done
}
  
function create_instance() {
    if [ $# -lt 2 ]; then
        echo "Illegal number of arguments, expected at least 2, found $#"
        exit 101
    fi

    local TEMPLATE=$1
    local NAME=$2
    shift 2

    # Check if template exists
    if [ ! -d "./$TEMPLATE" ]; then
        echo "Unknown template $TEMPLATE"
        exit 102
    fi

    (cd $TEMPLATE; bash setup.sh $NAME $@)
}
  
function deploy() {
    if [[ $# -ne 1 ]]; then
        echo "Illegal number of arguments, expected between 1, found $#"
        exit 201
    fi

    local NAME=$1

    # Check if deployment exists
    local PODS=$(wiistock get deployments | grep "$NAME*")
    if [ -z "$PODS" ]; then
        echo "Unknown instance \"$NAME\""
        exit 202
    fi
    
    if [[ -n $(wiistock get pods -l app=$NAME | egrep "Init:[0-9]+/1") ]]; then
        echo "An instance is already being deployed"
        exit 203
    fi

    echo "Starting database backup"
    DATABASE_NAME=${NAME//-}
    DATABASE_USER=${NAME%-*}
    DATABASE_PASSWORD=$(cat configs/passwords/$DATABASE_USER)

    # Save the database in a detached thread
    mysqldump $DATABASE_NAME --no-tablespaces \
        --host="cb249510-001.dbaas.ovh.net" \
        --user="$DATABASE_USER" \
        --port=35403 \
        --password="$DATABASE_PASSWORD" > /root/backups/${NAME}_$(date '+%Y-%m-%d-%k-%M-%s').sql 2> /dev/null &

    echo "Updating deployment $NAME"
    wiistock patch deployment $NAME -p "{\"spec\": {\"template\": {\"metadata\": { \"labels\": { \"redeploy\": \"$(date +%s)\"}}}}}" > /dev/null
    
    # Wait for the pod to start initializing and get its name
    while [[ -z $(wiistock get pods -l app=$NAME | grep "Init:1/2") ]]; do
        sleep 1
    done; 
    
    local POD=$(wiistock get pods -l app=$NAME | grep "Init:1/2" | tr -s ' ' | cut -d ' ' -f 1)
    
    echo "Waiting for pod to reach migrations step"
    
    # Wait for the file to be created and get its content
    while [[ -z $(wiistock exec $POD -c initializer -- cat /tmp/migrations 2> /dev/null) ]]; do
        sleep 1
    done;

    # Reattach the detached database backup thread
    wait
    echo "Finished database backup"

    local MIGRATIONS=$(wiistock exec $POD -c initializer -- cat /tmp/migrations 2> /dev/null)

    if [ "$MIGRATIONS" -eq 1 ]; then
        activate_maintenance $NAME
        wiistock exec $POD -c initializer -- sh -c "echo '1' > /tmp/ready"
    else
        echo "No migration detected, proceeding without maintenance"
    fi
}

function cache() {
    if [[ $# -lt 1 || $# -gt 2 ]]; then
        echo "Illegal number of arguments, expected between 1 and 2, found $#"
        exit 201
    fi

    local TEMPLATE=$1

    if [ ! -d "./$TEMPLATE" ]; then
        echo "Unknown template $TEMPLATE"
        exit 302
    fi

    if [ ! -f "./$TEMPLATE/kubernetes/cache.yaml" ]; then
        echo "Template $TEMPLATE does not have a cache"
        exit 303
    fi

    if [ -z "$(wiistock get pods | grep $TEMPLATE-cache)" ]; then
        wiistock apply -f $TEMPLATE/kubernetes/cache.yaml
    else
        wiistock delete pod $TEMPLATE-cache
        wiistock apply -f $TEMPLATE/kubernetes/cache.yaml
    fi
}

function delete() {
    if [[ $# -ne 1 ]]; then
        echo "Illegal number of arguments, expected 1, found $#"
        exit 201
    fi

    local NAME=$1
 
    if [ ! -d configs/$NAME ]; then
        echo "Unknown instance \"$NAME\""
        exit 202
    fi

    local DEPLOYMENT
    for DEPLOYMENT in configs/$NAME/*-deployment.yaml; do
        wiistock delete -f $DEPLOYMENT 2> /dev/null
    done
    
    local BALANCER
    for BALANCER in configs/$NAME/*-balancer.yaml; do
        wiistock delete -f $BALANCER 2> /dev/null
    done

    rm -rf configs/$NAME
}

function publish() {
    local IMAGE=$1

    if [ -n "$IMAGE" ]; then
        echo "Building and pushing wiilog/$IMAGE"
        docker build -t wiilog/$IMAGE:latest images/$IMAGE > /dev/null
        docker push wiilog/$IMAGE:latest                   > /dev/null
    else
        # Build and push all images in the `images` folder
        local IMAGE
        while IFS=$' \t\n\r' read -r IMAGE; do
            echo "Building and pushing wiilog/$IMAGE"
            docker build -t wiilog/$IMAGE:latest images/$IMAGE > /dev/null
            docker push wiilog/$IMAGE:latest                   > /dev/null
        done < images/order
    fi
}

function usage() {
    echo "Manage and deploy kubernetes instances"
    echo ""
    echo "USAGE:"
    echo "    $PROGRAM_NAME <command> [options]"
    echo ""
    echo "COMMANDS:"
    echo "    create-instance <template> <name>    Create an instance"
    echo "    deploy <...instances>                Deploys the given instance(s)"
    echo "                                         or all environments if not specified"
    echo "    cache <template>                     Creates or updates a template's cache"
    echo "    delete <instance>                    Deletes a deployment"
    echo "    publish <image>                      Builds and pushes the docker image"
    echo ""
    exit 0
}

if [ -n "$COMMAND" ]; then
    shift
fi

if [[ -z $(kubectl get namespaces | grep "wiistock") ]]; then
    kubectl create namespace wiistock > /dev/null
fi

cd $SCRIPT_DIRECTORY
mkdir -p configs/passwords

case $COMMAND in
    create-instance)    create_instance "$@" ;;
    deploy)             deploy "$@" ;;
    cache)              cache "$@" ;;
    delete)             delete "$@" ;;
    publish)            publish "$@" ;;
    *)                  usage "$@" ;;
esac