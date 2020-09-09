#/bin/bash

kafka-topics --bootstrap-server localhost:9092 --create --topic first-topic --command-config client-properties/adminclient.properties --partitions 1 --replication-factor 1

kafka-acls --bootstrap-server localhost:9092 --command-config client-properties/adminclient.properties --topic first-topic --allow-principal User:producer --producer --add

kafka-acls --bootstrap-server localhost:9092 --command-config client-properties/adminclient.properties --topic first-topic --allow-principal User:consumer --consumer --add --group "test-consumer-group-1"
