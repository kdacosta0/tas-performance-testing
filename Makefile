# Makefile for TAS Performance Testing

# --- Variables ---
K6_SIGN_SCRIPT   := scripts/tas-perf-sign-template.js
K6_VERIFY_SCRIPT := scripts/tas-perf-verify-template.js
K6_MIXED_SCRIPT := scripts/tas-perf-sign-verify-template.js
GO_HELPER_BIN    := ./crypto-helper/tas-helper-server
RESULTS_DIR      := ./results

# --- Environment Variables ---
-include .env
export

# --- All Available Commands ---
.PHONY: help setup env build clean \
        smoke load burst stress \
        verify-smoke verify-load

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Setup:"
	@echo "  setup          - Run env, and build to prepare the project"
	@echo "  env            - Create the .env file by discovering service URLs from OpenShift"
	@echo "  build          - Compile the Go helper application"
	@echo ""
	@echo "Sign Workflows:"
	@echo "  smoke          - Run a single-iteration sign test"
	@echo "  load           - Run the sustained sign load test"
	@echo "  burst          - Run a high-traffic sign burst test"
	@echo "  stress         - Run a high-concurrency sign stress test"
	@echo ""
	@echo "Verify Workflows:"
	@echo "  verify-smoke   - Run a quick verify test using data from the smoke test"
	@echo "  verify-load    - Run a sustained verify load test using data from the load test"
	@echo ""
	@echo "Cleanup:"
	@echo "  clean          - Remove all generated files (binaries, logs, results, and .env)"

# --- Setup Commands ---
setup: env build
	@echo "Project setup complete. You are ready to run tests"

env:
	@chmod +x scripts/utils/configure-env.sh
	@bash scripts/utils/configure-env.sh

build:
	@echo "Building Go helper application..."
	@cd ./crypto-helper && go build -o tas-helper-server .
	@echo "Build complete"

# --- Data Generation Targets ---
rekor_uuids_smoke.txt:
	@echo "Generating UUIDs from smoke test..."
	@GENERATE_DATA_MODE=true $(MAKE) smoke 2>&1 | grep 'REKOR_ENTRY_UUID' | sed -E 's/.*REKOR_ENTRY_UUID:([0-9a-f]+).*/\1/' > $@
	@echo "UUID file for smoke verification created"

rekor_uuids_load.txt:
	@echo "WARNING: This will run the full 'load' test to generate a large dataset (~7 minutes)"
	@echo "Starting in 5 seconds... (Press Ctrl+C to cancel)"
	@sleep 5
	@echo "Generating UUIDs from load test..."
	@GENERATE_DATA_MODE=true $(MAKE) load 2>&1 | grep 'REKOR_ENTRY_UUID' | sed -E 's/.*REKOR_ENTRY_UUID:([0-9a-f]+).*/\1/' > $@
	@echo "UUID file for load verification created"


# --- Test Execution Commands ---
smoke: build
	@echo "Starting Go helper application..."
	@mkdir -p $(RESULTS_DIR)
	@$(GO_HELPER_BIN) &> go-helper.log & \
	HELPER_PID=$$!; \
	trap 'kill $$HELPER_PID 2>/dev/null || true' EXIT; \
	sleep 2; \
	echo "Running smoke test..."; \
	k6 run \
		--vus 1 --iterations 1 \
		$(K6_SIGN_SCRIPT)

load: build
	@echo "Starting Go helper application..."
	@mkdir -p $(RESULTS_DIR)
	@$(GO_HELPER_BIN) &> go-helper.log & \
	HELPER_PID=$$!; \
	trap 'kill $$HELPER_PID 2>/dev/null || true' EXIT; \
	sleep 2; \
	echo "Running medium load test..."; \
	k6 run \
		--stage 1m:20 --stage 5m:20 --stage 1m:0 \
		$(K6_SIGN_SCRIPT)

