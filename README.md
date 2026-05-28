# AlphaDuel - Multiplayer Network Architecture

## Overview
This repository documents the backend networking architecture for *AlphaDuel*, an in-development real-time multiplayer Android application. The architecture utilizes a dedicated headless server and a separate client module, validated in local testing environments. The focus of this project is explicitly on the functional network logic, client-server communication, and state synchronization.

## Network Infrastructure & Logic
Building a functional multiplayer environment required engineering robust backend systems capable of handling real-time data transfer. Core implementations include:

* **Headless Dedicated Server:** Engineered a standalone, headless server instance to independently manage game states and authorize client inputs.
* **Real-Time Matchmaking:** Architected the logic using ENet (UDP) to pair distinct clients across the network, establishing secure, active connections for data transfer.
* **Server Telemetry & Validation:** Integrated JSONL telemetry logging to track server events, alongside foundational server-side validation to prevent logic discrepancies and identity collisions (via UUIDs) between connected users.

## Core Technologies
* **Engine:** Godot Engine (4.5.1)
* **Target Architecture:** Android Client / Headless Server
* **Network Paradigms:** ENet (UDP) protocol, state synchronization, JSONL telemetry logging

---

*Note: The core gameplay loop and graphical assets for AlphaDuel are withheld from this repository. The networking scripts highlighted here (e.g., `match.gd`) demonstrate backend systems engineering.*
