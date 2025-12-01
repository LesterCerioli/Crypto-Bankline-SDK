
from web3 import Web3
from web3.middleware import geth_poa_middleware
import requests
import os
import logging
from typing import Dict, Optional, Union
from decimal import Decimal
import json
from datetime import datetime
from dotenv import load_dotenv
import base58


load_dotenv()

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('multichain_payments.log'),
        logging.StreamHandler()
    ]
)

class BasePaymentService:
        
    def __init__(self, network: str = "mainnet"):
        self.network = network
        self.setup_provider()
        
    def validate_address(self, address: str) -> bool:
        raise NotImplementedError
        
    def get_balance(self, address: str) -> Dict:
        raise NotImplementedError
        
    def send_payment(self, to_address: str, amount: float) -> Dict:
        raise NotImplementedError

class EthereumPaymentService(BasePaymentService):
        
    def setup_provider(self):
        infura_project_id = "765b21a4071444b5bfe6cedd49e8225a"
        
        networks = {
            "mainnet": f"https://mainnet.infura.io/v3/{infura_project_id}",
            "sepolia": f"https://sepolia.infura.io/v3/{infura_project_id}",
            "goerli": f"https://goerli.infura.io/v3/{infura_project_id}"
        }
        
        if self.network not in networks:
            raise ValueError(f"Unsupported Ethereum network: {self.network}")
            
        self.web3 = Web3(Web3.HTTPProvider(networks[self.network]))
        
        if self.network in ["sepolia", "goerli"]:
            self.web3.middleware_onion.inject(geth_poa_middleware, layer=0)
            
        if not self.web3.is_connected():
            raise ConnectionError("Failed to connect to Ethereum network")

    def validate_address(self, address: str) -> bool:
        return self.web3.is_address(address)

    def get_balance(self, address: str) -> Dict:
        if not self.validate_address(address):
            raise ValueError("Invalid Ethereum address")
            
        checksum_address = self.web3.to_checksum_address(address)
        balance_wei = self.web3.eth.get_balance(checksum_address)
        balance_eth = self.web3.from_wei(balance_wei, 'ether')
        
        return {
            'address': checksum_address,
            'balance_wei': balance_wei,
            'balance_eth': float(balance_eth),
            'currency': 'ETH',
            'network': f'ethereum_{self.network}',
            'timestamp': datetime.now().isoformat()
        }

    def send_payment(self, to_address: str, amount_eth: float, private_key: str) -> Dict:
        if not self.validate_address(to_address):
            raise ValueError("Invalid recipient address")
            
        account = self.web3.eth.account.from_key(private_key)
        amount_wei = self.web3.to_wei(amount_eth, 'ether')
        
        transaction = {
            'to': self.web3.to_checksum_address(to_address),
            'value': amount_wei,
            'gas': 21000,
            'gasPrice': self.web3.eth.gas_price,
            'nonce': self.web3.eth.get_transaction_count(account.address),
            'chainId': 1 if self.network == 'mainnet' else 11155111  # sepolia
        }

        signed_tx = self.web3.eth.account.sign_transaction(transaction, private_key)
        tx_hash = self.web3.eth.send_raw_transaction(signed_tx.rawTransaction)
        
        return {
            'transaction_hash': self.web3.to_hex(tx_hash),
            'from': account.address,
            'to': to_address,
            'amount_eth': amount_eth,
            'network': f'ethereum_{self.network}',
            'currency': 'ETH'
        }

class SolanaPaymentService(BasePaymentService):
    """Solana payment service using public RPC endpoints"""
    
    def setup_provider(self):
        networks = {
            "mainnet": "https://api.mainnet-beta.solana.com",
            "devnet": "https://api.devnet.solana.com",
            "testnet": "https://api.testnet.solana.com"
        }
        
        if self.network not in networks:
            raise ValueError(f"Unsupported Solana network: {self.network}")
            
        self.rpc_url = networks[self.network]
        
    def validate_address(self, address: str) -> bool:
        
        try:
            
            if len(address) < 32 or len(address) > 44:
                return False
                
            
            base58_chars = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"
            if not all(char in base58_chars for char in address):
                return False
                
            
            payload = {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "getBalance",
                "params": [address]
            }
            
            response = requests.post(self.rpc_url, json=payload, timeout=10)
            return 'error' not in response.json()
            
        except:
            return False

    def get_balance(self, address: str) -> Dict:
        if not self.validate_address(address):
            raise ValueError("Invalid Solana address")
            
        payload = {
            "jsonrpc": "2.0",
            "id": 1,
            "method": "getBalance",
            "params": [address]
        }
        
        response = requests.post(self.rpc_url, json=payload).json()
        
        if 'error' in response:
            raise Exception(f"Solana RPC error: {response['error']}")
            
        balance_lamports = response['result']['value']
        balance_sol = balance_lamports / 1_000_000_000
        
        return {
            'address': address,
            'balance_lamports': balance_lamports,
            'balance_sol': balance_sol,
            'currency': 'SOL',
            'network': f'solana_{self.network}',
            'timestamp': datetime.now().isoformat()
        }

