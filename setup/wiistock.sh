function initialize_wiistock() {
    kubectl apply -f /opt/kubernetes-manager/configs/wiistock.yaml

    kubectl -n wiistock create secret generic docker-token \
        --from-file=.dockerconfigjson=$HOME/.docker/config.json \
        --type=kubernetes.io/dockerconfigjson
        
    kubectl apply -f /opt/kubernetes-manager/configs/nginx-ingress.yaml
    kubectl apply -f /opt/kubernetes-manager/configs/cert-manager.yaml

    echo
    echo
    echo "Waiting for cert-manager"

    sleep 30
    kubectl apply -f /opt/kubernetes-manager/configs/letsencrypt-issuer.yaml
}

initialize_wiistock