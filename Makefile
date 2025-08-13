# Makefile for TAS Performance Testing

# --- Environment Variables ---
-include .env
export

# --- Variables ---
K6_BIN           := ./k6 
GO_HELPER_BIN    := ./crypto-helper/tas-helper-server

K6_SIGN_SCRIPT   := scripts/tas-perf-sign-template.js
K6_VERIFY_SCRIPT := scripts/tas-perf-verify-template.js

K6_SIGN_JOB_NAME   := signing_test
K6_VERIFY_JOB_NAME := verifying_test
K6_SIGN_ADDRESS    := localhost:6565
K6_VERIFY_ADDRESS  := localhost:6566

# --- Reusable Macro for Running Tests ---
define RUN_SIGN_TEST
    @echo "INFO: Starting Go helper application in the background..."
    @$(GO_HELPER_BIN) &> go-helper.log & \
    HELPER_PID=$$!; \
    trap 'echo "INFO: Cleaning up..."; \
		kill $$HELPER_PID 2>/dev/null; \
		echo "INFO: Deleting metrics for job [$(K6_SIGN_JOB_NAME)] from Pushgateway..."; \
		curl --silent --show-error -k -X DELETE "$(K6_PUSHGATEWAY_URL)/metrics/job/$(K6_SIGN_JOB_NAME)" || true;' \
		EXIT; \
    echo "INFO: Waiting for services to establish..." \
    sleep 4; \
    echo "INFO: Running $(1) with job name [$(K6_SIGN_JOB_NAME)]..."; \
    K6_JOB_NAME="$(K6_SIGN_JOB_NAME)" \
    $(K6_BIN) run \
        --address $(K6_SIGN_ADDRESS) \
        --out output-prometheus-pushgateway \
        $(2)
endef

define RUN_VERIFY_TEST
    @trap 'echo "INFO: Cleaning up..."; \
          echo "INFO: Deleting metrics for job [$(K6_VERIFY_JOB_NAME)] from Pushgateway..."; \
          curl --silent --show-error -k -X DELETE "$(K6_PUSHGATEWAY_URL)/metrics/job/$(K6_VERIFY_JOB_NAME)" || true;' \
          EXIT; \
    echo "INFO: Running $(1) with job name [$(K6_VERIFY_JOB_NAME)]..."; \
    K6_JOB_NAME="$(K6_VERIFY_JOB_NAME)" \
    $(K6_BIN) run \
        --address $(K6_VERIFY_ADDRESS) \
        --out output-prometheus-pushgateway \
        $(2)
endef

# --- All Available Commands ---
.PHONY: help setup env build build-helper clean \
        sign-smoke sign-load sign-stress sign-endurance \
        generate-smoke-data verify-load verify-stress \
        mixed-stress-info


help:
	@echo "Usage: make <target>"
	@echo ""
	@echo "SETUP COMMANDS:"
	@echo "  setup              - (RECOMMENDED) Run all setup tasks: env, build-k6, build-helper"
	@echo "  env                - Configure .env file from OpenShift cluster"
	@echo "  build              - Build all necessary binaries (k6 and Go helper)"
	@echo "  build-k6           - Build custom k6 binary with Pushgateway support"
	@echo "  build-helper       - Build the Go crypto helper application"
	@echo ""
	@echo "SIGNING WORKFLOWS:"
	@echo "  sign-smoke         - Run a single-iteration sign test"
	@echo "  sign-load          - Run the sustained sign load test (20 VUs)"
	@echo "  sign-stress        - Run a high-concurrency sign stress test (ramp-up to 200 VUs)"
	@echo "  sign-endurance     - Run a long-duration sign endurance test (8 hours)"
	@echo ""
	@echo "VERIFY WORKFLOWS:"
	@echo "  verify-load        - Run a sustained verify load test (50 VUs)"
	@echo "  verify-stress.     - Run a high-concurrency verify stress test (ramp-up to 500 VUs)"
	@echo ""
	@echo "CLEANUP:"
	@echo "  clean              - Remove all generated files (binaries, logs, and .env)"


# --- Setup Commands ---
setup: env build

env:
	@chmod +x scripts/utils/configure-env.sh
	@bash scripts/utils/configure-env.sh

