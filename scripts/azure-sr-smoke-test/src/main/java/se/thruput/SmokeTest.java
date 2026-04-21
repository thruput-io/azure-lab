package se.thruput;

import com.azure.core.credential.TokenCredential;
import com.azure.identity.ClientSecretCredentialBuilder;
import com.microsoft.azure.schemaregistry.kafka.avro.KafkaAvroDeserializerConfig;
import com.microsoft.azure.schemaregistry.kafka.avro.KafkaAvroSerializerConfig;
import org.apache.avro.Schema;
import org.apache.avro.generic.GenericData;
import org.apache.avro.generic.GenericRecord;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.consumer.ConsumerRecords;
import org.apache.kafka.clients.consumer.KafkaConsumer;
import org.apache.kafka.clients.producer.KafkaProducer;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;

import java.io.IOException;
import java.io.InputStream;
import java.time.Duration;
import java.util.Collections;
import java.util.Properties;

/**
 * Smoke test: produces one Avro message to orders.placed topic via App Gateway (port 9093),
 * then consumes it back, using Azure Schema Registry for Kafka serializer.
 *
 * Config is loaded from client.properties (path passed as first CLI arg or /etc/kafka/client.properties).
 */
public class SmokeTest {

    private static final String AVRO_SCHEMA_JSON = "{"
            + "\"type\":\"record\","
            + "\"name\":\"OrderPlaced\","
            + "\"namespace\":\"se.thruput.orders\","
            + "\"fields\":["
            + "  {\"name\":\"order_id\",\"type\":\"string\"},"
            + "  {\"name\":\"product\",\"type\":\"string\"},"
            + "  {\"name\":\"quantity\",\"type\":\"int\"},"
            + "  {\"name\":\"timestamp\",\"type\":\"long\"}"
            + "]}";

    public static void main(String[] args) throws Exception {
        String propsPath = args.length > 0 ? args[0] : "/etc/kafka/client.properties";
        Properties props = loadProperties(propsPath);

        String bootstrapServers = required(props, "bootstrap.servers");
        String topic = props.getProperty("topic", "orders.placed");
        String schemaRegistryUrl = required(props, "schema.registry.url");
        String schemaGroup = required(props, "schema.group");
        String tenantId = required(props, "tenant.id");
        String clientId = required(props, "client.id");
        String clientSecret = required(props, "client.secret");

        long expectedTs = System.currentTimeMillis();
        String orderId = "check-" + expectedTs;

        System.out.println("==> bootstrap.servers=" + bootstrapServers);
        System.out.println("==> schema.registry.url=" + schemaRegistryUrl);
        System.out.println("==> topic=" + topic);
        System.out.println("==> expectedTs=" + expectedTs);

        TokenCredential credential = new ClientSecretCredentialBuilder()
                .tenantId(tenantId)
                .clientId(clientId)
                .clientSecret(clientSecret)
                .build();

        // Produce
        produce(props, bootstrapServers, topic, schemaRegistryUrl, schemaGroup, credential,
                orderId, expectedTs);

        // Consume
        consume(props, bootstrapServers, topic, schemaRegistryUrl, schemaGroup, credential,
                orderId, expectedTs);
    }

