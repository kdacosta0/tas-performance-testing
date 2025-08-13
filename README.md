# TAS Performance Testing

This repository contains a suite of performance testing scripts designed to benchmark a Trusted Artifact Signer (TAS) environment. It uses a custom-built `k6` to simulate various load scenarios, reports metrics in real-time to **Prometheus Pushgateway**, and uses `make` for easy automation and orchestration.

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [How It Works](#how-it-works)
- [Quick Start](#quick-start)
- [Available `make` Commands](#available-make-commands)
- [Running a Mixed-Load Test](#running-a-mixed-load-test)
- [Test Scenarios](#test-scenarios)
- [License](#license)

## Overview

The primary goal of this project is to provide a standardized way to measure the performance and scalability of a TAS deployment. The test suite is designed to benchmark both the **"write" path** (signing artifacts) and the **"read" path** (verifying signatures).

The workflow is orchestrated by a `Makefile` and relies on a custom Go helper application to generate the necessary cryptographic materials on the fly for signing tests. All test results are pushed to a Prometheus Pushgateway instance, allowing for real-time visualization and analysis in Grafana.

## Prerequisites

Before running the tests, ensure you have the following tools installed:

* An OpenShift cluster with a running TAS environment and the deployed Prometheus Pushgateway.
* `oc` (OpenShift CLI) logged into your cluster.
* `go` (version 1.18 or newer).
* `xk6` for building a custom k6 binary.
* `make`.

## How It Works

The testing process is designed to run locally while reporting metrics to a central monitoring stack.

1.  **Custom k6 Build:** The `setup` process automatically builds a custom `k6` binary using `xk6`. This binary includes a special output extension (`xk6-output-prometheus-pushgateway`) required to send metrics to the Pushgateway.

2.  **Metric Collection:** During a test run (`sign` or `verify`), the custom `k6` binary sends detailed performance metrics (VUs, RPS, Latency, Errors) to the Prometheus Pushgateway URL specified in your `.env` file. Prometheus scrapes this Pushgateway, making the data available for visualization in Grafana.

3.  **Signing (`sign` tests):** When a `sign` test is initiated (e.g., `make sign-load`), the `Makefile` first builds and starts the **Go Crypto Helper** service in the background. The k6 script then requests cryptographic materials from this local service for each signing operation.

4.  **Verifying (`verify` tests):** Verification tests rely on a data file (`rekor_uuids_smoke.txt`) containing entry UUIDs. This file **must be generated manually before** running verification tests using the `make generate-verify-data` command. This decouples data generation from test execution, allowing for flexible and concurrent testing.

## Quick Start

1.  **Clone the repository:**
    ```bash
    git clone [https://github.com/kdacosta0/tas-performance-testing.git](https://github.com/kdacosta0/tas-performance-testing.git)
    cd tas-performance-testing
    ```

2.  **Run the Automated Setup:**
    This single command discovers service URLs from your cluster, creates the `.env` file, and builds both the custom `k6` binary and the Go helper application.
    ```bash
    make setup
    ```
    You will be prompted for your OIDC credentials, which will be stored in the `.env` file.

3.  **Run a Signing Test:**
    You are now ready to run any signing test.
    ```bash
    # Run a high-concurrency signing stress test
    make sign-stress
    ```
    *Open your Grafana dashboard to observe the results in real-time.*

4.  **Run a Verification Test:**
    This is a two-step process.
    ```bash
    # Step 1: Generate the test data (only needs to be done once)
    make generate-verify-data

    # Step 2: Run the verification test
    make verify-stress
    ```

## Available `make` Commands

### Setup Commands
* `setup`: (RECOMMENDED) Run all setup tasks: `env`, `build-k6`, `build-helper`.
* `env`: Configure `.env` file from OpenShift cluster.
* `build`: Build all necessary binaries (`k6` and Go helper).
* `build-k6`: Build custom `k6` binary with Pushgateway support.
* `build-helper`: Build the Go crypto helper application.

### Signing Workflows
* `sign-smoke`: Run a single-iteration sign test.
* `sign-load`: Run the sustained sign load test (20 VUs).
* `sign-stress`: Run a high-concurrency sign stress test (ramp-up to 200 VUs).
* `sign-endurance`: Run a long-duration sign endurance test (8 hours).

### Verify Workflows
* `verify-load`: Run a sustained verify load test (50 VUs).
* `verify-stress`: Run a high-concurrency verify stress test (ramp-up to 500 VUs).

### Utilities
* `generate-verify-data`: Force regeneration of the `rekor_uuids_smoke.txt` file needed for verify tests.

### Cleanup
* `clean`: Remove all generated files (binaries, logs, and `.env`).

## Running a Mixed-Load Test

To simulate a realistic workload with both signing and verification happening at the same time, you need to run two tests concurrently in two separate terminals.

1.  **(Run Once) Generate data for verification:**
    ```bash
    make generate-verify-data
    ```

2.  **In Terminal 1, start the verification load:**
    This creates a constant "read" pressure on the system.
    ```bash
    make verify-load
    ```

3.  **While Terminal 1 is running, start the signing stress test in Terminal 2:**
    This adds the "write" pressure.
    ```bash
    make sign-stress
    ```

## Test Scenarios

The `Makefile` provides several pre-configured scenarios based on our findings.

### Signing ("Write") Scenarios
* **Smoke Test:** 1 Virtual User, 1 iteration.
* **Load Test:** Ramps to 20 VUs over 1 minute, holds the load for 5 minutes.
* **Burst Test:** Ramps to 150 VUs over 2 minutes.
* **Stress Test:** Ramps to 200 VUs over 5 minutes.
* **Endurance Test:** Ramps to 15 VUs and sustains the load for 8 hours.

### Verification ("Read") Scenarios
* **Smoke Test:** 1 Virtual User, 1 iteration.
* **Load Test:** Ramps to 50 VUs over 1 minute, holds the load for 5 minutes.
* **Stress Test:** Ramps to 500 VUs over 5 minutes.

## License
This project is licensed under the terms included in the [LICENSE](LICENSE) file.