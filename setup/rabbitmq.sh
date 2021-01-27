function create_secret() {
    echo ""
    echo "Erlang cookie creation...."
    (openssl rand -base64 128 | tr --delete '=/\n') >cookie

    kubectl -n rabbitmq create secret generic erlang-cookie --from-file=./cookie
    rm cookie
}

function create_credentials() {
    echo "RabbitMQ management credentials"
    read -pr "User: " USER
    read -psr "Password: " PWD
    echo ""
    echo "$USER" >user
    echo "$PWD" >pass
    kubectl create secret generic rabbitmq-admin --from-file=./user --from-file=./pass
    rm user && rm pass
}

function get_service_ip() {
    kubectl -n rabbitmq get svc rabbitmq-client --no-headers | tr -s '   ' | cut -d ' ' -f 4
}

function initialize_rabbitmq() {
    echo "RabbitMQ cluster creation"
    echo ""
    echo "Namespace creation...."
    kubectl apply -f ../configs/rabbitmq/namespace.yml
    echo ""
    echo "RBAC creation...."
    kubectl apply -f ../configs/rabbitmq/rbac.yml
    echo ""
    echo "Cluster creation...."
    kubectl apply -f ../configs/rabbitmq/cluster.yml
    create_secret
    create_credentials
    echo ""
    echo "Secret creation...."
    kubectl apply -f ../configs/rabbitmq/secret.yml
    echo ""
    echo "Config creation...."
    kubectl apply -f ../configs/rabbitmq/config.yml
    echo ""
    echo "Statefulset creation...."
    kubectl apply -f ../configs/rabbitmq/statefulset.yml
    echo ""
    echo "Service creation...."
    kubectl apply -f ../configs/rabbitmq/service.yml

    while [[ -z $(get_service_ip) ]]; do
        sleep 1
    done
    echo "RabbitMQ cluster configuration is now done, to access the administration interface, reach the following IP with 15672 port and login with the previously entered credentials"
    get_service_ip
}

initialize_rabbitmq
