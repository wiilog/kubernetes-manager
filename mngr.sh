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

    if [ ! -d "./$TEMPLATE" ]; then
        echo "Unknown template $TEMPLATE"
        exit 102
    fi

    chmod +x $TEMPLATE/create.sh
    (cd $TEMPLATE; ./create.sh $NAME)
}
  
deploy() {
    if [[ $# -lt 1 || $# -gt 2 ]]; then
        echo "Illegal number of arguments, expected between 1 and 2, found $#"
        exit 201
    fi

    NAME=$1
    ENVIRONMENT=$2

    if [ -z "$ENVIRONMENT" ]; then
        PODS=$(kubectl get pods | grep "$NAME-.*-deployment" | tr -s ' ')
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
        
        PODS=$(kubectl get pods | grep "$INSTANCE-deployment" | tr -s ' ')
        if [ -z "$PODS" ]; then
            echo "Unknown instance \"$NAME\" for environment \"$ENVIRONMENT\""
            exit 202
        fi

        kubectl patch deployment $INSTANCE-deployment -p "{\"spec\": {\"template\": {\"metadata\": { \"labels\": {  \"redeploy\": \"$(date +%s)\"}}}}}"
    fi


    # Démarre les pod existants en mode maintenance
    #kubectl set env deployments $INSTANCE-deployment APP_ENV=maintenance
    #kubectl set image deployment/$INSTANCE-deployment mycontainer=myimage:latest

    # while read -r POD; do
    #     FULL_NAME=$(echo "$POD" | cut -d ' ' -f 1)
    #     STATUS=$(echo "$POD" | cut -d ' ' -f 3)

    # done <<< $PODS

    # echo $(readarray -t y <<< "$FULL_NAME")
    # echo $(readarray -t y <<< "$STATUS")

    # Redeploy a pod
    # kubectl get pods | grep wiilogs-deployment | tr -s ' ' | cut -d ' ' -f X
    # kubectl patch deployment wiilogs-deployment -p "{\"spec\": {\"template\": {\"metadata\": { \"labels\": {  \"redeploy\": \"$(date +%s)\"}}}}}"
}

publish() {
    if [ "$#" -ne 1 ]; then
        echo "Illegal number of arguments, expected 1, found $#"
        exit 401
    fi

    NAME=$1

    docker build -t wiilog/$NAME:latest $NAME/image/
    docker push wiilog/$NAME:latest
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