burst: build
	@echo "Starting Go helper application..."
	@mkdir -p $(RESULTS_DIR)
	@$(GO_HELPER_BIN) &> go-helper.log & \
	HELPER_PID=$$!; \
	trap 'kill $$HELPER_PID 2>/dev/null || true' EXIT; \
	sleep 2; \
	echo "Running burst load test..."; \
	k6 run \
		--stage 30s:75 --stage 2m:75 --stage 30s:0 \
		$(K6_SIGN_SCRIPT)

stress: build
	@echo "Starting Go helper application..."
	@mkdir -p $(RESULTS_DIR)
	@$(GO_HELPER_BIN) &> go-helper.log & \
	HELPER_PID=$$!; \
	trap 'kill $$HELPER_PID 2>/dev/null || true' EXIT; \
	sleep 2; \
	echo "Running stress test..."; \
	k6 run \
		--stage 5m:200 \
		$(K6_SIGN_SCRIPT)

endurance: build
	@echo "Starting Go helper application..."
	@mkdir -p $(RESULTS_DIR)
	@$(GO_HELPER_BIN) &> go-helper.log & \
	HELPER_PID=$$!; \
	trap 'kill $$HELPER_PID 2>/dev/null || true' EXIT; \
	sleep 2; \
	echo "Running endurance test (8 hours at 15 VUs)..."; \
	k6 run \
		--stage 1m:15 --stage 8h:15 --stage 2m:0 \
		$(K6_SIGN_SCRIPT)

verify-smoke: rekor_uuids_smoke.txt
	@echo "Running verification smoke test..."
	@mkdir -p $(RESULTS_DIR)
	@k6 run \
		--vus 1 --iterations 10 \
		-e REKOR_UUID_FILE='../rekor_uuids_smoke.txt' \
		$(K6_VERIFY_SCRIPT)

verify-load: rekor_uuids_load.txt
	@echo "Running verification load test..."
	@mkdir -p $(RESULTS_DIR)
	@k6 run \
		--stage 1m:50 --stage 5m:50 --stage 1m:0 \
		-e REKOR_UUID_FILE='../rekor_uuids_load.txt' \
		$(K6_VERIFY_SCRIPT)

mixed-smoke: build
	@echo "Starting Go helper application..."
	@mkdir -p $(RESULTS_DIR)
	@$(GO_HELPER_BIN) &> go-helper.log & \
	HELPER_PID=$$!; \
	trap 'kill $$HELPER_PID 2>/dev/null || true' EXIT; \
	sleep 2; \
	echo "Running mixed SMOKE test (1 signer, 1 verifier for 10s)..."; \
	k6 run \
		-e SIGN_VUS=1 \
		-e VERIFY_VUS=1 \
		-e TEST_DURATION=10s \
		$(K6_MIXED_SCRIPT)

mixed-load: build
	@echo "Starting Go helper application..."
	@mkdir -p $(RESULTS_DIR)
	@$(GO_HELPER_BIN) &> go-helper.log & \
	HELPER_PID=$$!; \
	trap 'kill $$HELPER_PID 2>/dev/null || true' EXIT; \
	sleep 2; \
	echo "Running mixed workload test (10 signers, 40 verifiers for 10m)..."; \
	k6 run \
		$(K6_MIXED_SCRIPT)

mixed-stress: build
	@echo "Starting Go helper application..."
	@mkdir -p $(RESULTS_DIR)
	@$(GO_HELPER_BIN) &> go-helper.log & \
	HELPER_PID=$$!; \
	trap 'kill $$HELPER_PID 2>/dev/null || true' EXIT; \
	sleep 2; \
	echo "Running mixed STRESS test (50 signers, 200 verifiers for 5m)..."; \
	k6 run \
		-e SIGN_VUS=50 \
		-e VERIFY_VUS=200 \
		-e TEST_DURATION=5m \
		$(K6_MIXED_SCRIPT)

# --- Cleanup ---
clean:
	@echo "Cleaning up generated files..."
	@rm -f $(GO_HELPER_BIN) go-helper.log .env rekor_uuids_*.txt
	@rm -rf results
	@echo "Cleanup complete"
