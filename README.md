# Chordy: A Distributed Hash Table

## Overview

This repository contains the implementation of **Chordy**, a distributed hash table (DHT) based on the **Chord** protocol. The Chord architecture is a scalable and decentralized way to store and retrieve data in a distributed system. It supports node joins and departures while maintaining a consistent and efficient key-value lookup.

### Features:
- **Ring Structure Implementation** (node1.erl): Nodes can join and form a consistent ring using periodic stabilization.
- **Distributed Storage** (node2.erl): Nodes can store key-value pairs and perform lookups in a distributed manner.
- **Failure Handling** (node3.erl): Introduces logic to handle node failures using successor tracking.
- **Data Replication** (node4.erl): Ensures data integrity through replication, mitigating the risks of data loss when a node fails.

## Table of Contents
- [Getting Started](#getting-started)
- [Usage](#usage)
  - [Manual Testing](#manual-testing)
  - [Benchmarking](#benchmarking)
  - [Failure Handling](#failure-handling)
  - [Replication](#replication)
- [Evaluation](#evaluation)
- [Conclusion](#conclusion)

---

## Getting Started

### Prerequisites
- **Erlang/OTP** installed on your system.
  
To install Erlang, visit the [official Erlang website](https://www.erlang.org/downloads).

### Clone the Repository
```bash
git clone https://github.com/yourusername/chordy.git
cd chordy
````
### Compile the Modules
Make sure you compile the Erlang files before testing:

```bash
erlc node1.erl
erlc node2.erl
erlc node3.erl
erlc node4.erl
```
## Usage
### Manual Testing
You can manually test the system using the commands below. First, create a node and start adding keys to the system.
```bash
1> Pid1 = test:start(node2).
2> test:start(node2, 3, Pid1).
3> Keys = test:keys(10).
4> test:add(Keys, Pid1).
5> test:check(Keys, Pid1).
```
This will display information about how the ring grows and stabilizes as nodes join, and how key-value pairs are added.

## Benchmarking
You can test the performance of the system using larger datasets:
```bash
1> Keys = test:keys(1000).
2> test:add(Keys, Pid1).
3> test:check(Keys, Pid1).
```
This will perform operations on 1000 keys and return lookup statistics.

You can also test the system with multiple clients:
```bash
dht_test:perform_test(2, 4, 1000, 1000).
dht_test:perform_test(4, 4, 1000, 1000).
dht_test:perform_test(4, 4, 10000, 1000).
```

### Failure Handling
Simulate node failures and see how the ring self-heals by keeping track of the next node:
```bash
1> Id1 = 1000, Pid1 = node3:start(Id1).
2> Id2 = 2000, Pid2 = node3:start(Id2, Pid1).
3> Id3 = 3000, Pid3 = node3:start(Id3, Pid1).
4> Pid1 ! {print_state}.
5> Pid2 ! {terminate}.
6> Pid1 ! {print_state}.
7> Pid3 ! {print_state}.
```
### Replication
For fault tolerance, the system supports data replication. Here’s an example where a node stores a key, and it’s replicated in the successor. If the original node fails, the successor takes over.

```bash
1> Id1 = 1000, Pid1 = node4:start(Id1).
2> Id2 = 2000, Pid2 = node4:start(Id2, Pid1).
3> Id3 = 3000, Pid3 = node4:start(Id3, Pid1).
4> Qref = make_ref(), Pid1 ! {add, 12345, "Value1", Qref, self()}.
5> Pid1 ! {terminate}.
6> Pid2 ! {lookup, 12345, Qref2, self()}.
```
## Evaluation
Several test cases were run to evaluate the system’s performance, scalability, and fault tolerance. The tests included:

Manual Testing for basic functionality.
Benchmarks with up to 10,000 key-value pairs.
Failure Handling to ensure data integrity when nodes fail.
Replication to ensure data redundancy in case of node failures.
For a detailed evaluation of the system’s performance and results, refer to the Report.

## Conclusion
This project demonstrates the scalability and reliability of a distributed hash table using the Chord architecture. The system can grow dynamically and handle node failures efficiently through successor tracking and data replication. While the current implementation doesn't include the advanced routing mechanisms of Chord, it provides a robust foundation for future extensions.

