![alt text](https://github.com/pbakanas/marketdata-cloud-demo/blob/master/demo_topology.png)

Huge thanks to [Chris Matta](https://github.com/cjmatta) who put together a lot of the components for this demo including the SSE connector and the orders schema.  

_NOTE:  This demo uses [iexcloud.io](https://iexcloud.io/) to get the marketdata.  You will have to create your own IEX token to interact with datasets._

# TO SETUP DEMO

1. Update the /scripts/connectors/marketdata.json file with your IEX token.

2. create a .env file with the follwing properties
```
BOOTSTRAP_SERVERS=
API_KEY=
API_SECRET=
SCHEMA_REGISTRY_URL=
SR_API_SECRET=
```

3. Bring up connect via docker
```
docker compose up -d
```

4. Check that it is running
```
docker logs connect 

docker-compose exec connect curl -s -X GET http://connect:8083/connectors | jq .

docker-compose exec connect curl -s -X GET http://connect:8083/connector-plugins | jq .
```

## START MARKET DATA CONNECT

1. run market data
```
./scripts/connectors/submit-connector.sh scripts/connectors/marketdata.json
```

2. Give it structure with KSQL by first registering Marketdata with KSQL, extracting the JSON fields, and assigning a key
```
CREATE STREAM MARKETDATA (id STRING, data STRING) WITH (KAFKA_TOPIC='marketdata-raw', VALUE_FORMAT='avro');      


CREATE STREAM MARKET_DATA_LIVE WITH (KAFKA_TOPIC='MARKET_DATA_LIVE', VALUE_FORMAT='avro') as select extractjsonfield(data, '$[0].symbol') as SYMBOL, CAST(extractjsonfield(data, '$[0].latestPrice') as DOUBLE) as LATESTPRICE, CAST(extractjsonfield(data, '$[0].open') as DOUBLE) as OPEN, CAST(extractjsonfield(data, '$[0].close') as DOUBLE) as CLOSE, CAST(extractjsonfield(data, '$[0].high') as DOUBLE) as HIGH, CAST(extractjsonfield(data, '$[0].low') as DOUBLE) as LOW, CAST(extractjsonfield(data, '$[0].volume') as DOUBLE) as VOLUME, CAST(extractjsonfield(data, '$[0].lastTradeTime') as BIGINT) as LASTTRADETIME FROM marketdata;


CREATE STREAM MARKET_DATA_LIVE_KEYED WITH (KAFKA_TOPIC='MARKET_DATA_LIVE_KEYED', VALUE_FORMAT='avro') as select * FROM MARKET_DATA_LIVE PARTITION BY SYMBOL;
```

3. Create a couple tables for further KSQL exploration
```
CREATE TABLE MARKETDATA_TABLE WITH (KAFKA_TOPIC='MARKETDATA_TABLE') AS 
SELECT
  SYMBOL as SYMBOL,
  LATEST_BY_OFFSET(LATESTPRICE) as LATESTPRICE,
  LATEST_BY_OFFSET(OPEN) as OPEN,
  LATEST_BY_OFFSET(CLOSE) as CLOSE,
  LATEST_BY_OFFSET(HIGH) as HIGH,
  LATEST_BY_OFFSET(LOW) as LOW,
  LATEST_BY_OFFSET(VOLUME) as VOLUME,
  LATEST_BY_OFFSET(LASTTRADETIME) as LASTTRADETIME
FROM MARKET_DATA_LIVE_KEYED
GROUP BY symbol;


CREATE TABLE MARKETDATA_TOTAL_RUNNING WITH (KAFKA_TOPIC='MARKETDATA_TOTAL_RUNNING') AS 
SELECT
  SYMBOL as SYMBOL,
  SUM(LATESTPRICE) as TOTAL_RUNNING_PRICE,
  SUM(VOLUME) as TOTAL_RUNNING_VOLUME
FROM MARKET_DATA_LIVE_KEYED
GROUP BY symbol;

```

4. To delete / pause / resume connector
```
docker-compose exec connect curl -s -X DELETE http://connect:8083/connectors/marketdata/ | jq .
docker-compose exec connect curl -s -X PUT http://connect:8083/connectors/marketdata/pause | jq .
docker-compose exec connect curl -s -X PUT http://connect:8083/connectors/marketdata/resume | jq .
```


## START ORDERS AND STOCKTRADES CONNECTORS

1. Run orders and stocktrades
```
./scripts/connectors/submit-connector.sh scripts/connectors/stocktrades-datagen.json
./scripts/connectors/submit-connector.sh scripts/connectors/orders-datagen.json
```

2. Enrich the orders:

Create a stream of orders-raw
```
CREATE STREAM orders (orderid INT, side STRING, quantity INT, symbol STRING, account STRING, userid STRING) WITH (KAFKA_TOPIC='orders-raw', VALUE_FORMAT='avro');
```
Rekey the orders data
```
CREATE STREAM ORDERS_REKEY WITH (KAFKA_TOPIC='ORDERS_REKEY',VALUE_FORMAT='AVRO')
AS SELECT
  symbol as symbol
, side as side
, quantity as quantity
, orderid as orderid
, userid as userid
, account as account
FROM orders PARTITION BY ORDERID;
```
Join marketdata table and orders to get trade costs
```
CREATE STREAM ORDERS_ENRICHED WITH (KAFKA_TOPIC='ORDERS_ENRICHED',VALUE_FORMAT='AVRO')
AS SELECT a.ORDERID,
a.SYMBOL,
a.QUANTITY,
b.LATESTPRICE,
(a.QUANTITY * b.LATESTPRICE) as TOTAL_COST
FROM ORDERS_REKEY a JOIN MARKETDATA_TABLE b on a.SYMBOL=b.SYMBOL PARTITION BY ORDERID; 
```

## START S3 SINK

Use the fully managed S3 sink connector to export data from topics to S3 objects in either Avro, JSON, or Bytes formats.
See documentation: https://docs.confluent.io/cloud/current/connectors/cc-s3-sink.html
