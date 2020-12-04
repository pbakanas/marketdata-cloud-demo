#!/bin/bash

TOPICS=(orders marketdata)

for topic in ${TOPICS[*]}; do
    docker-compose exec kafka \
        kafka-topics --bootstrap-server kafka:9091 \
        --create \
        --topic ${topic} \
        --partitions 1 \
        --replication-factor 1
done