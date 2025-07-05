# TAS Performance Testing

This repository contains a suite of performance testing scripts designed to benchmark a Trusted Artifact Signer (TAS) environment. It uses `k6` to simulate various load scenarios against TAS components, including Fulcio, Rekor, and a Timestamp Authority (TSA).

## Overview

The primary goal of this project is to provide a standardized and automated way to measure the performance and scalability of a TAS deployment. It includes several predefined test scenarios that simulate different usage patterns, from a simple smoke test to a high-load stress test.

The workflow is orchestrated by a `Makefile` and relies on a custom Go helper application to generate the necessary cryptographic materials on the fly for each virtual user.

## Prerequisites

Before running the tests, ensure you have the following tools installed and configured:

* An OpenShift cluster with a running TAS environment
* `oc` (OpenShift CLI) logged into your cluster
* `k6` for load testing
* `go` (version 1.18 or newer)
* `make`

## How It Works

The testing process is fully automated:

1.  The `make env` command discovers the necessary Fulcio, Rekor, and TSA endpoints from your OpenShift cluster and prompts you for OIDC credentials, creating a `.env` file.
2.  When a test is initiated (e.g., `make test-smoke`), the `Makefile` first builds and starts the **Go Crypto Helper** service in the background.
3.  A k6 test script is then executed. Each virtual user in the k6 test requests unique cryptographic materials (keypair, signature, etc.) from the Go helper.
4.  Using these materials, the k6 script performs a signing workflow against the live TAS endpoints, recording performance metrics.
5.  Once the test is complete, the Go helper is automatically shut down, and results are saved to the `results/` directory.

## Quick Start

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/kdacosta0/tas-performance-testing.git
    cd tas-performance-testing
    ```

2.  **Configure the environment:**
    This command will create a `.env` file by discovering service URLs from your OpenShift cluster and prompting for your OIDC username and password.
    ```bash
    make env
    ```

3.  **Build the helper application:**
    ```bash
    make build
    ```

4.  **Generate artifact payloads:**
    This creates the binary files used for hashing and signing during the tests.
    ```bash
    make payloads
    ```

5.  **Run a test:**
    You can now run any of the predefined test scenarios. For example, to run a simple smoke test:
    ```bash
    make test-smoke
    ```

## Available `make` Commands

* `make env` - Creates the `.env` configuration file from your OpenShift cluster
* `make build` - Compiles the Go helper application
* `make payloads` - Generates small and medium artifact files for testing
* `make test-smoke` - Runs a single-iteration test to verify the setup
* `make test-load` - Runs a sustained load test simulating a medium enterprise
* `make test-burst` - Runs a short, high-traffic burst test
* `make test-stress` - Runs a high-concurrency stress test
* `make clean` - Removes all generated files (binaries, logs, payloads, and `.env`)

## Test Scenarios

* **Smoke Test:** 1 Virtual User, 1 iteration. Used to ensure the entire workflow is functional.
* **Medium Enterprise Load Test:** Ramps up to 20 Virtual Users and sustains the load for 5 minutes.
* **Burst Load Test:** Ramps up to 75 Virtual Users and sustains the load for 2 minutes.
* **Stress Test:** Runs a sustained load of 200 Virtual Users for 5 minutes.

## License

This project is licensed under the terms included in the [LICENSE](LICENSE) file.
