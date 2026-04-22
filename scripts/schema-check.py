#!/usr/bin/env python3
"""
Avro produce + consume smoke test using:
  - confluent-kafka (official Confluent Python client)
  - azure-schemaregistry + azure-schemaregistry-avroencoder (Azure EH Schema Registry)

Only input: client.properties file path (--props-file)

Usage:
    python3 scripts/schema-check.py --props-file /path/to/client.properties

Required keys in client.properties:
    bootstrap.servers, topic,
    sasl.oauthbearer.token.endpoint.url, sasl.jaas.config
    (clientId and clientSecret are parsed from sasl.jaas.config)
"""

import argparse
import json
import re
import sys
import time

SCHEMA_GROUP = "orders-schema-group"
SCHEMA_NAME  = "OrderPlaced"
SCHEMA_DEF   = json.dumps({
    "type": "record", "name": "OrderPlaced", "namespace": "io.thruput.orders",
    "fields": [
        {"name": "order_id",  "type": "string"},
        {"name": "product",   "type": "string"},
        {"name": "quantity",  "type": "int"},
        {"name": "timestamp", "type": "long"},
    ]
})


def load_props(path: str) -> dict:
    props = {}
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, _, v = line.partition("=")
                props[k.strip()] = v.strip()
    return props


def main():
    parser = argparse.ArgumentParser(description="Avro Kafka smoke test")
    parser.add_argument("--props-file", required=True, help="Path to client.properties")
    args = parser.parse_args()

    props = load_props(args.props_file)

    for key in ("bootstrap.servers", "topic", "sasl.oauthbearer.token.endpoint.url", "sasl.jaas.config"):
        if key not in props:
            print(f"ERROR: client.properties missing required key: {key}")
            sys.exit(1)

    jaas          = props["sasl.jaas.config"]
    client_id_m   = re.search(r'clientId="([^"]+)"',     jaas)
    client_sec_m  = re.search(r'clientSecret="([^"]+)"', jaas)
    tenant_id_m   = re.search(r'/([^/]+)/oauth2',        props["sasl.oauthbearer.token.endpoint.url"])

    if not (client_id_m and client_sec_m and tenant_id_m):
        print("ERROR: Could not parse clientId/clientSecret/tenantId from client.properties")
        sys.exit(1)

    client_id     = client_id_m.group(1)
    client_secret = client_sec_m.group(1)
    tenant_id     = tenant_id_m.group(1)

    bootstrap    = props["bootstrap.servers"]
    topic        = props["topic"]
    domain       = bootstrap.split(":")[0]
    sr_namespace = domain  # Azure EH SR fully-qualified namespace == domain

    print(f"bootstrap    : {bootstrap}")
    print(f"topic        : {topic}")
    print(f"sr_namespace : {sr_namespace}")
    print(f"schema_group : {SCHEMA_GROUP}")

    # ------------------------------------------------------------------
    # 1. Register Avro schema with Azure EH Schema Registry
    # ------------------------------------------------------------------
    from azure.identity import ClientSecretCredential
    from azure.schemaregistry import SchemaRegistryClient
    from azure.schemaregistry.encoder.avroencoder import AvroEncoder

    credential = ClientSecretCredential(
        tenant_id=tenant_id, client_id=client_id, client_secret=client_secret
    )
    sr_client = SchemaRegistryClient(
        fully_qualified_namespace=sr_namespace, credential=credential
    )

    print(f"\n==> Registering schema '{SCHEMA_NAME}' in '{SCHEMA_GROUP}' ...")
    sp = sr_client.register_schema(
        group_name=SCHEMA_GROUP, name=SCHEMA_NAME, definition=SCHEMA_DEF, format="Avro"
    )
    print(f"PASS: Schema registered — id={sp.id}")

    encoder = AvroEncoder(client=sr_client, group_name=SCHEMA_GROUP, auto_register=True)

    # ------------------------------------------------------------------
    # 2. Build confluent-kafka config from client.properties
    # ------------------------------------------------------------------
    kafka_conf = {
        "bootstrap.servers":                   bootstrap,
        "security.protocol":                   "SASL_SSL",
        "sasl.mechanisms":                     "OAUTHBEARER",
        "sasl.oauthbearer.method":             "oidc",
        "sasl.oauthbearer.token.endpoint.url": props["sasl.oauthbearer.token.endpoint.url"],
        "sasl.oauthbearer.client.id":          client_id,
        "sasl.oauthbearer.client.secret":      client_secret,
        "sasl.oauthbearer.scope":              "https://eventhubs.azure.net/.default",
        "enable.ssl.certificate.verification": True,
    }

    # ------------------------------------------------------------------
    # 3. Produce Avro message
    # ------------------------------------------------------------------
    from confluent_kafka import Producer, Consumer, KafkaException, KafkaError

    payload       = {
        "order_id":  f"schema-check-{int(time.time())}",
        "product":   "test-widget",
        "quantity":  1,
        "timestamp": int(time.time() * 1000),
    }
    encoded_bytes = bytes(encoder.encode(payload, schema_format="Avro"))

    producer  = Producer(kafka_conf)
    delivered = {"ok": False, "err": None}

    def on_delivery(err, msg):
        if err:
            delivered["err"] = err
        else:
            delivered["ok"] = True
            print(f"PASS: Produced to {msg.topic()} partition={msg.partition()} offset={msg.offset()}")

    print(f"\n==> Producing Avro message to '{topic}' ...")
    producer.produce(topic, value=encoded_bytes, callback=on_delivery)
    producer.flush(timeout=30)

    if not delivered["ok"]:
        print(f"FAIL: Delivery failed — {delivered['err']}")
        sys.exit(1)

    # ------------------------------------------------------------------
    # 4. Consume + decode Avro message
    # ------------------------------------------------------------------
    consumer_conf = {
        **kafka_conf,
        "group.id":           f"schema-check-{int(time.time())}",
        "auto.offset.reset":  "latest",
        "session.timeout.ms": 30000,
    }
    consumer = Consumer(consumer_conf)
    consumer.subscribe([topic])

    print(f"\n==> Consuming Avro message from '{topic}' (timeout 45s) ...")
    deadline, consumed = time.time() + 45, None
    while time.time() < deadline:
        msg = consumer.poll(2.0)
        if msg is None:
            continue
        if msg.error():
            if msg.error().code() == KafkaError._PARTITION_EOF:
                continue
            raise KafkaException(msg.error())
        consumed = msg
        break
    consumer.close()

    if consumed is None:
        print(f"FAIL: No message consumed from '{topic}' within timeout")
        sys.exit(1)

    decoded = encoder.decode(consumed.value())
    print(f"Decoded  : {decoded}")
    print(f"PASS: Avro produce + consume round-trip successful on '{topic}'")


if __name__ == "__main__":
    main()
