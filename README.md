![alt text](https://github.com/pbakanas/marketdata-cloud-demo/blob/master/demo_topology.png)

Credit to [Chris Matta](https://github.com/cjmatta) who put together a lot of the components for this demo including the SSE connector, connector scripts and the orders schema.  

_NOTE:  
This demo uses [iexcloud.io](https://iexcloud.io/) to get the marketdata.  You will have to create your own IEX token to interact with datasets. 
This demo also requires a Confluent Cloud cluster_

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

1. Run the market data connector:  
```
./scripts/connectors/submit-connector.sh scripts/connectors/marketdata.json
```
You should see market data events produced into the "marketdata-raw" topic - one event for each Symbol buy or sell. 

2. If you have not set up KSQL cluster in Confluent Cloud - do so following these instructions: [Add KSQL to the Cluster](https://docs.confluent.io/cloud/current/get-started/index.html#section-2-add-ksql-cloud-to-the-cluster)

3. Execute the followign KSQL queries in the KSQL Editor to clean up the market data events:

Register Marketdata with KSQL
```
CREATE STREAM MARKETDATA (id STRING, data STRING) WITH (KAFKA_TOPIC='marketdata-raw', VALUE_FORMAT='avro');      
```
Extract the JSON fields
```
CREATE STREAM MARKET_DATA_LIVE WITH (KAFKA_TOPIC='MARKET_DATA_LIVE', VALUE_FORMAT='avro') as select extractjsonfield(data, '$[0].symbol') as SYMBOL, CAST(extractjsonfield(data, '$[0].latestPrice') as DOUBLE) as LATESTPRICE, CAST(extractjsonfield(data, '$[0].open') as DOUBLE) as OPEN, CAST(extractjsonfield(data, '$[0].close') as DOUBLE) as CLOSE, CAST(extractjsonfield(data, '$[0].high') as DOUBLE) as HIGH, CAST(extractjsonfield(data, '$[0].low') as DOUBLE) as LOW, CAST(extractjsonfield(data, '$[0].volume') as DOUBLE) as VOLUME, CAST(extractjsonfield(data, '$[0].lastTradeTime') as BIGINT) as LASTTRADETIME FROM marketdata;
```
Assign a key
```
CREATE STREAM MARKET_DATA_LIVE_KEYED WITH (KAFKA_TOPIC='MARKET_DATA_LIVE_KEYED', VALUE_FORMAT='avro') as select * FROM MARKET_DATA_LIVE PARTITION BY SYMBOL;
```

4. Create a couple tables for further KSQL exploration
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

_Notes To delete / pause / resume connector use the below commands_
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

2. Execute the followign KSQL queries in the KSQL Editor to clean up the order events

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
