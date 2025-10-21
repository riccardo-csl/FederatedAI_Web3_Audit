import os, json
from dotenv import load_dotenv
from web3 import Web3
from eth_account import Account

load_dotenv()

class Web3Connector:
    def __init__(self):
        self.w3 = Web3(Web3.HTTPProvider(os.getenv("WEB3_HTTP_PROVIDER")))
        assert self.w3.is_connected(), "Web3 non connesso"
        # Aggregatore
        self.agg_key = os.getenv("AGGREGATOR_PRIVATE_KEY")
        self.agg_acct = Account.from_key(self.agg_key)
        with open(os.getenv("AGGREGATOR_ABI_PATH")) as f:
            agg_abi = json.load(f)
        self.agg_contract = self.w3.eth.contract(
            address=os.getenv("AGGREGATOR_CONTRACT_ADDRESS"),
            abi=agg_abi
        )
        # Client
        with open(os.getenv("CLIENT_ABI_PATH")) as f:
            client_abi = json.load(f)
        self.client_contracts = []
        addrs = os.getenv("CLIENT_CONTRACT_ADDRESSES").split(",")
        keys  = os.getenv("CLIENT_PRIVATE_KEYS").split(",")
        for k, addr in zip(keys, addrs):
            acct = Account.from_key(k)
            self.client_contracts.append({"acct": acct, "contract":
                self.w3.eth.contract(address=addr, abi=client_abi)})
    def _send_tx(self, acct, fn):
        # build tx
        tx = fn.build_transaction({
            "from": acct.address,
            "nonce": self.w3.eth.get_transaction_count(acct.address),
            "gasPrice": self.w3.eth.gas_price,      # ok con Ganache
            "chainId": self.w3.eth.chain_id,        # esplicito: evita edge-cases
        })
        # sign
        signed = self.w3.eth.account.sign_transaction(tx, private_key=acct.key)

        # web3.py v5 vs v6 compat
        raw = getattr(signed, "rawTransaction", None) or getattr(signed, "raw_transaction", None)
        assert raw, "SignedTransaction missing raw transaction payload"

        # send
        tx_hash = self.w3.eth.send_raw_transaction(raw)
        receipt = self.w3.eth.wait_for_transaction_receipt(tx_hash)
        return receipt

    def mint_peer_round(self, round_id: int, info_str: str, peer_idx: int):
        cinfo = self.client_contracts[peer_idx]
        fn = cinfo["contract"].functions.mint(round_id, info_str)
        return self._send_tx(cinfo["acct"], fn)

    def mint_aggregator_round(self, hash_avg: str, round_info_json: str):
        fn = self.agg_contract.functions.mint(hash_avg, round_info_json)
        return self._send_tx(self.agg_acct, fn)
