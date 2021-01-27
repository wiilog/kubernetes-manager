function initialize_iot() {
    echo "IOT cluster creation"
    echo ""
    echo "Namespace creation...."
    kubectl apply -f ../configs/iot/namespace.yml
    echo "Secret creation...."
    kubectl apply -f ../configs/iot/secret.yml
    echo ""
}

initialize_iot
