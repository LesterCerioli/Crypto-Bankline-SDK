import hashlib
import json
from datetime import datetime
from typing import List, Dict, Any
from .block import Block
from .transaction_validator import TransactionValidator, FraudDetectionService


class Blockchain:
    def __init__(self):
        self.chain: List[Block] = []
        self.difficulty = 2  
        self.transaction_validator = TransactionValidator()
        self.fraud_detection = FraudDetectionService()
        self.create_genesis_block()

    def create_genesis_block(self) -> None:
        
        genesis_data = {
            "message": "Genesis Block - Initial block of the blockchain",
            "creator": "System",
            "version": "1.0"
        }
        
        genesis_block = Block(
            index=0,
            timestamp=datetime.now(),
            data=genesis_data,
            previous_hash="0" * 64  
        )
        
        
        genesis_block.mine_block(self.difficulty)
        
        self.chain.append(genesis_block)
        print("Genesis Block created successfully!")

    def get_latest_block(self) -> Block:
        
        return self.chain[-1]

    def add_block(self, data: Dict[str, Any]) -> Block:
        
        
        if not self._validate_block_data(data):
            raise ValueError("Block contains invalid or fraudulent transactions")
        
        previous_block = self.get_latest_block()
        
        new_block = Block(
            index=len(self.chain),
            timestamp=datetime.now(),
            data=data,
            previous_hash=previous_block.hash
        )
                
        new_block.mine_block(self.difficulty)
        
        self.chain.append(new_block)
        print(f"✅ New block #{new_block.index} added to the blockchain!")
        return new_block

    def _validate_block_data(self, data: Dict[str, Any]) -> bool:
        
        print("\n🔐 Starting transaction validation...")
        
        
        if not data:
            print("Block data is empty")
            return False
                
        if 'transactions' in data:
            if not self.transaction_validator.validate_block_transactions(data):
                print("Block rejected due to invalid transactions")
                return False
            
            
            for transaction in data['transactions']:
                fraud_analysis = self.fraud_detection.analyze_transaction_pattern(transaction)
                if fraud_analysis['is_suspicious']:
                    print(f"🚨 Fraud detection alert for transaction:")
                    print(f"   Reasons: {', '.join(fraud_analysis['reasons'])}")
                    print(f"   Confidence: {fraud_analysis['confidence']:.2f}")
                    return False
        
        print("All transactions validated successfully!")
        return True

    def is_chain_valid(self) -> bool:
        
        for i in range(1, len(self.chain)):
            current_block = self.chain[i]
            previous_block = self.chain[i - 1]
            
            if current_block.hash != current_block.calculate_hash():
                print(f"Invalid hash in block {current_block.index}")
                return False

            
            if current_block.previous_hash != previous_block.hash:
                print(f"❌ Invalid previous hash in block {current_block.index}")
                return False

        print("Blockchain is valid!")
        return True

    def display_chain(self) -> None:
        
        print("\n" + "="*80)
        print("COMPLETE BLOCKCHAIN")
        print("="*80)
        
        for block in self.chain:
            print(f"\n📦 Block #{block.index}")
            print(f"   Timestamp: {block.timestamp}")
            print(f"   Hash: {block.hash}")
            print(f"   Previous Hash: {block.previous_hash}")
            print(f"   Nonce: {block.nonce}")
            print(f"   Data: {json.dumps(block.data, indent=4, ensure_ascii=False)}")
            print("-" * 50)

    def to_dict_list(self) -> List[Dict[str, Any]]:
        
        return [block.to_dict() for block in self.chain]

    def get_block_by_index(self, index: int) -> Block:
        
        if 0 <= index < len(self.chain):
            return self.chain[index]
        raise IndexError("Block index out of range")

    def get_chain_length(self) -> int:
        
        return len(self.chain)
    
    def report_fraudulent_address(self, address: str) -> None:
        
        self.transaction_validator.add_fraudulent_address(address)
        print(f"🚨 Reported fraudulent address: {address}")