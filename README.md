# Chordy: A Distributed Hash Table

![Chordy Logo](./images/logo.png)

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
