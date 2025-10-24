SHELL := /bin/bash
.ONESHELL:

# Quiet by default; use `make V=1 <target>` for verbose
ifeq ($(V),1)
# verbose mode
else
MAKEFLAGS += -s --no-print-directory
endif

# Configuration
FOUNDRY ?= $(HOME)/.foundry/bin
FORGE ?= $(FOUNDRY)/forge
CAST  ?= $(FOUNDRY)/cast
ANVIL ?= $(FOUNDRY)/anvil
RPC_URL ?= http://127.0.0.1:7545
HOST ?= 127.0.0.1
PORT ?= 7545
ENV_FILE ?= .env
MODEL_HASH ?= init-hash
ROUNDS ?= 1

.PHONY: anvil-start anvil-stop build test test-sol test-py abi deploy-agg deploy-peers fund-accounts mint-round end demo reset status peer-round peer-rounds agg-round agg-rounds verify-agg-hash verify-peer-hash clean-logs clean-artifacts

anvil-start:
	if lsof -i:$(PORT) >/dev/null 2>&1; then
		echo "Port $(PORT) already in use"
	else
		mkdir -p logs
		nohup "$(ANVIL)" --port $(PORT) --host $(HOST) > logs/anvil.log 2>&1 & echo $$! > .anvil.pid
		echo "Started anvil (pid $$(cat .anvil.pid)) on $(HOST):$(PORT) (log: logs/anvil.log)"
	fi
	for i in {1..50}; do
		if "$(CAST)" block-number --rpc-url $(RPC_URL) >/dev/null 2>&1; then
			echo "Anvil is responding on $(RPC_URL)"
			break
		fi
		sleep 0.1
	done

anvil-stop:
	if [ -f .anvil.pid ]; then
		kill $$(cat .anvil.pid) || true
		rm -f .anvil.pid
		echo "Stopped anvil"
	else
		echo "No .anvil.pid found"
	fi

build:
	"$(FORGE)" build

test:
	"$(FORGE)" test -vv

test-sol: ## Run Solidity (Foundry) tests
	"$(FORGE)" test -vv

test-py: ## Run Python tests with pytest
	set -euo pipefail
	PY=.venv/bin/python; if [ ! -x "$$PY" ]; then PY=python3; fi
	PYTHONPATH=src "$$PY" -m pytest -q tests/python

abi:
	"$(FORGE)" inspect src/smart_contracts/FedAggregator.sol:FedAggregatorNFT abi --json > src/abi/Aggregator_ABI.json
	"$(FORGE)" inspect src/smart_contracts/FedPeer.sol:FedPeerNFT abi --json > src/abi/Client_ABI.json
	@echo "ABI updated in src/abi/"

deploy-agg: ## Deploy aggregator and update .env
	set -euo pipefail
	AGG_PK=$$(grep -E '^AGGREGATOR_PRIVATE_KEY=' $(ENV_FILE) | sed 's/AGGREGATOR_PRIVATE_KEY=//')
	if [ -z "$$AGG_PK" ]; then echo "AGGREGATOR_PRIVATE_KEY not found in $(ENV_FILE)" >&2; exit 1; fi
	mkdir -p logs
	export PRIVATE_KEY="$$AGG_PK" MODEL_HASH="$(MODEL_HASH)"
	"$(FORGE)" script script/DeployAggregator.s.sol:DeployAggregator --rpc-url $(RPC_URL) --broadcast --private-key "$$PRIVATE_KEY" -vv | tee logs/deploy_agg.log >/dev/null
	ADDR=$$(sed -n 's/.*FedAggregatorNFT deployed at: \(0x[0-9a-fA-F]\+\).*/\1/p' logs/deploy_agg.log | tail -n1)
	if [ -z "$$ADDR" ]; then echo "Unable to determine aggregator address" >&2; exit 1; fi
	cp $(ENV_FILE) $(ENV_FILE).bak || true
	awk -v new="$$ADDR" 'BEGIN{updated=0} /^AGGREGATOR_CONTRACT_ADDRESS=/{print "AGGREGATOR_CONTRACT_ADDRESS=" new; updated=1; next} {print} END{if(!updated) print "AGGREGATOR_CONTRACT_ADDRESS=" new}' $(ENV_FILE) > $(ENV_FILE).tmp && mv $(ENV_FILE).tmp $(ENV_FILE)
	@echo "Aggregator deployed at: $$ADDR (env backup at $(ENV_FILE).bak)"

