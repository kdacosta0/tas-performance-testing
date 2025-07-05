# Makefile for TAS Performance Testing

# Defines file paths and directories.
K6_SIGN_SCRIPT := scripts/tas-perf-sign-template.js
GO_HELPER_DIR  := ./crypto-helper
GO_HELPER_BIN  := $(GO_HELPER_DIR)/tas-helper-server
RESULTS_DIR    := ./results

# Includes and exports environment variables from the .env file.
-include .env
export

.PHONY: help all payloads build env test-smoke test-load test-medium-enterprise test-burst test-stress clean

# --- Main Targets ---

help:
	@echo "TAS Performance Test Makefile"
	@echo "-------------------------------"
	@echo "See the .env file for required environment variables"
	@echo ""
	@echo "Available commands:"
	@echo "  make env         - Create the .env configuration file from the template"
	@echo "  make build       - Compile the Go helper application"
	@echo "  make payloads    - Generates small and medium artifact files for testing"
	@echo "  make test-smoke  - Runs a single-iteration test to verify the setup"
	@echo "  make test-load   - Runs a sustained load test simulating a medium enterprise"
	@echo "  make test-burst  - Runs a short, high-traffic burst test"
	@echo "  make test-stress - Runs a high-concurrency stress test"
	@echo "  make clean       - Removes all generated files (binaries, logs, payloads, and .env)"

env:
	@chmod +x scripts/utils/configure-env.sh
	@bash scripts/utils/configure-env.sh

build:
	@echo "Building Go helper application..."
	@cd $(GO_HELPER_DIR) && go build -o $(notdir $(GO_HELPER_BIN)) .
	@echo "Build complete"

payloads:
	@echo "Generating artifact payloads..."
	@mkdir -p payloads
	@dd if=/dev/urandom of=payloads/artifact-small.bin bs=1K count=10
	@dd if=/dev/urandom of=payloads/artifact-medium.bin bs=1M count=50
	@echo "Payloads generated successfully"

# --- Test Scenarios ---

test-smoke: build
	@echo "Starting Go helper application in the background..."
	@mkdir -p $(RESULTS_DIR)
	@$(GO_HELPER_BIN) &> go-helper.log & \
	HELPER_PID=$$!; \
	trap 'echo "Stopping Go helper (PID: $$HELPER_PID)..."; kill $$HELPER_PID 2>/dev/null || true' EXIT; \
	echo "Waiting for Go helper to initialize (PID: $$HELPER_PID)..."; \
	sleep 2; \
	echo "Running smoke test..."; \
	k6 run \
		--out json=$(RESULTS_DIR)/results-smoke-$(shell date -u +%Y%m%d-%H%M%S).json \
		--vus 1 --iterations 1 \
		-e PAYLOAD_SIZE="small" \
		$(K6_SIGN_SCRIPT);
	@echo "Test complete. Results are available in the $(RESULTS_DIR)/ directory"

test-load: test-medium-enterprise

test-medium-enterprise: build
	@echo "Starting Go helper application in the background..."
	@mkdir -p $(RESULTS_DIR)
	@$(GO_HELPER_BIN) &> go-helper.log & \
	HELPER_PID=$$!; \
	trap 'echo "Stopping Go helper (PID: $$HELPER_PID)..."; kill $$HELPER_PID 2>/dev/null || true' EXIT; \
	echo "Waiting for Go helper to initialize (PID: $$HELPER_PID)..."; \
	sleep 2; \
	echo "Running medium enterprise load test..."; \
	k6 run \
		--out json=$(RESULTS_DIR)/results-medium-$(shell date -u +%Y%m%d-%H%M%S).json \
		--stage 1m:20 \
		--stage 5m:20 \
		--stage 1m:0 \
		-e PAYLOAD_SIZE="medium" \
		$(K6_SIGN_SCRIPT);
	@echo "Test complete. Results are available in the $(RESULTS_DIR)/ directory"

test-burst: build
	@echo "Starting Go helper application in the background..."
	@mkdir -p $(RESULTS_DIR)
	@$(GO_HELPER_BIN) &> go-helper.log & \
	HELPER_PID=$$!; \
	trap 'echo "Stopping Go helper (PID: $$HELPER_PID)..."; kill $$HELPER_PID 2>/dev/null || true' EXIT; \
	echo "Waiting for Go helper to initialize (PID: $$HELPER_PID)..."; \
	sleep 2; \
	echo "Running burst load test..."; \
	k6 run \
		--out json=$(RESULTS_DIR)/results-burst-$(shell date -u +%Y%m%d-%H%M%S).json \
		--stage 30s:75 \
		--stage 2m:75 \
		--stage 30s:0 \
		-e PAYLOAD_SIZE="medium" \
		$(K6_SIGN_SCRIPT);
	@echo "Test complete. Results are available in the $(RESULTS_DIR)/ directory"

test-stress: build
	@echo "Starting Go helper application in the background..."
	@mkdir -p $(RESULTS_DIR)
	@$(GO_HELPER_BIN) &> go-helper.log & \
	HELPER_PID=$$!; \
	trap 'echo "Stopping Go helper (PID: $$HELPER_PID)..."; kill $$HELPER_PID 2>/dev/null || true' EXIT; \
	echo "Waiting for Go helper to initialize (PID: $$HELPER_PID)..."; \
	sleep 2; \
	echo "Running stress test..."; \
	k6 run \
		--out json=$(RESULTS_DIR)/results-stress-$(shell date -u +%Y%m%d-%H%M%S).json \
		--stage 5m:200 \
		-e PAYLOAD_SIZE="small" \
		$(K6_SIGN_SCRIPT);
	@echo "Test complete. Results are available in the $(RESULTS_DIR)/ directory"

clean:
	@echo "Cleaning up generated files..."
	@rm -f $(GO_HELPER_BIN) go-helper.log .env
	@rm -rf payloads results
	@echo "Cleanup complete"
