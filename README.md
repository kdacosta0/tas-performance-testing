# TAS Performance Testing

This repository contains a suite of performance testing scripts designed to benchmark a Trusted Artifact Signer (TAS) environment. It uses `k6` to simulate various load scenarios and `make` for easy automation.

## Overview

The primary goal of this project is to provide a standardized way to measure the performance and scalability of a TAS deployment. The test suite is designed to benchmark both the **"write" path** (signing artifacts) and the **"read" path** (verifying signatures).

The workflow is orchestrated by a `Makefile` and relies on a custom Go helper application to generate the necessary cryptographic materials on the fly for signing tests.

## Prerequisites

Before running the tests, ensure you have the following tools installed:

* An OpenShift cluster with a running TAS environment
* `oc` (OpenShift CLI) logged into your cluster
* `k6` for load testing
* `go` (version 1.18 or newer)
* `make`

## How It Works

The testing process is fully automated and handles two primary workflows:

1.  **Signing (`sign` tests):**
    * When a `sign` test is initiated (e.g., `make smoke`), the `Makefile` first builds and starts the **Go Crypto Helper** service in the background.
    * The k6 test script then executes. Each virtual user requests unique cryptographic materials from the Go helper.
    * Using these materials, the k6 script performs a signing workflow against the live TAS endpoints, outputting Rekor UUIDs for each successful entry.

2.  **Verifying (`verify` tests):**
    * When a `verify` test is initiated (e.g., `make verify-smoke`), the `Makefile` first checks if a list of test data (`rekor_uuids_*.txt`) exists.
    * If the data file does not exist, it **automatically runs the corresponding signing test** to generate it.
    * It then runs the k6 verification script, which queries the Rekor and TSA endpoints using the generated data to simulate a realistic read-heavy workload.

Once any test is complete, detailed results are saved as JSON files in the `results/` directory.

## Quick Start

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/kdacosta0/tas-performance-testing.git
    cd tas-performance-testing
    ```

2.  **Run the Automated Setup:**
    This single command discovers service URLs from your cluster, creates the `.env` file, compiles the Go helper, and generates binary artifact files.
    ```bash
    make setup
    ```

3.  **Run a Test:**
    You are now ready to run any test. For example:
    ```bash
    # Run a signing smoke test
    make smoke

    # Run a verification smoke test (will auto-generate data if needed)
    make verify-smoke
    ```

## Available `make` Commands

### Setup
* `make setup`: Runs `env`, `build`, and `payloads` to prepare the project.
* `make env`: Creates the `.env` file by discovering service URLs from OpenShift.
* `make build`: Compiles the Go helper application.
* `make payloads`: Generates small and medium artifact files for testing.

### Sign Workflows ('Write' Path)
* `make smoke`: Runs a single-iteration `sign` test.
* `make load`: Runs the sustained `sign` load test (Medium Enterprise).
* `make burst`: Runs a high-traffic `sign` burst test.
* `make stress`: Runs a high-concurrency `sign` stress test.

### Verify Workflows ('Read' Path)
* `make verify-smoke`: Runs a quick `verify` test using data from the smoke test.
* `make verify-load`: Runs a sustained `verify` load test using data from the load test.

### Cleanup
* `make clean`: Removes all generated files (binaries, logs, payloads, results, and `.env`).

## Test Scenarios

### Signing ("Write") Scenarios
* **Smoke Test:** 1 Virtual User, 1 iteration.
* **Load Test:** Ramps to **TBD** VUs and sustains the load for **TBD** minutes.
* **Burst Test:** Ramps to **TBD** VUs and sustains the load for **TBD** minutes.
* **Stress Test:** Ramps to **TBD** VUs over **TBD** minutes.

### Verification ("Read") Scenarios
* **Verification Smoke Test:** 1 Virtual User, 10 iterations.
* **Verification Load Test:** Ramps to **TBD** VUs and sustains the load for **TBD** minutes.

## License

This project is licensed under the terms included in the [LICENSE](LICENSE) file.