fund-accounts: ## Fund aggregator and peer EOAs on anvil
	set -euo pipefail
	AGG_PK=$$(grep -E '^AGGREGATOR_PRIVATE_KEY=' $(ENV_FILE) | sed 's/AGGREGATOR_PRIVATE_KEY=//')
	AGG_EOA=$$("$(CAST)" wallet address --private-key "$$AGG_PK")
	"$(CAST)" rpc anvil_setBalance "$$AGG_EOA" 0x56BC75E2D63100000 --rpc-url $(RPC_URL) >/dev/null || true
	IFS=',' read -r -a PKS <<< "$$(grep -E '^CLIENT_PRIVATE_KEYS=' $(ENV_FILE) | sed 's/CLIENT_PRIVATE_KEYS=//')"
	for pk in "$${PKS[@]}"; do
		addr=$$("$(CAST)" wallet address --private-key "$$pk")
		"$(CAST)" rpc anvil_setBalance "$$addr" 0x56BC75E2D63100000 --rpc-url $(RPC_URL) >/dev/null || true
	done
	@echo "Balances funded"

deploy-peers: ## Deploy peer contracts for each CLIENT_PRIVATE_KEYS and update .env
	set -euo pipefail
	AGG_PK=$$(grep -E '^AGGREGATOR_PRIVATE_KEY=' $(ENV_FILE) | sed 's/AGGREGATOR_PRIVATE_KEY=//')
	AGG_ADDR=$$(grep -E '^AGGREGATOR_CONTRACT_ADDRESS=' $(ENV_FILE) | sed 's/AGGREGATOR_CONTRACT_ADDRESS=//')
	if [ -z "$$AGG_PK" ] || [ -z "$$AGG_ADDR" ]; then echo "Missing aggregator key or address in $(ENV_FILE)" >&2; exit 1; fi
	IFS=',' read -r -a PKS <<< "$$(grep -E '^CLIENT_PRIVATE_KEYS=' $(ENV_FILE) | sed 's/CLIENT_PRIVATE_KEYS=//')"
	CSV=""
	idx=0
	for pk in "$${PKS[@]}"; do
		peer_eoa=$$("$(CAST)" wallet address --private-key "$$pk")
		export PRIVATE_KEY="$$AGG_PK" PEER_ADDRESS="$$peer_eoa" AGGREGATOR_ADDRESS="$$AGG_ADDR"
		mkdir -p logs
		"$(FORGE)" script script/DeployPeer.s.sol:DeployPeer --rpc-url $(RPC_URL) --broadcast --private-key "$$PRIVATE_KEY" -vv | tee logs/deploy_peer_$$idx.log >/dev/null
		addr=$$(sed -n 's/.*FedPeerNFT deployed at: \(0x[0-9a-fA-F]\+\).*/\1/p' logs/deploy_peer_$$idx.log | tail -n1)
		if [ -z "$$addr" ]; then echo "Unable to determine peer $$idx address" >&2; exit 1; fi
		if [ -z "$$CSV" ]; then CSV="$$addr"; else CSV="$$CSV,$$addr"; fi
		idx=$$((idx+1))
		sleep 0.1
	done
	cp $(ENV_FILE) $(ENV_FILE).bak_peers || true
	awk -v new="$$CSV" 'BEGIN{updated=0} /^CLIENT_CONTRACT_ADDRESSES=/{print "CLIENT_CONTRACT_ADDRESSES=" new; updated=1; next} {print} END{if(!updated) print "CLIENT_CONTRACT_ADDRESSES=" new}' $(ENV_FILE) > $(ENV_FILE).tmp && mv $(ENV_FILE).tmp $(ENV_FILE)
	@echo "Peer contracts: $$CSV (env backup at $(ENV_FILE).bak_peers)"


