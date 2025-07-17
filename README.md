# TAS Performance Testing

This repository contains a suite of performance testing scripts designed to benchmark a Trusted Artifact Signer (TAS) environment. It uses `k6` to simulate various load scenarios and `make` for easy automation.

## Table of Contents
- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [How It Works](#how-it-works)
- [Quick Start](#quick-start)
- [Available `make` Commands](#available-make-commands)
- [Test Scenarios](#test-scenarios)
- [License](#license)

## Overview

The primary goal of this project is to provide a standardized way to measure the performance and scalability of a TAS deployment. The test suite is designed to benchmark both the **"write" path** (signing artifacts) and the **"read" path** (verifying signatures), and a **mixed workload path** that simulates both concurrently.

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

3. **Mixed Workloads (`mixed` tests)**:
    * This workflow simulates a real-world environment where signing and verification happen at the same time.
    * The k6 script executes both signing and verification logic within the same test run to measure performance under a combined load.

**TODO** Pipe the output to a file or another tool for analysis.

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

    # Run a mixed workload test
    make mixed-load
    ```

## Available `make` Commands

### Setup
* `make setup`: Runs `env`, and `build` to prepare the project.
* `make env`: Creates the `.env` file by discovering service URLs from OpenShift.
* `make build`: Compiles the Go helper application.

### Sign Workflows ('Write' Path)
* `make smoke`: Runs a single-iteration `sign` test.
* `make load`: Runs the sustained `sign` load test.
* `make burst`: Runs a high-traffic `sign` burst test.
* `make stress`: Runs a high-concurrency `sign` stress test.
* `make endurance`: Runs a long-duration `sign` endurance test to check for system stability.

### Verify Workflows ('Read' Path)
* `make verify-smoke`: Runs a quick `verify` test using data from the smoke test.
* `make verify-load`: Runs a sustained `verify` load test using data from the load test.

### Mixed Workflows ('Read/Write' Path)
* `make mixed-smoke`: Runs a single-iteration test combining both `sign` and `verify` operations to confirm the mixed workload script is functional.
* `make mixed-load`: Runs a sustained load test with a mixed workload of `sign` and `verify` operations to simulate realistic, concurrent read/write traffic.
* `make mixed-stress`: Runs a high-concurrency stress test with a mixed workload to determine the system's performance boundaries under extreme read/write pressure.

### Cleanup
* `make clean`: Removes all generated files (binaries, logs, results, and `.env`).

## Test Scenarios

### Signing ("Write") Scenarios
* **Smoke Test:** 1 Virtual User, 1 iteration.
* **Load Test:** Ramps to **TBD** VUs and sustains the load for **TBD** minutes.
* **Burst Test:** Ramps to **TBD** VUs and sustains the load for **TBD** minutes.
* **Stress Test:** Ramps to **TBD** VUs over **TBD** minutes.
* **Endurance Test:** Ramps to **TBD** VUs and sustains the load for an extended period (e.g., **TBD** hours) to test system stability over time.

### Verification ("Read") Scenarios
* **Verification Smoke Test:** 1 Virtual User, 10 iterations.
* **Verification Load Test:** Ramps to **TBD** VUs and sustains the load for **TBD** minutes.

### Mixed Workload ("Read/Write") Scenarios
* **Mixed Smoke Test:** 1 Virtual User, 10 iterations, executing a 50/50 split of signing and verification operations.
* **Mixed Load Test:** Ramps to **TBD** VUs, executing a workload of **TBD%** signing and **TBD%** verification operations for **TBD** minutes to simulate realistic traffic.
* **Mixed Stress Test:** Ramps to a high number of VUs (**TBD**) over **TBD** minutes to find the system's breaking point under a combined read/write workload.

## License
This project is licensed under the terms included in the [LICENSE](LICENSE) file.