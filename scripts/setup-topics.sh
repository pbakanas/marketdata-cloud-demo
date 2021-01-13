#!/bin/bash
DIR=$(cd $(dirname $0) && pwd)

if [[ ! -f $DIR/../.env ]]; then
	echo "Error: missing .env file in the root of this demo, please see the README"
	exit 1
fi

source $DIR/../.env
echo ${BOOTSTRAP_SERVERS}

if [[ ! -f $DIR/client.properties ]]; then
	echo "client.properties not found, generating..."
	cat <<EOF> ${DIR}/client.properties
		bootstrap.servers=${BOOTSTRAP_SERVERS}
		security.protocol=SASL_SSL
		sasl.jaas.config=org.apache.kafka.common.security.plain.PlainLoginModule required username='${API_KEY}'   password='${API_SECRET}';
		sasl.mechanism=PLAIN
		client.dns.lookup=use_all_dns_ips
EOF
fi

TOPICS=(orders marketdata)

for topic in ${TOPICS[*]}; do
    docker run --rm \
	-v ${DIR}/client.properties:/client.properties \
	confluentinc/cp-kafka:latest \
        kafka-topics --bootstrap-server ${BOOTSTRAP_SERVERS} \
	--command-config /client.properties \
        --create \
        --topic ${topic} \
        --partitions 1
done