class BitcoinPaymentService(BasePaymentService):
        
    def setup_provider(self):
        networks = {
            "mainnet": "https://blockstream.info/api",
            "testnet": "https://blockstream.info/testnet/api"
        }
        
        if self.network not in networks:
            raise ValueError(f"Unsupported Bitcoin network: {self.network}")
            
        self.api_url = networks[self.network]
        
    def validate_address(self, address: str) -> bool:
        
        return address.startswith(('1', '3', 'bc1', 'tb1', '2', 'm', 'n'))

    def get_balance(self, address: str) -> Dict:
        if not self.validate_address(address):
            raise ValueError("Invalid Bitcoin address")
            
        try:
            
            if self.network == "mainnet":
                url = f"https://blockchain.info/balance?active={address}"
            else:
                
                url = f"https://blockstream.info/testnet/api/address/{address}"
                
            response = requests.get(url)
            data = response.json()
            
            if self.network == "mainnet":
                balance_sat = data[address]['final_balance']
            else:
                balance_sat = data['chain_stats']['funded_txo_sum'] - data['chain_stats']['spent_txo_sum']
                
            balance_btc = balance_sat / 100_000_000  # 1 BTC = 100,000,000 satoshis
            
            return {
                'address': address,
                'balance_satoshis': balance_sat,
                'balance_btc': balance_btc,
                'currency': 'BTC',
                'network': f'bitcoin_{self.network}',
                'timestamp': datetime.now().isoformat()
            }
            
        except Exception as e:
            raise Exception(f"Error fetching Bitcoin balance: {e}")

    def send_payment(self, to_address: str, amount_btc: float, private_key: str) -> Dict:
        
        raise NotImplementedError(
            "Bitcoin transaction implementation requires proper wallet management. "
            "Consider using python-bitcoinlib or similar libraries."
        )

class UniversalPaymentService:
    
    
    def __init__(self):
        self.services = {}
        
    def get_service(self, blockchain: str, network: str = "mainnet") -> BasePaymentService:
        
        key = f"{blockchain}_{network}"
        
        if key not in self.services:
            if blockchain.lower() == "ethereum":
                self.services[key] = EthereumPaymentService(network)
            elif blockchain.lower() == "solana":
                self.services[key] = SolanaPaymentService(network)
            elif blockchain.lower() == "bitcoin":
                self.services[key] = BitcoinPaymentService(network)
            else:
                raise ValueError(f"Unsupported blockchain: {blockchain}")
                
        return self.services[key]
    
    def get_supported_chains(self) -> list:
        
        return [
            {"blockchain": "Ethereum", "networks": ["mainnet", "sepolia", "goerli"], "currency": "ETH"},
            {"blockchain": "Solana", "networks": ["mainnet", "devnet", "testnet"], "currency": "SOL"},
            {"blockchain": "Bitcoin", "networks": ["mainnet", "testnet"], "currency": "BTC"}
        ]
    
    def validate_address(self, blockchain: str, address: str, network: str = "mainnet") -> Dict:
        """Validate address for specific blockchain"""
        service = self.get_service(blockchain, network)
        is_valid = service.validate_address(address)
        
        return {
            'blockchain': blockchain,
            'address': address,
            'valid': is_valid,
            'network': network
        }
    
    def get_balance(self, blockchain: str, address: str, network: str = "mainnet") -> Dict:
        
        service = self.get_service(blockchain, network)
        return service.get_balance(address)
    
    def create_payment_request(self, blockchain: str, address: str, amount: float, 
                              network: str = "mainnet") -> Dict:
        
        service = self.get_service(blockchain, network)
        
        
        if not service.validate_address(address):
            raise ValueError(f"Invalid {blockchain} address")
            
        
        currency_map = {
            "ethereum": "ETH",
            "solana": "SOL", 
            "bitcoin": "BTC"
        }
        
        currency = currency_map.get(blockchain.lower(), blockchain.upper())
        
        return {
            'payment_url': f"{blockchain.lower()}:{address}?amount={amount}",
            'qr_data': f"{blockchain.lower()}:{address}?amount={amount}&network={network}",
            'blockchain': blockchain,
            'address': address,
            'amount': amount,
            'currency': currency,
            'network': network,
            'timestamp': datetime.now().isoformat()
        }


if __name__ == "__main__":
    payment_service = UniversalPaymentService()
    
    print("Supported Blockchains:")
    for chain in payment_service.get_supported_chains():
        print(f"- {chain['blockchain']} ({chain['currency']})")
    
    
    try:
        eth_balance = payment_service.get_balance(
            "ethereum", 
            "0x742d35Cc6634C0532925a3b8Dc9F1a6C8B7e1a5d",  # Example address
            "mainnet"
        )
        print(f"\nEthereum Balance: {eth_balance}")
    except Exception as e:
        print(f"Ethereum error: {e}")
    
    
    try:
        sol_balance = payment_service.get_balance(
            "solana",
            "vines1vzrYbzLMRdu58ou5XTby4qAqVRLmqo36NKPTg",  # Example address
            "mainnet"
        )
        print(f"Solana Balance: {sol_balance}")
    except Exception as e:
        print(f"Solana error: {e}")
    
    
    payment_request = payment_service.create_payment_request(
        "ethereum",
        "0x742d35Cc6634C0532925a3b8Dc9F1a6C8B7e1a5d",
        0.1,
        "mainnet"
    )
    print(f"Payment Request: {payment_request}")