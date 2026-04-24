# This project is a small Poc

## Objectives for this setup
    -   Make a infra setup that offers "Kafka client compatibility" using standard client libraries. First consumer is Pega Cloud.
    -   Find a config of azure event hub and api gateway that can be used for external parties.
    -   Production grade security
    -   Favour use of azure native products
    -   Second use open source products
    
## PHASE 1, current for building internal knowledge

## Constraint: Confluent KafkaSerdes compatibility is the gate
    -   There is no value in setting up, testing, or documenting any schema registry feature, authentication flow, or client configuration that is not supported by **Confluent KafkaSerdes with schema support** (i.e. `kafka-avro-serializer`, `kafka-avro-deserializer` and the Confluent Schema Registry client).
    -   If a feature or workaround cannot be expressed as standard properties consumed by those serdes, it must not be pursued. Fix the infrastructure instead.

## PHASE 2, when confluent console client can send and receive messages with schema enabled serdes
    -   Ship client settings to Pega team for verification 
    -   Make use of poc as Template for real implementation

    

