
"""
Main application for Blockchain implementation
"""

import json
import time
from datetime import datetime
from .blockchain import Blockchain


def main():
    print("🚀 Initializing Blockchain...")
    
    # Create blockchain
    blockchain = Blockchain()
    
    # Add some example blocks
    print("\n📝 Adding transaction blocks...")
    
    # Block 1
    blockchain.add_block({
        "transactions": [
            {
                "from": "Alice",
                "to": "Bob",
                "amount": 50.0,
                "currency": "BTC"
            },
            {
                "from": "Carlos", 
                "to": "Diana",
                "amount": 25.5,
                "currency": "BTC"
            }
        ],
        "fee": 0.001,
        "memo": "First transactions"
    })
    
    time.sleep(1)  # Simulate time between blocks
        
    blockchain.add_block({
        "transactions": [
            {
                "from": "Bob",
                "to": "Eva",
                "amount": 10.0,
                "currency": "BTC"
            }
        ],
        "fee": 0.0005,
        "memo": "Simple transfer"
    })
    
    time.sleep(1)
        
    blockchain.add_block({
        "type": "smart_contract",
        "contract": "ERC-20 Token",
        "action": "mint",
        "quantity": 1000,
        "recipient": "0x742d35Cc6634C0532925a3b8D"
    })
        
    blockchain.display_chain()
        
    print("\n🔍 Validating blockchain integrity...")
    is_valid = blockchain.is_chain_valid()
    print(f"Validation status: {'✅ VALID' if is_valid else '❌ INVALID'}")
        
    print(f"\n📊 Blockchain Statistics:")
    print(f"   Total blocks: {blockchain.get_chain_length()}")
    print(f"   Last block hash: {blockchain.get_latest_block().hash[:20]}...")
    
    # Export to JSON (optional)
    export_data = blockchain.to_dict_list()
    with open('blockchain_export.json', 'w', encoding='utf-8') as f:
        json.dump(export_data, f, indent=2, ensure_ascii=False)
    
    print(f"\n💾 Blockchain exported to 'blockchain_export.json'")
    print("🎉 Execution completed successfully!")


if __name__ == "__main__":
    main()