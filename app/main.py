
import json
import time
import threading
import random
from datetime import datetime
from .blockchain import Blockchain


def display_menu():
    """Display the main menu options"""
    print("\n" + "="*50)
    print("🔗 BLOCKCHAIN MANAGEMENT SYSTEM")
    print("="*50)
    print("1. ➕ Add new transaction block")
    print("2. 📊 Display blockchain")
    print("3. 🔍 Validate blockchain integrity")
    print("4. 🚨 Report fraudulent address")
    print("5. 📈 Show statistics")
    print("6. 💾 Export blockchain to JSON")
    print("7. 🛑 Exit")
    print("8. 🚀 Start Background Server (FastAPI-like)")
    print("-" * 50)


def get_transaction_data():
    """Get transaction data from user input"""
    transactions = []
    
    print("\n📝 Adding transactions (leave 'from' empty to finish):")
    
    while True:
        print(f"\n--- Transaction #{len(transactions) + 1} ---")
        sender = input("From: ").strip()
        if not sender:
            break
            
        receiver = input("To: ").strip()
        amount = input("Amount: ").strip()
        currency = input("Currency (BTC/ETH/USD/EUR): ").strip().upper()
        
        try:
            amount_float = float(amount)
            transaction = {
                "from": sender,
                "to": receiver,
                "amount": amount_float,
                "currency": currency
            }
            transactions.append(transaction)
            print("✅ Transaction added!")
            
        except ValueError:
            print("❌ Invalid amount! Please enter a valid number.")
    
    if not transactions:
        print("❌ No transactions provided!")
        return None
    
    memo = input("\nMemo/description: ").strip()
    fee = input("Fee (optional, press Enter for default): ").strip()
    
    block_data = {
        "transactions": transactions,
        "memo": memo or "User-added transactions"
    }
    
    if fee:
        try:
            block_data["fee"] = float(fee)
        except ValueError:
            print("❌ Invalid fee, using default")
    
    return block_data


class BackgroundBlockchainServer:
        
    def __init__(self, blockchain):
        self.blockchain = blockchain
        self.is_running = False
        self.server_thread = None
        self.transaction_queue = []
        self.processing_interval = 10  
        self.last_processed = datetime.now()
        
    def start_server(self):
        
        if self.is_running:
            print("⚠️  Server is already running!")
            return
            
        self.is_running = True
        self.server_thread = threading.Thread(target=self._server_loop, daemon=True)
        self.server_thread.start()
        print("🚀 Background server started!")
        print("   📡 Listening for incoming transactions...")
        print("   ⏰ Processing queue every 10 seconds")
        print("   🛑 Use option 7 to stop the server")
        
    def stop_server(self):
        
        self.is_running = False
        if self.server_thread:
            self.server_thread.join(timeout=2)
        print("🛑 Background server stopped")
        
    def _server_loop(self):
        
        print(f"🕒 Server started at {datetime.now().strftime('%H:%M:%S')}")
        
        while self.is_running:
            try:
                current_time = datetime.now()
                
               
                if random.random() < 0.3:  # 30% chance every loop
                    self._simulate_incoming_transaction()
                
                
                if (current_time - self.last_processed).seconds >= self.processing_interval:
                    self._process_transaction_queue()
                    self.last_processed = current_time
                
                time.sleep(2)  # Check every 2 seconds
                
            except Exception as e:
                print(f"❌ Server error: {e}")
                time.sleep(5)
    
    def _simulate_incoming_transaction(self):
        
        users = ["Alice", "Bob", "Charlie", "Diana", "Eva", "Frank", "Grace", "Henry"]
        currencies = ["BTC", "ETH", "USD"]
        
        transaction = {
            "from": random.choice(users),
            "to": random.choice(users),
            "amount": round(random.uniform(0.1, 100.0), 2),
            "currency": random.choice(currencies),
            "timestamp": datetime.now().isoformat(),
            "source": "simulated"
        }
        
        
        while transaction["from"] == transaction["to"]:
            transaction["to"] = random.choice(users)
        
        self.transaction_queue.append(transaction)
        print(f"📨 Incoming transaction: {transaction['from']} -> {transaction['to']} {transaction['amount']} {transaction['currency']}")
    
    def _process_transaction_queue(self):
        
        if not self.transaction_queue:
            return
            
        print(f"\n🔄 Processing {len(self.transaction_queue)} transactions in queue...")
        
        
        transactions_to_process = self.transaction_queue.copy()
        self.transaction_queue.clear()
        
        blocks_created = 0
        while transactions_to_process:
            block_transactions = transactions_to_process[:3]
            transactions_to_process = transactions_to_process[3:]
            
            block_data = {
                "transactions": block_transactions,
                "memo": f"Auto-processed block #{blocks_created + 1}",
                "fee": 0.001,
                "processed_at": datetime.now().isoformat()
            }
            
            try:
                self.blockchain.add_block(block_data)
                blocks_created += 1
                print(f"✅ Auto-created block with {len(block_transactions)} transactions")
            except ValueError as e:
                print(f"❌ Failed to create auto-block: {e}")
        
        if blocks_created > 0:
            print(f"🎉 Successfully processed {blocks_created} new blocks!")
        
        
        print(f"📊 Server Status: {len(self.transaction_queue)} pending transactions")
    
    def get_server_status(self):
        
        return {
            "is_running": self.is_running,
            "queue_size": len(self.transaction_queue),
            "last_processed": self.last_processed.strftime('%H:%M:%S'),
            "blocks_in_chain": self.blockchain.get_chain_length()
        }


