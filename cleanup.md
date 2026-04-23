
Right now if you execute the 'Kafka Tests' git action the kafka tests passes. Plz do it to verify.
The settings that are used by the confluent console application in that test are important. It is our only known working state.
I want to be able to take the settings for that and give the to Pega-team so they can verify from their side. Can you figure out exactly what those are and verify them by running confluent console in docker via command line? 
My idea was that the client.properties file that is stored i keyvault and made accessible via Download client.properties  gihub action w