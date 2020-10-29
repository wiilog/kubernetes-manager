#!/bin/bash

PROGRAM_NAME=$(basename $0)
COMMAND=$1
  
create_instance() {
    if [ "$#" -ne 2 ]; then
        echo "Illegal number of arguments, expected 2, found $#"
        exit 101
    fi

    TEMPLATE=$1
    NAME=$2

    # Check if template exists
    if [ ! -d "./$TEMPLATE" ]; then
        echo "Unknown template $TEMPLATE"
        exit 102
    fi

    # Check if instance already exists and ask for confirmation
    if [ -d "instances/$NAME" ]; then
        read -p "Instance \"$NAME\" already exists, uploads will be lost and data may get corrupted, continue? " -n 1 -r
        echo 

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi

    chmod +x $TEMPLATE/setup.sh
    (cd $TEMPLATE; ./setup.sh $NAME)
}
  
deploy() {
    if [[ $# -lt 1 || $# -gt 2 ]]; then
        echo "Illegal number of arguments, expected between 1 and 2, found $#"
        exit 201
    fi

    NAME=$1
    ENVIRONMENT=$2

    # If no environment is specified, update all environments
    if [ -z "$ENVIRONMENT" ]; then
        # Check if deployment exists
        PODS=$(kubectl get deployments | grep "$NAME-.*-deployment")
        if [ -z "$PODS" ]; then
            echo "Unknown instance \"$NAME\""
            exit 202
        fi

        for INSTANCE_FILE in $(find instances/$NAME -name "*-deployment.yaml" -type f); do
            DEPLOYMENT=$(echo $INSTANCE_FILE | grep -oP '(?<=instances/).*?(?=\-deployment.yaml)')
            DEPLOYMENT="${DEPLOYMENT/\//-}-deployment"

            kubectl patch deployment $DEPLOYMENT -p "{\"spec\": {\"template\": {\"metadata\": { \"labels\": {  \"redeploy\": \"$(date +%s)\"}}}}}"
        done
    else
        INSTANCE=$NAME-$ENVIRONMENT
        
        # Check if deployment exists
        PODS=$(kubectl get deployments | grep "$INSTANCE-deployment")
        if [ -z "$PODS" ]; then
            echo "Unknown instance \"$NAME\" for environment \"$ENVIRONMENT\""
            exit 202
        fi

        kubectl patch deployment $INSTANCE-deployment -p "{\"spec\": {\"template\": {\"metadata\": { \"labels\": {  \"redeploy\": \"$(date +%s)\"}}}}}"
    fi

    # Démarre les pod existants en mode maintenance
    #kubectl set env deployments $INSTANCE-deployment APP_ENV=maintenance
    #kubectl set image deployment/$INSTANCE-deployment mycontainer=myimage:latest
}

publish() {
    if [ "$#" -ne 1 ]; then
        echo "Illegal number of arguments, expected 1, found $#"
        exit 401
    fi

    NAME=$1

    # Build and push all images in the `images` folder of the instance
    for IMAGE in $(ls $NAME/images); do
        docker build -t wiilog/$IMAGE:latest $NAME/images/$IMAGE
        docker push wiilog/$IMAGE:latest
    done
}

usage() {
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

case $COMMAND in
    create-instance)    create_instance "$@" ;;
    deploy)             deploy "$@" ;;
    delete)             delete "$@" ;;
    publish)            publish "$@" ;;
    *)                  usage "$@" ;;
esac