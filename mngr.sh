#!/bin/bash

PROGRAM_NAME=$(basename $0)
COMMAND=$1

function wiistock() {
    kubectl --namespace=wiistock "$@"
}

function activate_maintenance() {
    local INSTANCE=$1
    local PODS=$(wiistock get pods | grep "$INSTANCE" | grep "Running" | tr -s ' ' | cut -d ' ' -f 1)
    local PODS_COUNT=$(echo $PODS | wc -w)

    echo "Rolling $PODS_COUNT pods to maintainance mode"
    
    for POD in $PODS; do
        wiistock exec -it $POD -- sh /bootstrap/maintenance.sh
    done
}
  
function create_instance() {
    if [ $# -ne 2 ]; then
        echo "Illegal number of arguments, expected 2, found $#"
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

    # Check if instance already exists and ask for confirmation
    if [ -d "configs/$NAME" ]; then
        read -p "Instance \"$NAME\" already exists, uploads will be lost and data may get corrupted, continue? " -n 1 -r
        echo 

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi

    mkdir -p configs/$NAME
    echo $TEMPLATE > configs/$NAME/template

    (cd $TEMPLATE; bash setup.sh $NAME $@)
}
  
function deploy() {
    if [[ $# -lt 1 || $# -gt 2 ]]; then
        echo "Illegal number of arguments, expected between 1 and 2, found $#"
        exit 201
    fi

    local NAME=$1
    local ENVIRONMENT=$2

    if [ -z "$ENVIRONMENT" ]; then
        # Check if deployment exists
        local PODS=$(wiistock get deployments | grep "$NAME*")
        if [ -z "$PODS" ]; then
            echo "Unknown instance \"$NAME\""
            exit 202
        fi

        activate_maintenance $NAME
        wiistock patch deployment $NAME -p "{\"spec\": {\"template\": {\"metadata\": { \"labels\": { \"redeploy\": \"$(date +%s)\"}}}}}"
    else
        local INSTANCE=$NAME-$ENVIRONMENT
        
        # Check if deployment exists
        local PODS=$(wiistock get deployments | grep "$INSTANCE")
        if [ -z "$PODS" ]; then
            echo "Unknown instance \"$NAME\" for environment \"$ENVIRONMENT\""
            exit 202
        fi

        activate_maintenance $INSTANCE
        wiistock patch deployment $INSTANCE -p "{\"spec\": {\"template\": {\"metadata\": { \"labels\": {  \"redeploy\": \"$(date +%s)\"}}}}}"
    fi

    # Find pods by label
    # kubectl get pods -l environment=production,tier=frontend
}

function delete() {
    if [[ $# -ne 1 ]]; then
        echo "Illegal number of arguments, expected 1, found $#"
        exit 201
    fi

    local NAME=$1
    local TEMPLATE=$(cat configs/$NAME/template 2> /dev/null)

    if [ -z "$TEMPLATE" ]; then
        echo "Unknown instance \"$NAME\""
        exit 202
    fi

    (cd $TEMPLATE; bash delete.sh $NAME)
}

function publish() {
    local NAME=$1

    if [ -n "$NAME" ]; then
        docker build -t wiilog/$NAME:latest images/$NAME
        docker push wiilog/$NAME:latest
    else
        # Build and push all images in the `images` folder
        for IMAGE in $(ls images); do
            docker build -t wiilog/$IMAGE:latest images/$IMAGE
            docker push wiilog/$IMAGE:latest
        done
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
    echo "    deploy <name> [environment]          Deploys the given instances for the selected environment"
    echo "                                         or all environments if not specified"
    echo "    delete <name>                        Deletes a deployment"
    echo "    publish <name>                       Builds and pushes the docker image"
    echo ""
    exit 0
}

if [ -n "$COMMAND" ]; then
    shift
fi

if [[ -z $(kubectl get namespaces | grep "wiistock") ]]; then
    kubectl create namespace wiistock > /dev/null
fi

case $COMMAND in
    create-instance)    create_instance "$@" ;;
    deploy)             deploy "$@" ;;
    delete)             delete "$@" ;;
    publish)            publish "$@" ;;
    *)                  usage "$@" ;;
esac