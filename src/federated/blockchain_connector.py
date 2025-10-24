# src/federated/blockchain_connector.py
import os, json
from dotenv import load_dotenv
from web3 import Web3
from eth_account import Account

load_dotenv()

class Web3Connector:
    def __init__(self):
        self.w3 = Web3(Web3.HTTPProvider(os.getenv("WEB3_HTTP_PROVIDER")))
        assert self.w3.is_connected(), "Web3 not connected"

        # Aggregator
        self.agg_key = os.getenv("AGGREGATOR_PRIVATE_KEY")
        self.agg_acct = Account.from_key(self.agg_key)

        with open(os.getenv("AGGREGATOR_ABI_PATH")) as f:
            agg_abi = json.load(f)
        self.agg_contract = self.w3.eth.contract(
            address=Web3.to_checksum_address(os.getenv("AGGREGATOR_CONTRACT_ADDRESS")),
            abi=agg_abi
        )

        # Client (peers)
        with open(os.getenv("CLIENT_ABI_PATH")) as f:
            client_abi = json.load(f)

        addrs = [a.strip() for a in os.getenv("CLIENT_CONTRACT_ADDRESSES").split(",") if a.strip()]
        keys  = [k.strip() for k in os.getenv("CLIENT_PRIVATE_KEYS").split(",") if k.strip()]
        assert len(addrs) == len(keys) > 0, "Invalid client contracts configuration"

        self.client_contracts = []
        for k, addr in zip(keys, addrs):
            acct = Account.from_key(k)
            self.client_contracts.append({
                "acct": acct,
                "contract": self.w3.eth.contract(address=Web3.to_checksum_address(addr), abi=client_abi)
            })

    # ---------- low-level tx helper ----------
    def _send_tx(self, acct, fn):
        tx = fn.build_transaction({
            "from": acct.address,
            "nonce": self.w3.eth.get_transaction_count(acct.address),
            "gas": fn.estimate_gas({"from": acct.address}),
            "gasPrice": self.w3.eth.gas_price,
            "chainId": self.w3.eth.chain_id,
        })
        signed = self.w3.eth.account.sign_transaction(tx, private_key=acct.key)
        raw = getattr(signed, "rawTransaction", None) or getattr(signed, "raw_transaction", None)
        tx_hash = self.w3.eth.send_raw_transaction(raw)
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
        return receipt

    # ---------- writes ----------
    def mint_peer_round(self, round_id: int, info_str: str, peer_idx: int):
        c = self.client_contracts[peer_idx]["contract"]
        acct = self.client_contracts[peer_idx]["acct"]
        fn = c.functions.mint(round_id, info_str)
        return self._send_tx(acct, fn)

    def mint_aggregator_round(self, hash_avg: str, round_info_json: str):
        fn = self.agg_contract.functions.mint(hash_avg, round_info_json)
        return self._send_tx(self.agg_acct, fn)

    # ---------- reads (aggregator) ----------
    def get_current_round(self) -> int:
        return int(self.agg_contract.functions.getCurrentRound().call())

    def get_federated_status(self) -> int:
        # public variable in the smart contract
        return int(self.agg_contract.functions.federatedStatus().call())

    def get_aggregator_address(self) -> str:
        return self.agg_contract.functions.getAggregator().call()

    def get_round_details(self, round_id: int) -> str:
        return self.agg_contract.functions.getRoundDetails(round_id).call()

    def get_round_weight(self, round_id: int) -> str:
        # if the contract exposes getRoundWeight (per your list)
        return self.agg_contract.functions.getRoundWeight(round_id).call()

    def get_round_hash(self, round_id: int) -> str:
        # if the contract exposes getRoundHash (per your list)
        return self.agg_contract.functions.getRoundHash(round_id).call()

    # ---------- reads (peer) ----------
    def peer_get_status(self, peer_idx: int) -> int:
        c = self.client_contracts[peer_idx]["contract"]
        return int(c.functions.getPeerStatus().call())

    def peer_get_last_round(self, peer_idx: int) -> int:
        c = self.client_contracts[peer_idx]["contract"]
        return int(c.functions.getLastParticipatedRound().call())

    def peer_get_address(self, peer_idx: int) -> str:
        c = self.client_contracts[peer_idx]["contract"]
        return c.functions.getPeerAddress().call()

    def peer_get_round_details(self, peer_idx: int, round_id: int) -> str:
        # FedPeer exposes the public getter "roundDetails(uint256)"
        c = self.client_contracts[peer_idx]["contract"]
        return c.functions.roundDetails(round_id).call()

    # ---------- helpers ----------
    def peer_count(self) -> int:
        return len(self.client_contracts)

    def get_peer_account_address(self, peer_idx: int) -> str:
        return self.client_contracts[peer_idx]["acct"].address

    def get_aggregator_account_address(self) -> str:
        return self.agg_acct.address

    def get_balance_eth(self, address: str) -> float:
        bal_wei = self.w3.eth.get_balance(Web3.to_checksum_address(address))
        # Web3.from_wei returns Decimal; cast to float for logging
        return float(self.w3.from_wei(bal_wei, 'ether'))
