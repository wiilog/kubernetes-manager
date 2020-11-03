#!/bin/bash

PROGRAM_NAME=$(basename $0)
COMMAND=$1

function wiistock() {
    kubectl --namespace=wiistock "@a"
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
    if [ "$#" -ne 2 ]; then
        echo "Illegal number of arguments, expected 2, found $#"
        exit 101
    fi

    local TEMPLATE=$1
    local NAME=$2

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

    chmod +x $TEMPLATE/setup.sh
    (cd $TEMPLATE; ./setup.sh $NAME)
}
  
function deploy() {
    if [[ $# -lt 1 || $# -gt 2 ]]; then
        echo "Illegal number of arguments, expected between 1 and 2, found $#"
        exit 201
    fi

    local NAME=$1
    local ENVIRONMENT=$2

    # If no environment is specified, update all environments
    if [ -z "$ENVIRONMENT" ]; then
        # Check if deployment exists
        local PODS=$(wiistock get deployments | grep "$NAME-.*")
        if [ -z "$PODS" ]; then
            echo "Unknown instance \"$NAME\""
            exit 202
        fi

        activate_maintenance "$NAME-.*"

        for INSTANCE_FILE in $(find configs/$NAME -name "*-deployment.yaml" -type f); do
            local DEPLOYMENT=$(echo $INSTANCE_FILE | grep -oP '(?<=configs/).*?(?=\-deployment.yaml)')
            local DEPLOYMENT="${DEPLOYMENT/\//-}"

            wiistock patch deployment $DEPLOYMENT -p "{\"spec\": {\"template\": {\"metadata\": { \"labels\": {  \"redeploy\": \"$(date +%s)\"}}}}}"
        done
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

function publish() {
    if [ "$#" -ne 1 ]; then
        echo "Illegal number of arguments, expected 1, found $#"
        exit 401
    fi

    local NAME=$1

    # Build and push all images in the `images` folder of the instance
    for IMAGE in $(ls $NAME/images); do
        docker build -t wiilog/$IMAGE:latest $NAME/images/$IMAGE
        docker push wiilog/$IMAGE:latest
    done
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