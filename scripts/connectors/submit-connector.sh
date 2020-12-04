#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG=$1

if [[ ! -f ${CONFIG} ]]; then
  echo "Error: file ${CONFIG} not found!"
  exit 1
fi
DATA=$(cat ${CONFIG})
docker-compose exec connect curl -X POST -H "Content-Type: application/json" --data "${DATA}" http://connect:8083/connectors