mint-round: ## Mint aggregator round (MODEL_WEIGHTS_HASH and ROUND_INFO required)
	set -euo pipefail
	if [ -z "$(MODEL_WEIGHTS_HASH)" ]; then echo "MODEL_WEIGHTS_HASH not set. Use: make mint-round MODEL_WEIGHTS_HASH=... ROUND_INFO='{}'" >&2; exit 1; fi
	if [ -z "$(ROUND_INFO)" ]; then echo "ROUND_INFO not set. Use: make mint-round MODEL_WEIGHTS_HASH=... ROUND_INFO='{}'" >&2; exit 1; fi
	AGG_PK=$$(grep -E '^AGGREGATOR_PRIVATE_KEY=' $(ENV_FILE) | sed 's/AGGREGATOR_PRIVATE_KEY=//')
	AGG_ADDR=$$(grep -E '^AGGREGATOR_CONTRACT_ADDRESS=' $(ENV_FILE) | sed 's/AGGREGATOR_CONTRACT_ADDRESS=//')
	export PRIVATE_KEY="$$AGG_PK" AGGREGATOR_ADDRESS="$$AGG_ADDR" MODEL_WEIGHTS_HASH="$(MODEL_WEIGHTS_HASH)" ROUND_INFO="$(ROUND_INFO)"
	"$(FORGE)" script script/MintAggregatorRound.s.sol:MintAggregatorRound --rpc-url $(RPC_URL) --broadcast --private-key "$$PRIVATE_KEY" -vv

end: ## End the federation
	set -euo pipefail
	AGG_PK=$$(grep -E '^AGGREGATOR_PRIVATE_KEY=' $(ENV_FILE) | sed 's/AGGREGATOR_PRIVATE_KEY=//')
	AGG_ADDR=$$(grep -E '^AGGREGATOR_CONTRACT_ADDRESS=' $(ENV_FILE) | sed 's/AGGREGATOR_CONTRACT_ADDRESS=//')
	export PRIVATE_KEY="$$AGG_PK" AGGREGATOR_ADDRESS="$$AGG_ADDR"
	"$(FORGE)" script script/EndFederation.s.sol:EndFederation --rpc-url $(RPC_URL) --broadcast --private-key "$$PRIVATE_KEY" -vv

demo: ## Run the Python demo
	set -euo pipefail
	PY=.venv/bin/python; if [ ! -x "$$PY" ]; then PY=python3; fi
	ROUNDS=$(ROUNDS) "$$PY" examples/run_demo.py

reset: ## Full reset: clean, restart anvil, redeploy agg+peers, fund, regenerate ABI
	set -euo pipefail
	$(MAKE) anvil-stop || true
	rm -rf broadcast logs .anvil.pid out cache || true
	$(MAKE) anvil-start
	$(MAKE) build abi
	$(MAKE) fund-accounts
	$(MAKE) deploy-agg MODEL_HASH=$(MODEL_HASH)
	$(MAKE) deploy-peers
	@echo "Reset complete. Aggregator: $$(grep -E '^AGGREGATOR_CONTRACT_ADDRESS=' $(ENV_FILE) | sed 's/AGGREGATOR_CONTRACT_ADDRESS=//')"

clean-logs: ## Remove logs directory
	rm -rf logs || true

clean-artifacts: ## Remove Foundry artifacts and broadcasts
	rm -rf out cache broadcast || true