    private static void produce(Properties baseProps, String bootstrapServers, String topic,
            String schemaRegistryUrl, String schemaGroup, TokenCredential credential,
            String orderId, long expectedTs) throws Exception {
        Properties producerProps = new Properties();
        // Kafka broker settings from base props (includes sasl.* and security.protocol)
        copyKafkaBrokerSettings(baseProps, producerProps);
        producerProps.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        producerProps.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class.getName());
        producerProps.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG,
                com.microsoft.azure.schemaregistry.kafka.avro.KafkaAvroSerializer.class.getName());
        producerProps.put(KafkaAvroSerializerConfig.SCHEMA_REGISTRY_URL_CONFIG, schemaRegistryUrl);
        producerProps.put(KafkaAvroSerializerConfig.SCHEMA_GROUP_CONFIG, schemaGroup);
        producerProps.put(KafkaAvroSerializerConfig.AUTO_REGISTER_SCHEMAS_CONFIG, false);
        producerProps.put(KafkaAvroSerializerConfig.AVRO_USE_LOGICAL_TYPE_CONVERTERS_CONFIG, true);
        // Pass credential via token credential property
        producerProps.put("token.credential", credential);

        Schema schema = new Schema.Parser().parse(AVRO_SCHEMA_JSON);
        GenericRecord record = new GenericData.Record(schema);
        record.put("order_id", orderId);
        record.put("product", "endpoint-check");
        record.put("quantity", 1);
        record.put("timestamp", expectedTs);

        System.out.println("==> Producing Avro message: " + record);
        try (KafkaProducer<String, Object> producer = new KafkaProducer<>(producerProps)) {
            ProducerRecord<String, Object> kafkaRecord = new ProducerRecord<>(topic, orderId, record);
            producer.send(kafkaRecord).get();
            System.out.println("==> Produce: OK");
        }
    }

    private static void consume(Properties baseProps, String bootstrapServers, String topic,
            String schemaRegistryUrl, String schemaGroup, TokenCredential credential,
            String orderId, long expectedTs) throws Exception {
        Properties consumerProps = new Properties();
        copyKafkaBrokerSettings(baseProps, consumerProps);
        consumerProps.put(ConsumerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrapServers);
        consumerProps.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class.getName());
        consumerProps.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG,
                com.microsoft.azure.schemaregistry.kafka.avro.KafkaAvroDeserializer.class.getName());
        consumerProps.put(KafkaAvroDeserializerConfig.SCHEMA_REGISTRY_URL_CONFIG, schemaRegistryUrl);
        consumerProps.put(KafkaAvroDeserializerConfig.SCHEMA_GROUP_CONFIG, schemaGroup);
        consumerProps.put(KafkaAvroDeserializerConfig.AVRO_SPECIFIC_READER_CONFIG, false);
        consumerProps.put("token.credential", credential);
        consumerProps.put(ConsumerConfig.GROUP_ID_CONFIG, "smoke-test-" + expectedTs);
        consumerProps.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "latest");
        consumerProps.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, "true");

        System.out.println("==> Consuming from topic " + topic + " (looking for order_id=" + orderId + ")...");
        try (KafkaConsumer<String, GenericRecord> consumer = new KafkaConsumer<>(consumerProps)) {
            consumer.subscribe(Collections.singletonList(topic));
            // Poll up to 30s
            long deadline = System.currentTimeMillis() + 30000;
            boolean found = false;
            while (System.currentTimeMillis() < deadline && !found) {
                ConsumerRecords<String, GenericRecord> records = consumer.poll(Duration.ofSeconds(5));
                for (ConsumerRecord<String, GenericRecord> r : records) {
                    System.out.println("==> Received: " + r.value());
                    Object ts = r.value().get("timestamp");
                    if (orderId.equals(r.key()) && ts != null && Long.parseLong(ts.toString()) == expectedTs) {
                        found = true;
                        break;
                    }
                }
            }
            if (!found) {
                System.err.println("FAIL: Did not receive expected message with order_id=" + orderId);
                System.exit(1);
            }
        }
        System.out.println("PASS: Smoke test completed successfully");
    }

    private static void copyKafkaBrokerSettings(Properties src, Properties dest) {
        for (String key : new String[]{
            "security.protocol", "sasl.mechanism", "sasl.jaas.config",
            "sasl.login.callback.handler.class", "sasl.oauthbearer.token.endpoint.url"
        }) {
            if (src.containsKey(key)) {
                dest.put(key, src.getProperty(key));
            }
        }
    }

    private static Properties loadProperties(String path) throws IOException {
        Properties props = new Properties();
        java.io.File file = new java.io.File(path);
        try (InputStream is = new java.io.FileInputStream(file)) {
            props.load(is);
        }
        return props;
    }

    private static String required(Properties props, String key) {
        String val = props.getProperty(key);
        if (val == null || val.isBlank()) {
            throw new IllegalArgumentException("Missing required property: " + key);
        }
        return val.trim();
    }
}
