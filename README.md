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

##Benchmarking
You can test the performance of the system using larger datasets:
