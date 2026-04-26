## Objective
Turn terraform code into self-explained and verified code.
Make target functional requirement and artifacts part of integration tests.
1. Topics with schema-enforced messages compatible with confluent
2. Ready to use config files for clients java (Pega) and go (reference)

<ai: Flesh out how important it that config files are first citizen artifacts and will be delivered to Pega>

## Rules
- You MUST follow the workflow

## Strategy - modules with tests
Move tests into terraform standard structure so the purpose is clearer
Make config files for outputs of main module

### Modules
#### Layout
1. keyvault - verify read/write
2. kafka
   2.1  eventhub - int.test very send/receive wo schema against internal endpoints
   2.3  schema-registry -  int.test  verify get/post of schemas using confluent endpoints
   2.4  app gateway - int.test verify port 443 and 1093 with 
#### Output Kafka module should return the following:
-   go-client.json (reference)
  - java-client.properties

#### Unit tests for Kafka module:
1. verify that produced go-client.json has all parameters as @oauth.json
2. verify that produced java-client.properties has all parameters as@oauth.json

#### e2e test for Kafka module:
1. Create a topic via rest api - internal.test.test-event.event.v1
2. Create a json schema via rest api, subject name following confluent naming standards 
3. Send and receive a message using cp-kafka 8.2.0, only allowed parameters will be kafka-module output client-config.json
4. Send and receive a message using confluent java container, only parameters passed to test will be kafka-module output client-config.properties

### Cleanup 
1. Remove left-overs


#### Workflow
Make new branch create one module / submodule at the time
1. Create new branch
2. Create module
3. Create unit tests
4. Create integration tests
5. Make tests pass
5. Review code change with review skill
6. Fix any issues
7. loop to 5
8. Merge to master