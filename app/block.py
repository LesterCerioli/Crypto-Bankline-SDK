import hashlib
import json
from datetime import datetime
from typing import Any, Dict


class Block:
    def __init__(self, index: int, timestamp: datetime, data: Dict[str, Any], previous_hash: str = ""):
        self.index = index
        self.timestamp = timestamp
        self.data = data
        self.previous_hash = previous_hash
        self.nonce = 0  # This line must come BEFORE calculate_hash()
        self.hash = self.calculate_hash()  # This line must come AFTER nonce

    def calculate_hash(self) -> str:
        """
        Calculate SHA-256 hash of the block
        """
        block_string = json.dumps({
            "index": self.index,
            "timestamp": self.timestamp.isoformat(),
            "data": self.data,
            "previous_hash": self.previous_hash,
            "nonce": self.nonce
        }, sort_keys=True)
        
        return hashlib.sha256(block_string.encode()).hexdigest()

    def mine_block(self, difficulty: int = 2) -> None:
        """
        Implement proof-of-work (mining)
        """
        target = "0" * difficulty
        while self.hash[:difficulty] != target:
            self.nonce += 1
            self.hash = self.calculate_hash()
        
        print(f"Mined block: {self.hash}")

    def to_dict(self) -> Dict[str, Any]:
        """
        Convert block to dictionary
        """
        return {
            "index": self.index,
            "timestamp": self.timestamp.isoformat(),
            "data": self.data,
            "previous_hash": self.previous_hash,
            "hash": self.hash,
            "nonce": self.nonce
        }

    def __repr__(self) -> str:
        return f"Block(Index: {self.index}, Hash: {self.hash[:10]}..., Previous Hash: {self.previous_hash[:10]}...)"