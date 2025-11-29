import hashlib
import json
from datetime import datetime
from typing import List, Dict, Any
from .block import Block


class Blockchain:
    def __init__(self):
        self.chain: List[Block] = []
        self.difficulty = 2  # Difficulty for proof-of-work
        self.create_genesis_block()

    def create_genesis_block(self) -> None:
        """
        Create the Genesis Block - the first block in the blockchain
        """
        genesis_data = {
            "message": "Genesis Block - Initial block of the blockchain",
            "creator": "System",
            "version": "1.0"
        }
        
        genesis_block = Block(
            index=0,
            timestamp=datetime.now(),
            data=genesis_data,
            previous_hash="0" * 64  # Standard initial hash
        )
                
        genesis_block.mine_block(self.difficulty)
        
        self.chain.append(genesis_block)
        print("✅ Genesis Block created successfully!")

    def get_latest_block(self) -> Block:
        """
        Returns the last block in the chain
        """
        return self.chain[-1]

    def add_block(self, data: Dict[str, Any]) -> Block:
        """
        Adds a new block to the blockchain
        """
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

    def is_chain_valid(self) -> bool:
        """
        Verifies if the blockchain is valid
        """
        for i in range(1, len(self.chain)):
            current_block = self.chain[i]
            previous_block = self.chain[i - 1]
            
            if current_block.hash != current_block.calculate_hash():
                print(f"❌ Invalid hash in block {current_block.index}")
                return False

            # Verify if the previous_hash points to the previous block
            if current_block.previous_hash != previous_block.hash:
                print(f"❌ Invalid previous hash in block {current_block.index}")
                return False

        print("✅ Blockchain is valid!")
        return True

    def display_chain(self) -> None:
        """
        Displays the entire blockchain
        """
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
        """
        Converts the blockchain to a list of dictionaries
        """
        return [block.to_dict() for block in self.chain]

    def get_block_by_index(self, index: int) -> Block:
        """
        Returns a block by its index
        """
        if 0 <= index < len(self.chain):
            return self.chain[index]
        raise IndexError("Block index out of range")

    def get_chain_length(self) -> int:
        """
        Returns the length of the chain
        """
        return len(self.chain)