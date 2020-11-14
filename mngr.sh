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
        
        if [[ -n $(wiistock get pods -l app=$NAME | egrep "Init:[0-9]+/1") ]]; then
            echo "An instance is already being deployed"
            exit 203
        fi

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

        local MIGRATIONS=$(wiistock exec $POD -c initializer -- cat /tmp/migrations 2> /dev/null)

        if [ $MIGRATIONS -eq 1 ]; then
            activate_maintenance $NAME
            wiistock exec $POD -c initializer -- sh -c "echo '1' > /tmp/ready"
        else
            echo "No migration detected, proceeding without maintenance"
        fi
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

    local DEPLOYMENT
    for DEPLOYMENT in configs/$NAME/*-deployment.yaml; do
        wiistock delete -f $DEPLOYMENT 2> /dev/null
    done
    
    # (cd $TEMPLATE; bash delete.sh $NAME)
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
case $COMMAND in
    create-instance)    create_instance "$@" ;;
    deploy)             deploy "$@" ;;
    delete)             delete "$@" ;;
    publish)            publish "$@" ;;
    *)                  usage "$@" ;;
esac