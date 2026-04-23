We will Apicurio as schema registry. 

It must be possible to authenticate using entra oauth and rbac.
It should be installed in private net
It should be exposed via app gateway on port 443 using https
It should be backed by a postgres database

1. Event hubs schema registry is not compatible with confluent and we will therefore not use it
2. Make sure schema tests that are failing are folllowing guidelines and only uses confluent compatible setting and client.properties (it will fail since we have not started this)
3. Clean away azure schema registry and replace it with Apicurio
4. Make sure kafka part is operational while doing this