build: $(K6_BIN) build-helper
	@echo "Build complete."

$(K6_BIN):
	@echo "Building custom k6 binary with Prometheus Pushgateway extension..."
	@if ! command -v xk6 &> /dev/null; then \
		echo "xk6 not found, installing..."; \
		go install go.k6.io/xk6/cmd/xk6@latest; \
	fi
	@xk6 build --with github.com/martymarron/xk6-output-prometheus-pushgateway@latest

build-helper:
	@echo "Building Go crypto helper application..."
	@cd ./crypto-helper && go build -o tas-helper-server .

# --- Data Generation Targets ---
generate-verify-data: build
	@echo "INFO: Deleting old smoke UUID file..."
	@rm -f rekor_uuids_smoke.txt
	@echo "INFO: Generating new UUIDs from sign-smoke test..."
	@GENERATE_DATA_MODE=true $(MAKE) sign-smoke 2>&1 | grep 'REKOR_ENTRY_UUID' | sed -E 's/.*REKOR_ENTRY_UUID:([0-9a-f]+).*/\1/' > rekor_uuids_smoke.txt
	@echo "INFO: UUID file for verification created: rekor_uuids_smoke.txt"

# --- SIGNING WORKFLOWS ---
sign-smoke: build
	$(call RUN_SIGN_TEST, "sign smoke test", --vus 1 --iterations 1 $(K6_SIGN_SCRIPT))

sign-load: build
	$(call RUN_SIGN_TEST, "sign medium load test", --stage 1m:20 --stage 5m:20 --stage 1m:0 $(K6_SIGN_SCRIPT))

sign-burst: build
	$(call RUN_SIGN_TEST, "sign medium burst test", --stage 2m:150 $(K6_SIGN_SCRIPT))

sign-stress: build
	$(call RUN_SIGN_TEST, "sign stress test", --stage 5m:200 $(K6_SIGN_SCRIPT))

sign-endurance: build
	$(call RUN_SIGN_TEST, "sign endurance test", --stage 1m:15 --stage 6h:15 --stage 2m:0 $(K6_SIGN_SCRIPT))

sign-final-report: build
	$(call RUN_SIGN_TEST, "sign stress test", --stage 3m:300 --stage 5m:300 --stage 2m:0 $(K6_SIGN_SCRIPT))

mixed-sign-final-report: build
	$(call RUN_SIGN_TEST, "sign stress test", --stage 3m:50 --stage 5m:50 --stage 2m:0 $(K6_SIGN_SCRIPT))


# --- VERIFY WORKFLOWS ---
verify-smoke: build
	$(call RUN_VERIFY_TEST, "verify smoke test", --vus 1 --iterations 1 -e REKOR_UUID_FILE='../rekor_uuids_smoke.txt' $(K6_VERIFY_SCRIPT))

verify-load: build
	$(call RUN_VERIFY_TEST, "verify medium load test", --stage 1m:50 --stage 5m:50 --stage 1m:0 -e REKOR_UUID_FILE='../rekor_uuids_smoke.txt' $(K6_VERIFY_SCRIPT))

verify-stress: build
	$(call RUN_VERIFY_TEST, "verify stress test", --stage 5m:500 -e REKOR_UUID_FILE='../rekor_uuids_smoke.txt' $(K6_VERIFY_SCRIPT))

verify-final-report: build
	$(call RUN_VERIFY_TEST, "verify stress test", --stage 3m:800 --stage 5m:800 --stage 2m:0 -e REKOR_UUID_FILE='../rekor_uuids_smoke.txt' $(K6_VERIFY_SCRIPT))

mixed-verify-final-report: build
	$(call RUN_VERIFY_TEST, "verify stress test", --stage 3m:500 --stage 5m:500 --stage 2m:0 -e REKOR_UUID_FILE='../rekor_uuids_smoke.txt' $(K6_VERIFY_SCRIPT))

# --- Cleanup ---
clean:
	@echo "Cleaning up generated files..."
	@rm -f $(K6_BIN) $(GO_HELPER_BIN) go-helper.log .env rekor_uuids_*.txt oc-port-forward.log
	@echo "Cleanup complete."