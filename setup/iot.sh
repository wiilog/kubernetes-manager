function initialize_iot() {
    echo "IOT cluster creation"
    echo ""
    echo "Namespace creation...."
    kubectl apply -f ../configs/iot/namespace.yml
}

initialize_iot