def main():
    print("🚀 Initializing Blockchain with Fraud Detection...")
    
    
    blockchain = Blockchain()
    
    
    background_server = BackgroundBlockchainServer(blockchain)
    
    
    print("\n📝 Adding initial example blocks...")
    
    try:
        
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
            "memo": "Initial example transactions"
        })
        time.sleep(1)
        
        
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
            "memo": "Example transfer"
        })
        
    except ValueError as e:
        print(f"❌ Error adding example block: {e}")
    
    print("\n✅ Blockchain initialized with example data!")
    
   
    while True:
        display_menu()
        choice = input("\nSelect an option (1-8): ").strip()
        
        if choice == "1":
            
            block_data = get_transaction_data()
            if block_data:
                try:
                    blockchain.add_block(block_data)
                    print("✅ Block added successfully!")
                except ValueError as e:
                    print(f"❌ Failed to add block: {e}")
        
        elif choice == "2":
            
            blockchain.display_chain()
        
        elif choice == "3":
            
            print("\n🔍 Validating blockchain integrity...")
            is_valid = blockchain.is_chain_valid()
            print(f"Validation status: {'✅ VALID' if is_valid else '❌ INVALID'}")
        
        elif choice == "4":
            
            address = input("Enter fraudulent address to report: ").strip()
            if address:
                blockchain.report_fraudulent_address(address)
                print(f"✅ Address '{address}' reported as fraudulent!")
            else:
                print("❌ No address provided!")
        
        elif choice == "5":
            
            status = background_server.get_server_status()
            print(f"\n📊 Blockchain Statistics:")
            print(f"   Total blocks: {blockchain.get_chain_length()}")
            print(f"   Last block hash: {blockchain.get_latest_block().hash[:20]}...")
            print(f"   Background Server: {'🟢 RUNNING' if status['is_running'] else '🔴 STOPPED'}")
            print(f"   Pending transactions: {status['queue_size']}")
            print(f"   Last processed: {status['last_processed']}")
        
        elif choice == "6":
            
            export_data = blockchain.to_dict_list()
            filename = input("Enter filename (or press Enter for 'blockchain_export.json'): ").strip()
            filename = filename or "blockchain_export.json"
            
            try:
                with open(filename, 'w', encoding='utf-8') as f:
                    json.dump(export_data, f, indent=2, ensure_ascii=False)
                print(f"✅ Blockchain exported to '{filename}'")
            except Exception as e:
                print(f"❌ Error exporting: {e}")
        
        elif choice == "7":
            
            if background_server.is_running:
                background_server.stop_server()
            print("\n👋 Thank you for using the Blockchain System!")
            print("🛑 Shutting down...")
            break
        
        elif choice == "8":
            
            if not background_server.is_running:
                background_server.start_server()
                print("\n💡 The server is now running in background!")
                print("   You can continue using other menu options")
                print("   Transactions will be processed automatically every 10 seconds")
            else:
                print("⚠️  Server is already running!")
        
        else:
            print("❌ Invalid option! Please choose 1-8.")
        
        
        time.sleep(1)


if __name__ == "__main__":
    main()