status: ## Show status of anvil, RPC and contracts (aggregator + peers)
	set -euo pipefail
	@echo "== Config =="
	@echo "HOST=$(HOST) PORT=$(PORT) RPC_URL=$(RPC_URL) ENV=$(ENV_FILE)"
	@echo "== Anvil =="
	@if lsof -i:$(PORT) >/dev/null 2>&1; then \
		echo "Anvil running on $(HOST):$(PORT)"; \
	else \
		echo "Anvil NOT running on $(HOST):$(PORT)"; \
	fi
	@echo "== RPC =="
	@if "$(CAST)" --version >/dev/null 2>&1; then \
		if "$(CAST)" block-number --rpc-url $(RPC_URL) >/dev/null 2>&1; then \
			BN=$$($(CAST) block-number --rpc-url $(RPC_URL)); echo "RPC reachable. block-number=$$BN"; \
		else \
			echo "RPC NOT reachable at $(RPC_URL)"; \
		fi; \
	else \
		echo "cast not found at $(CAST). Check Foundry installation."; \
	fi
	@echo "== Aggregator/Peers =="
	@AGG_PK=$$(grep -E '^AGGREGATOR_PRIVATE_KEY=' $(ENV_FILE) | sed 's/AGGREGATOR_PRIVATE_KEY=//'); \
	AGG_EOA=""; \
	if [ -n "$$AGG_PK" ] && [ "$$AGG_PK" != "" ]; then \
		AGG_EOA=$$($(CAST) wallet address --private-key "$$AGG_PK" 2>/dev/null || true); \
		echo "Aggregator EOA: $$AGG_EOA"; \
	else \
		echo "AGGREGATOR_PRIVATE_KEY not found in $(ENV_FILE)"; \
	fi; \
	AGG_ADDR=$$(grep -E '^AGGREGATOR_CONTRACT_ADDRESS=' $(ENV_FILE) | sed 's/AGGREGATOR_CONTRACT_ADDRESS=//'); \
	if [ -n "$$AGG_ADDR" ] && [ "$$AGG_ADDR" != "" ]; then \
		echo "Aggregator contract: $$AGG_ADDR"; \
		MODEL_HASH=$$($(CAST) call "$$AGG_ADDR" "modelHash()(string)" --rpc-url $(RPC_URL) 2>/dev/null || true); \
		CURR=$$($(CAST) call "$$AGG_ADDR" "currentRound()(uint256)" --rpc-url $(RPC_URL) 2>/dev/null || true); \
		FSTAT=$$($(CAST) call "$$AGG_ADDR" "federatedStatus()(uint8)" --rpc-url $(RPC_URL) 2>/dev/null || true); \
		MWH=$$($(CAST) call "$$AGG_ADDR" "modelWeightHash()(string)" --rpc-url $(RPC_URL) 2>/dev/null || true); \
		AGG_OWNER=$$($(CAST) call "$$AGG_ADDR" "owner()(address)" --rpc-url $(RPC_URL) 2>/dev/null || true); \
		[ -n "$$CURR" ] && echo "Current round: $$CURR"; \
		[ -n "$$FSTAT" ] && echo "Federated status: $$FSTAT (0=in-progress, 1=ended)"; \
		[ -n "$$AGG_OWNER" ] && echo "Owner: $$AGG_OWNER"; \
		[ -n "$$MODEL_HASH" ] && echo "Initial model hash: $$MODEL_HASH"; \
		[ -n "$$MWH" ] && echo "Latest weights hash: $$MWH"; \
	else \
		echo "AGGREGATOR_CONTRACT_ADDRESS not found in $(ENV_FILE)"; \
	fi; \
	PEERS=$$(grep -E '^CLIENT_CONTRACT_ADDRESSES=' $(ENV_FILE) | sed 's/CLIENT_CONTRACT_ADDRESSES=//'); \
	if [ -n "$$PEERS" ] && [ "$$PEERS" != "" ]; then \
		IFS=',' read -r -a ADDRS <<< "$$PEERS"; \
		N=$${#ADDRS[@]}; echo "Peer contracts: $$N"; \
		idx=0; \
		for addr in "$${ADDRS[@]}"; do \
			PSTAT=$$($(CAST) call "$$addr" "peerStatus()(uint8)" --rpc-url $(RPC_URL) 2>/dev/null || true); \
			LAST=$$($(CAST) call "$$addr" "lastParticipatedRound()(uint256)" --rpc-url $(RPC_URL) 2>/dev/null || true); \
			PEO=$$($(CAST) call "$$addr" "peerAddress()(address)" --rpc-url $(RPC_URL) 2>/dev/null || true); \
			echo " - peer[$$idx] $$addr | status=$$PSTAT lastRound=$$LAST owner=$$PEO"; \
			idx=$$((idx+1)); \
		done; \
	else \
			echo "CLIENT_CONTRACT_ADDRESSES not found in $(ENV_FILE)"; \
	fi

verify-agg-hash: ## Verify local weights hash against aggregator on-chain hash (ROUND_NUMBER, WEIGHTS[, KEYS_ORDER, AGG_ADDR])
	set -euo pipefail
	if [ -z "$(ROUND_NUMBER)" ]; then echo "Provide ROUND_NUMBER=<n>" >&2; exit 1; fi
	if [ -z "$(WEIGHTS)" ]; then echo "Provide WEIGHTS=</path/to/file> (.npy/.npz/.h5/.keras)" >&2; exit 1; fi
	ADDR="$${AGG_ADDR:-}"; if [ -z "$$ADDR" ]; then ADDR=$$(grep -E '^AGGREGATOR_CONTRACT_ADDRESS=' $(ENV_FILE) | sed 's/AGGREGATOR_CONTRACT_ADDRESS=//'); fi
	if [ -z "$$ADDR" ]; then echo "Set AGG_ADDR=0x... or define AGGREGATOR_CONTRACT_ADDRESS in $(ENV_FILE)" >&2; exit 1; fi
	W=$$("$(CAST)" call "$$ADDR" "getRoundWeight(uint256)(string)" "$(ROUND_NUMBER)" --rpc-url $(RPC_URL) 2>/dev/null || true)
	if [ -z "$$W" ]; then W=$$("$(CAST)" call "$$ADDR" "getRoundHash(uint256)(string)" "$(ROUND_NUMBER)" --rpc-url $(RPC_URL) 2>/dev/null || true); fi
	PY=.venv/bin/python; if [ ! -x "$$PY" ]; then PY=python3; fi
	ORDER_ARG=""; if [ -n "$${KEYS_ORDER:-}" ]; then ORDER_ARG="--keys-order \"$${KEYS_ORDER}\""; fi
	LH=$$(eval "\"$$PY\" tools/weights_hash.py --file \"$(WEIGHTS)\" $$ORDER_ARG")
	WL=$$(echo "$$W" | sed -e 's/^"//' -e 's/"$$//' | tr 'A-Z' 'a-z')
	@echo "aggregator=$$ADDR round=$(ROUND_NUMBER)"
	@echo "on_chain=$$WL"
	@echo "local   =$$LH"
	if [ -z "$$WL" ]; then echo "On-chain hash is empty" >&2; exit 1; fi
	if [ "$$WL" = "$$LH" ]; then echo "MATCH ✓"; else echo "MISMATCH ✗" >&2; exit 1; fi

verify-peer-hash: ## Verify local weights hash against peer payload weight_hash (PEER_ADDR or PEER_INDEX, ROUND_NUMBER, WEIGHTS[, KEYS_ORDER])
	set -euo pipefail
	if [ -z "$(ROUND_NUMBER)" ]; then echo "Provide ROUND_NUMBER=<n>" >&2; exit 1; fi
	if [ -z "$(WEIGHTS)" ]; then echo "Provide WEIGHTS=</path/to/file> (.npy/.npz/.h5/.keras)" >&2; exit 1; fi
	ADDR="$${PEER_ADDR:-}"; \
	if [ -z "$$ADDR" ]; then \
		IDX="$${PEER_INDEX:-}"; \
		if [ -z "$$IDX" ]; then echo "Provide PEER_ADDR=0x... or PEER_INDEX=<idx>" >&2; exit 1; fi; \
		PEERS_CSV=$$(grep -E '^CLIENT_CONTRACT_ADDRESSES=' $(ENV_FILE) | sed 's/CLIENT_CONTRACT_ADDRESSES=//'); \
		IFS=',' read -r -a ADDRS <<< "$$PEERS_CSV"; \
		if [ -z "$$IDX" ] || [ "$$IDX" -lt 0 ] || [ "$$IDX" -ge "$$(( $${#ADDRS[@]} ))" ]; then echo "Invalid PEER_INDEX ($$IDX)" >&2; exit 1; fi; \
		ADDR="$${ADDRS[$$IDX]}"; \
	fi
	PAYLOAD=$$("$(CAST)" call "$$ADDR" "roundDetails(uint256)(string)" "$(ROUND_NUMBER)" --rpc-url $(RPC_URL) 2>/dev/null || true)
	PY=.venv/bin/python; if [ ! -x "$$PY" ]; then PY=python3; fi
	PH=$$(printf '%s' "$$PAYLOAD" | "$$PY" tools/extract_weight_hash.py)
	ORDER_ARG=""; if [ -n "$${KEYS_ORDER:-}" ]; then ORDER_ARG="--keys-order \"$${KEYS_ORDER}\""; fi
	LH=$$(eval "\"$$PY\" tools/weights_hash.py --file \"$(WEIGHTS)\" $$ORDER_ARG")
	@echo "peer=$$ADDR round=$(ROUND_NUMBER)"
	@echo "on_chain=$$PH"
	@echo "local   =$$LH"
	if [ -z "$$PH" ]; then echo "On-chain payload missing or no weight_hash field" >&2; exit 1; fi
	if [ "$$PH" = "$$LH" ]; then echo "MATCH ✓"; else echo "MISMATCH ✗" >&2; exit 1; fi

agg-round: ## Show aggregator global round details (ROUND_NUMBER=n, optional AGG_ADDR=0x..)
	set -euo pipefail
	ADDR="$${AGG_ADDR:-}"; if [ -z "$$ADDR" ]; then ADDR=$$(grep -E '^AGGREGATOR_CONTRACT_ADDRESS=' $(ENV_FILE) | sed 's/AGGREGATOR_CONTRACT_ADDRESS=//'); fi
	if [ -z "$$ADDR" ]; then echo "Provide AGG_ADDR=0x... or set AGGREGATOR_CONTRACT_ADDRESS in $(ENV_FILE)" >&2; exit 1; fi
	if [ -z "$$ROUND_NUMBER" ]; then echo "Provide ROUND_NUMBER=<n>" >&2; exit 1; fi
	DET=$$("$(CAST)" call "$$ADDR" "getRoundDetails(uint256)(string)" "$$ROUND_NUMBER" --rpc-url $(RPC_URL) 2>/dev/null || true)
	W=$$("$(CAST)" call "$$ADDR" "getRoundWeight(uint256)(string)" "$$ROUND_NUMBER" --rpc-url $(RPC_URL) 2>/dev/null || true)
	if [ -z "$$W" ]; then W=$$("$(CAST)" call "$$ADDR" "getRoundHash(uint256)(string)" "$$ROUND_NUMBER" --rpc-url $(RPC_URL) 2>/dev/null || true); fi
	@echo "aggregator=$$ADDR round=$$ROUND_NUMBER"
	@echo "weight_hash=$$W"
	@echo "details=$$DET"

agg-rounds: ## List aggregator details for an interval (FROM=1 TO=last, optional AGG_ADDR=0x..)
	set -euo pipefail
	ADDR="$${AGG_ADDR:-}"; if [ -z "$$ADDR" ]; then ADDR=$$(grep -E '^AGGREGATOR_CONTRACT_ADDRESS=' $(ENV_FILE) | sed 's/AGGREGATOR_CONTRACT_ADDRESS=//'); fi
	if [ -z "$$ADDR" ]; then echo "Provide AGG_ADDR=0x... or set AGGREGATOR_CONTRACT_ADDRESS in $(ENV_FILE)" >&2; exit 1; fi
	LAST=$$("$(CAST)" call "$$ADDR" "currentRound()(uint256)" --rpc-url $(RPC_URL) 2>/dev/null || true)
	FROM_N="$${FROM:-}"; if [ -z "$$FROM_N" ]; then FROM_N=1; fi
	TO_N="$${TO:-}"; if [ -z "$$TO_N" ]; then TO_N="$$LAST"; fi
	if [ -z "$$TO_N" ]; then TO_N=0; fi
	@echo "aggregator=$$ADDR rounds=$$FROM_N..$$TO_N (last=$$LAST)"
	if [ "$$TO_N" -lt "$$FROM_N" ]; then echo "Empty range"; exit 0; fi
	for ((i=$$FROM_N;i<=$$TO_N;i++)); do \
		DET=$$("$(CAST)" call "$$ADDR" "getRoundDetails(uint256)(string)" "$$i" --rpc-url $(RPC_URL) 2>/dev/null || true); \
		W=$$("$(CAST)" call "$$ADDR" "getRoundWeight(uint256)(string)" "$$i" --rpc-url $(RPC_URL) 2>/dev/null || true); \
		if [ -z "$$W" ]; then W=$$("$(CAST)" call "$$ADDR" "getRoundHash(uint256)(string)" "$$i" --rpc-url $(RPC_URL) 2>/dev/null || true); fi; \
		if [ -n "$$DET$$W" ]; then echo "round=$$i weight_hash=$$W details=$$DET"; else echo "round=$$i <empty>"; fi; \
	done

peer-round: ## Show training payload for a peer at a given round (PEER_ADDR=0x.. or PEER_INDEX=i, ROUND_NUMBER=n)
	set -euo pipefail
	ADDR="$${PEER_ADDR:-}"
	if [ -z "$$ADDR" ]; then \
		IDX="$$PEER_INDEX"; \
		if [ -z "$$IDX" ]; then echo "Provide PEER_ADDR=0x... or PEER_INDEX=<idx>" >&2; exit 1; fi; \
		PEERS_CSV=$$(grep -E '^CLIENT_CONTRACT_ADDRESSES=' $(ENV_FILE) | sed 's/CLIENT_CONTRACT_ADDRESSES=//'); \
		IFS=',' read -r -a ADDRS <<< "$$PEERS_CSV"; \
		if [ -z "$$IDX" ] || [ "$$IDX" -lt 0 ] || [ "$$IDX" -ge "$$(( $${#ADDRS[@]} ))" ]; then echo "Invalid PEER_INDEX ($$IDX)" >&2; exit 1; fi; \
		ADDR="$${ADDRS[$$IDX]}"; \
	fi
	if [ -z "$$ROUND_NUMBER" ]; then echo "Provide ROUND_NUMBER=<n>" >&2; exit 1; fi
	PAYLOAD=$$("$(CAST)" call "$$ADDR" "roundDetails(uint256)(string)" "$$ROUND_NUMBER" --rpc-url $(RPC_URL))
	@echo "peer=$$ADDR round=$$ROUND_NUMBER"
	@echo "$$PAYLOAD"

peer-rounds: ## List training payloads for a peer across rounds (PEER_ADDR=0x.. or PEER_INDEX=i, FROM=1 TO=last)
	set -euo pipefail
	ADDR="$${PEER_ADDR:-}"
	if [ -z "$$ADDR" ]; then \
		IDX="$${PEER_INDEX:-}"; \
		if [ -z "$$IDX" ]; then echo "Provide PEER_ADDR=0x... or PEER_INDEX=<idx>" >&2; exit 1; fi; \
		PEERS_CSV=$$(grep -E '^CLIENT_CONTRACT_ADDRESSES=' $(ENV_FILE) | sed 's/CLIENT_CONTRACT_ADDRESSES=//'); \
		IFS=',' read -r -a ADDRS <<< "$$PEERS_CSV"; \
		if [ -z "$$IDX" ] || [ "$$IDX" -lt 0 ] || [ "$$IDX" -ge "$$(( $${#ADDRS[@]} ))" ]; then echo "Invalid PEER_INDEX ($$IDX)" >&2; exit 1; fi; \
		ADDR="$${ADDRS[$$IDX]}"; \
	fi
	LAST=$$("$(CAST)" call "$$ADDR" "lastParticipatedRound()(uint256)" --rpc-url $(RPC_URL) 2>/dev/null || true)
	FROM_N="$${FROM:-}"; if [ -z "$$FROM_N" ]; then FROM_N=1; fi
	TO_N="$${TO:-}"; if [ -z "$$TO_N" ]; then TO_N="$$LAST"; fi
	if [ -z "$$TO_N" ]; then TO_N=0; fi
	@echo "peer=$$ADDR rounds=$$FROM_N..$$TO_N (last=$$LAST)"
	if [ "$$TO_N" -lt "$$FROM_N" ]; then echo "Empty range"; exit 0; fi
	for ((i=$$FROM_N;i<=$$TO_N;i++)); do \
		P=$$("$(CAST)" call "$$ADDR" "roundDetails(uint256)(string)" "$$i" --rpc-url $(RPC_URL) 2>/dev/null || true); \
		if [ -n "$$P" ]; then echo "round=$$i $$P"; else echo "round=$$i <empty>"; fi; \
	done
