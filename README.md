# Kafka Audit Security ACLs

The objective of this project is to aduit (to a log file) the authorization of topics and the behavior of a client
when being authorized / not authorized by the broker.

**Note:** By default the audit information `authorizationInfo` is out to an internal topic. This behaviour is not suitable if you want to use something like metricbeat to index this information.

## Prerequisites
This project has a dependency on a running [Elastic stack](https://github.com/osodevops/docker-elk) We use the network created in this project to send data from filebeat to Elastic
```console
$ git clone git@github.com:osodevops/docker-elk.git
$ cd docker-elk
$ docker-compose up --build
```
 
## Environment startup

The environment deploys 1 Zookeeper and 1 Kafka broker, to start this example you can run the following:

To start the environment run:

`docker-compose up -d`

To stop the environment use (This will delete all volumes to avoid stale ACL configuration in Zookeeper):

`docker-compose down -v`

## Default Configuration

The Kafka broker is configured with SASL/Plaintext authentication and Zookeeper is configured with SASL/Digest
authentication. The brokers are adding ACLs to the Zookeeper nodes when
they write and the broker will not allow access to topics without ACLs set (`allow.everyone.if.no.acl.found=false`).

This is a strict setting and the broker has 3 users configured

* `admin` - configured as super user
* `broker` - configured as super user
* `producer`
* `consumer`

The script `create_topic` creates the topic `first-topic` and set the ACLs for user `producer` to write and the
user `consumer` to read from this topic (in the case of the consumer, from any consumer group id).

The JAAS files used to configure the usernames and passwords, as well as the client credentials used by the broker
are in the directory `security` of the repo (and they are mounted as `/opt/security` in broker and in zookeeper).

The broker will expose the port 9092 as a SASL authenticated port in the localhost.

This testing environment `docker-compose.yml` is using Confluent docker images 5.5.1 (This may work with older versions) 

`log4j.properties.template` is appeneded to the default configuration which creates a `authorizerAppender` to log authorization events to  `/var/log/kafka/kafka-authorizer.log`

## Usage

### 1. Installing a Kafka client
It is required to have Kafka CLI tool installed to be able to use this environment. The best way to do it in a Mac is:

`brew install kafka`

### 2. Create a test topic 
Run the `./create_topic.sh` script to connect to broker and create the topic with the included ACLs.

### 3. Producing to the broker
You are now able to produce messages to the topic by running:

`kafka-console-producer --broker-list localhost:9092 --producer.config client-properties/producer.properties --topic first-topic`

> The command above assumes that the topic first-topic was created and the ACLs for producing were assigned.
> To perform this action just run the script `create_topic.sh`

### 4. Consuming from the broker

Similarly to consumer from the topic:

`kafka-console-consumer --bootstrap-server localhost:9092 --consumer.config client-properties/consumer.properties --group test-consumer-group --topic first-topic`

> The command above assumes that the topic first-topic was created and the ACLs for producing were assigned.
> To perform this action just run the script `create_topic.sh`

## Test Cases
To best understand what audit information is logged we have created the following scenarios for you to test on your own.

#### Kafka Console CLI Commands

The commands below are executed from the directory where this repo was cloned (due to the client-properties relative directory)

#### Producer tests

##### 1. No authentication configured
| Step | Action |
|---|---|
| Pre-requisites | * None |
| Test Steps | * Execute the producer<br>`kafka-console-producer --broker-list localhost:9092 --topic first-topic`<br>(note that the `producer.config` is not added to cause the authentication mismatch) |
| Expected Results | * Client tries continuously to connect to the broker |
| Audit Log | Nothing logged in `kafka-authorizer.log` |

##### 2. No authorization for the topic
| Step | Action |
|---|---|
| Pre-requisites | * Remove the producer ACL<br>` kafka-acls --bootstrap-server localhost:9092 --command-config client-properties/adminclient.properties --topic first-topic --allow-principal User:producer --producer --remove`|
| Test Steps | * Execute the producer with the proper authentication<br>`kafka-console-producer --broker-list localhost:9092 --producer.config client-properties/producer.properties --topic first-topic` |
| Expected Results | * Client will connect but fail due to produce messages |
| Audit Log | `Principal = User:producer is Denied Operation = Describe from host = 192.168.16.1 on resource = Topic:LITERAL:first-topic` |

##### 3. Remove the authorization from a running producer
| Step | Action |
|---|---|
| Pre-requisites | * Make sure the producer ACL is in place |
| Test Steps | * Execute the producer with the proper authentication<br>`kafka-console-producer --broker-list localhost:9092 --producer.config client-properties/producer.properties --topic first-topic`<br> * Remove the producer ACL |
| Expected Results | * Client start producing normally<br>* Client will generate one error message for each producing attempt after the ACL removal |
| Audit Log | `Principal = User:producer is Denied Operation = Write from host = 192.168.16.1 on resource = Topic:LITERAL:first-topic` |

#### Consumer tests

##### 1. No authentication configured
| Step | Action |
|---|---|
| Pre-requisites | * None |
| Test Steps | * Execute the consumer<br>`kafka-console-consumer --bootstrap-server localhost:9092 --group test-consumer-group --topic first-topic`<br>(note that the `consumer.config` is not added to cause the authentication mismatch) |
| Expected Results | * Client tries continuously to connect to the broker |
| Audit Log | Nothing logged in `kafka-authorizer.log` |

##### 2. No authorization for the topic
| Step | Action |
|---|---|
| Pre-requisites | * Remove the consumer ACL<br>`kafka-acls --bootstrap-server localhost:9092 --command-config client-properties/adminclient.properties --topic first-topic --allow-principal User:consumer --consumer --remove --group "*"` |
| Test Steps | * Execute the consumer with the proper authentication<br>`kafka-console-consumer --bootstrap-server localhost:9092 --consumer.config client-properties/consumer.properties --group test-consumer-group --topic first-topic` |
| Expected Results | * Client will fail due to authorization error |
| Audit Log | `Principal = User:consumer is Denied Operation = Describe from host = 192.168.16.1 on resource = Group:LITERAL:test-consumer-group`  |

##### 3. Remove the authorization from a running consumer
| Step | Action |
|---|---|
| Pre-requisites | * Make sure the consumer ACL is in place |
| Test Steps | * Execute the consumer with the proper authentication<br>`kafka-console-consumer --bootstrap-server localhost:9092 --consumer.config client-properties/consumer.properties --group test-consumer-group --topic first-topic`<br> * Remove the consumer ACL |
| Expected Results | * Client start consuming normally<br>* Client will generate one error message once the ACL is removed |
| Audit Log | `Principal = User:consumer is Denied Operation = Read from host = 192.168.16.1 on resource = Topic:LITERAL:first-topic` |

##### 4. No authorization for the consumer group
| Step | Action |
|---|---|
| Pre-requisites | * Change the consumer ACL to authorize only a specific consumer group (different from test-consumer-group) |
| Test Steps | * Execute the consumer with the proper authentication<br>`kafka-console-consumer --bootstrap-server localhost:9092 --consumer.config client-properties/consumer.properties --group test-consumer-group --topic first-topic` |
| Expected Results | * Client will fail due to authorization error |
| Audit Log | `[2020-09-09 19:55:15,732] Principal = User:consumer is Denied Operation = Describe from host = 192.168.16.1 on resource = Group:LITERAL:test-consumer-group` |

## Grok Parsing Patterns
TODO!!