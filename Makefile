# Makefile for TAS Performance Testing

# --- Variables ---
K6_SIGN_SCRIPT   := scripts/tas-perf-sign-template.js
K6_VERIFY_SCRIPT := scripts/tas-perf-verify-template.js
GO_HELPER_BIN    := ./crypto-helper/tas-helper-server
RESULTS_DIR      := ./results

# --- Environment Variables ---
-include .env
export

# --- All Available Commands ---
.PHONY: help setup env build payloads clean \
        smoke load burst stress \
        verify-smoke verify-load

help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "Setup:"
	@echo "  setup          - Run env, build, and payloads to prepare the project"
	@echo "  env            - Create the .env file by discovering service URLs from OpenShift"
	@echo "  build          - Compile the Go helper application"
	@echo "  payloads       - Generate small and medium artifact files for testing"
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
	@echo "  clean          - Remove all generated files (binaries, logs, payloads, results, and .env)"

# --- Setup Commands ---
setup: env build payloads
	@echo "Project setup complete. You are ready to run tests"

env:
	@chmod +x scripts/utils/configure-env.sh
	@bash scripts/utils/configure-env.sh

build:
	@echo "Building Go helper application..."
	@cd ./crypto-helper && go build -o tas-helper-server .
	@echo "Build complete"

payloads:
	@echo "Generating artifact payloads..."
	@mkdir -p payloads
	@dd if=/dev/urandom of=payloads/artifact-small.bin bs=1K count=10
	@dd if=/dev/urandom of=payloads/artifact-medium.bin bs=1M count=50
	@echo "Payloads generated successfully"


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
		--out json=$(RESULTS_DIR)/results-smoke-$(shell date -u +%Y%m%d-%H%M%S).json \
		--vus 1 --iterations 1 \
		-e PAYLOAD_SIZE="small" \
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
		--out json=$(RESULTS_DIR)/results-load-$(shell date -u +%Y%m%d-%H%M%S).json \
		--stage 1m:20 --stage 5m:20 --stage 1m:0 \
		-e PAYLOAD_SIZE="medium" \
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
		--out json=$(RESULTS_DIR)/results-burst-$(shell date -u +%Y%m%d-%H%M%S).json \
		--stage 30s:75 --stage 2m:75 --stage 30s:0 \
		-e PAYLOAD_SIZE="medium" \
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
		--out json=$(RESULTS_DIR)/results-stress-$(shell date -u +%Y%m%d-%H%M%S).json \
		--stage 5m:200 \
		-e PAYLOAD_SIZE="small" \
		$(K6_SIGN_SCRIPT)

verify-smoke: rekor_uuids_smoke.txt
	@echo "Running verification smoke test..."
	@mkdir -p $(RESULTS_DIR)
	@k6 run \
		--out json=$(RESULTS_DIR)/results-verify-smoke-$(shell date -u +%Y%m%d-%H%M%S).json \
		--vus 1 --iterations 10 \
		-e REKOR_UUID_FILE='../rekor_uuids_smoke.txt' \
		$(K6_VERIFY_SCRIPT)

verify-load: rekor_uuids_load.txt
	@echo "Running verification load test..."
	@mkdir -p $(RESULTS_DIR)
	@k6 run \
		--out json=$(RESULTS_DIR)/results-verify-load-$(shell date -u +%Y%m%d-%H%M%S).json \
		--stage 1m:50 --stage 5m:50 --stage 1m:0 \
		-e REKOR_UUID_FILE='../rekor_uuids_load.txt' \
		$(K6_VERIFY_SCRIPT)

# --- Cleanup ---
clean:
	@echo "Cleaning up generated files..."
	@rm -f $(GO_HELPER_BIN) go-helper.log .env rekor_uuids_*.txt
	@rm -rf payloads results
	@echo "Cleanup complete"
