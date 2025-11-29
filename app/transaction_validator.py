import hashlib
import json
from datetime import datetime, timedelta
from typing import Dict, Any, List, Optional
import re
import threading
import time
from collections import defaultdict, deque


class TransactionValidator:
    """
    Validates transactions and provides continuous fraud monitoring
    """
    
    def __init__(self):
        self.valid_currencies = {'BTC', 'ETH', 'USD', 'EUR'}
        self.min_transaction_amount = 0.0001
        self.max_transaction_amount = 1000000
        self.suspicious_patterns = [
            r'.*(test|fake|dummy).*',
            r'0000000000+',
            r'1234567890+'
        ]
        self.known_fraudulent_addresses = set()
        self._monitoring_active = False
        self._monitor_thread = None
        
    def start_continuous_monitoring(self, check_interval: int = 30) -> None:
        """
        Start continuous background monitoring for fraudulent patterns
        """
        if self._monitoring_active:
            print("⚠️ Monitoring is already active")
            return
            
        self._monitoring_active = True
        self._monitor_thread = threading.Thread(
            target=self._monitoring_loop,
            args=(check_interval,),
            daemon=True
        )
        self._monitor_thread.start()
        print(f"🔍 Continuous fraud monitoring started (checking every {check_interval}s)")
    
    def stop_continuous_monitoring(self) -> None:
        """
        Stop the continuous monitoring
        """
        self._monitoring_active = False
        if self._monitor_thread:
            self._monitor_thread.join(timeout=5)
        print("🛑 Continuous fraud monitoring stopped")
    
    def _monitoring_loop(self, check_interval: int) -> None:
        """
        Background monitoring loop for system-wide fraud detection
        """
        while self._monitoring_active:
            try:
                # Perform system health checks
                self._perform_system_health_check()
                
                # Check for patterns across recent transactions
                self._analyze_system_patterns()
                
                # Sleep until next check
                time.sleep(check_interval)
                
            except Exception as e:
                print(f"❌ Error in monitoring loop: {e}")
                time.sleep(check_interval)  # Continue even if there's an error
    
    def _perform_system_health_check(self) -> None:
        """
        Perform system-wide health and security checks
        """
        # Monitor for unusual system patterns
        current_time = datetime.now()
        print(f"🛡️  System health check at {current_time.strftime('%H:%M:%S')}")
        
        # Check if known fraudulent addresses list needs updating
        # (In a real system, this would fetch from external sources)
        if len(self.known_fraudulent_addresses) > 0:
            print(f"   📊 Monitoring {len(self.known_fraudulent_addresses)} known fraudulent addresses")
    
    def _analyze_system_patterns(self) -> None:
        """
        Analyze system-wide transaction patterns for anomalies
        """
        # This would integrate with a larger transaction database in production
        # For now, it's a placeholder for system-wide pattern analysis
        pass
    
    def validate_transaction(self, transaction: Dict[str, Any]) -> Dict[str, Any]:
        """
        Validate a single transaction and return validation result
        """
        validation_result = {
            'is_valid': True,
            'errors': [],
            'warnings': [],
            'risk_score': 0,
            'timestamp': datetime.now().isoformat()
        }
        
        # Check required fields
        required_fields = ['from', 'to', 'amount', 'currency']
        for field in required_fields:
            if field not in transaction:
                validation_result['is_valid'] = False
                validation_result['errors'].append(f"Missing required field: {field}")
                continue
        
        if not validation_result['is_valid']:
            return validation_result
        
        # Validate sender and receiver
        self._validate_addresses(transaction, validation_result)
        
        # Validate amount
        self._validate_amount(transaction, validation_result)
        
        # Validate currency
        self._validate_currency(transaction, validation_result)
        
        # Check for suspicious patterns
        self._check_suspicious_patterns(transaction, validation_result)
        
        # Calculate risk score
        validation_result['risk_score'] = self._calculate_risk_score(validation_result)
        
        # If high risk, mark as invalid
        if validation_result['risk_score'] >= 80:
            validation_result['is_valid'] = False
            validation_result['errors'].append("Transaction flagged as high risk")
        
        return validation_result
    
    def _validate_addresses(self, transaction: Dict[str, Any], validation_result: Dict[str, Any]) -> None:
        """Validate sender and receiver addresses"""
        sender = transaction['from']
        receiver = transaction['to']
        
        # Check for empty addresses
        if not sender or not receiver:
            validation_result['is_valid'] = False
            validation_result['errors'].append("Sender or receiver address is empty")
            return
        
        # Check for self-transaction
        if sender == receiver:
            validation_result['warnings'].append("Self-transaction detected")
            validation_result['risk_score'] += 10
        
        # Check against known fraudulent addresses
        if sender in self.known_fraudulent_addresses:
            validation_result['is_valid'] = False
            validation_result['errors'].append("Sender address is flagged as fraudulent")
        
        if receiver in self.known_fraudulent_addresses:
            validation_result['warnings'].append("Receiver address is in watchlist")
            validation_result['risk_score'] += 30
    
    def _validate_amount(self, transaction: Dict[str, Any], validation_result: Dict[str, Any]) -> None:
        """Validate transaction amount"""
        try:
            amount = float(transaction['amount'])
            
            if amount < self.min_transaction_amount:
                validation_result['is_valid'] = False
                validation_result['errors'].append(f"Amount too small. Minimum: {self.min_transaction_amount}")
            
            if amount > self.max_transaction_amount:
                validation_result['warnings'].append("Unusually large transaction amount")
                validation_result['risk_score'] += 20
            
            # Check for round numbers (potential test transactions)
            if amount % 1 == 0:
                validation_result['risk_score'] += 5
                
        except (ValueError, TypeError):
            validation_result['is_valid'] = False
            validation_result['errors'].append("Invalid amount format")
    
    def _validate_currency(self, transaction: Dict[str, Any], validation_result: Dict[str, Any]) -> None:
        """Validate currency type"""
        currency = transaction['currency']
        
        if currency not in self.valid_currencies:
            validation_result['is_valid'] = False
            validation_result['errors'].append(f"Invalid currency: {currency}")
    
    def _check_suspicious_patterns(self, transaction: Dict[str, Any], validation_result: Dict[str, Any]) -> None:
        """Check for suspicious patterns in transaction data"""
        transaction_str = json.dumps(transaction, sort_keys=True).lower()
        
        for pattern in self.suspicious_patterns:
            if re.search(pattern, transaction_str, re.IGNORECASE):
                validation_result['warnings'].append("Suspicious pattern detected")
                validation_result['risk_score'] += 15
                break
    
    def _calculate_risk_score(self, validation_result: Dict[str, Any]) -> int:
        """Calculate overall risk score for the transaction"""
        risk_score = validation_result.get('risk_score', 0)
        
        # Cap the risk score at 100
        return min(risk_score, 100)
    
    def add_fraudulent_address(self, address: str) -> None:
        """Add an address to the fraudulent addresses list"""
        self.known_fraudulent_addresses.add(address)
        print(f"🚨 Added fraudulent address: {address}")
    
    def validate_block_transactions(self, block_data: Dict[str, Any]) -> bool:
        """
        Validate all transactions in a block before adding to blockchain
        """
        if 'transactions' not in block_data:
            print("❌ No transactions found in block data")
            return False
        
        transactions = block_data['transactions']
        
        if not isinstance(transactions, list):
            print("❌ Transactions must be a list")
            return False
        
        all_valid = True
        
        for i, transaction in enumerate(transactions):
            print(f"🔍 Validating transaction {i + 1}...")
            validation_result = self.validate_transaction(transaction)
            
            if not validation_result['is_valid']:
                all_valid = False
                print(f"❌ Transaction {i + 1} validation failed:")
                for error in validation_result['errors']:
                    print(f"   - {error}")
            else:
                risk_level = "LOW" if validation_result['risk_score'] < 30 else "MEDIUM" if validation_result['risk_score'] < 70 else "HIGH"
                print(f"✅ Transaction {i + 1} validated (Risk: {risk_level} - {validation_result['risk_score']}%)")
                
                if validation_result['warnings']:
                    for warning in validation_result['warnings']:
                        print(f"   ⚠️  Warning: {warning}")
        
        return all_valid


class FraudDetectionService:
    """
    Advanced fraud detection with continuous pattern analysis
    """
    
    def __init__(self):
        self.transaction_history = deque(maxlen=1000)  # Fixed size history
        self.address_activity = defaultdict(list)
        self.validator = TransactionValidator()
        self._analysis_active = False
        self._analysis_thread = None
    
    def start_continuous_analysis(self, analysis_interval: int = 60) -> None:
        """
        Start continuous background analysis of transaction patterns
        """
        if self._analysis_active:
            print("⚠️ Pattern analysis is already active")
            return
            
        self._analysis_active = True
        self._analysis_thread = threading.Thread(
            target=self._analysis_loop,
            args=(analysis_interval,),
            daemon=True
        )
        self._analysis_thread.start()
        print(f"📊 Continuous pattern analysis started (analyzing every {analysis_interval}s)")
    
    def stop_continuous_analysis(self) -> None:
        """
        Stop the continuous pattern analysis
        """
        self._analysis_active = False
        if self._analysis_thread:
            self._analysis_thread.join(timeout=5)
        print("🛑 Continuous pattern analysis stopped")
    
    def _analysis_loop(self, analysis_interval: int) -> None:
        """
        Background analysis loop for transaction patterns
        """
        while self._analysis_active:
            try:
                self._analyze_transaction_patterns()
                self._detect_behavioral_anomalies()
                time.sleep(analysis_interval)
            except Exception as e:
                print(f"❌ Error in analysis loop: {e}")
                time.sleep(analysis_interval)
    
    def _analyze_transaction_patterns(self) -> None:
        """
        Analyze transaction patterns across the entire system
        """
        if not self.transaction_history:
            return
            
        current_time = datetime.now()
        time_threshold = current_time - timedelta(hours=1)
        
        # Analyze recent transaction frequency
        recent_tx_count = len(self.transaction_history)
        print(f"📈 System Analysis: {recent_tx_count} transactions in history")
        
        # Check for unusual activity patterns
        self._check_unusual_activity_patterns()
    
    def _check_unusual_activity_patterns(self) -> None:
        """
        Check for unusual activity patterns across addresses
        """
        # Analyze address activity patterns
        suspicious_addresses = []
        
        for address, timestamps in self.address_activity.items():
            if len(timestamps) > 10:  # More than 10 transactions
                recent_activity = [ts for ts in timestamps if ts > datetime.now() - timedelta(minutes=10)]
                if len(recent_activity) > 5:  # More than 5 transactions in 10 minutes
                    suspicious_addresses.append(address)
        
        if suspicious_addresses:
            print(f"🚨 Detected unusual activity from {len(suspicious_addresses)} addresses")
    
    def _detect_behavioral_anomalies(self) -> None:
        """
        Detect behavioral anomalies in transaction patterns
        """
        # This would implement more sophisticated anomaly detection
        # For now, it's a placeholder for advanced behavioral analysis
        pass
    
    def analyze_transaction_pattern(self, transaction: Dict[str, Any]) -> Dict[str, Any]:
        """
        Analyze transaction patterns for potential fraud
        """
        analysis = {
            'is_suspicious': False,
            'reasons': [],
            'confidence': 0.0,
            'analysis_timestamp': datetime.now().isoformat()
        }
        
        # Track address activity
        sender = transaction.get('from')
        if sender:
            self.address_activity[sender].append(datetime.now())
            # Clean old timestamps
            self.address_activity[sender] = [
                ts for ts in self.address_activity[sender] 
                if ts > datetime.now() - timedelta(hours=24)
            ]
        
        # Check for rapid successive transactions
        recent_transactions = [
            t for t in list(self.transaction_history)[-10:] 
            if t.get('from') == transaction.get('from')
        ]
        
        if len(recent_transactions) > 3:
            analysis['is_suspicious'] = True
            analysis['reasons'].append("Unusually high transaction frequency")
            analysis['confidence'] = 0.7
        
        # Check for amount anomalies
        amounts = [
            t.get('amount', 0) for t in list(self.transaction_history)[-20:] 
            if isinstance(t.get('amount'), (int, float))
        ]
        
        if amounts:
            avg_amount = sum(amounts) / len(amounts)
            current_amount = transaction.get('amount', 0)
            
            if current_amount > avg_amount * 10:  # 10x above average
                analysis['is_suspicious'] = True
                analysis['reasons'].append("Transaction amount significantly above average")
                analysis['confidence'] = max(analysis['confidence'], 0.6)
        
        # Add to transaction history
        transaction_with_timestamp = transaction.copy()
        transaction_with_timestamp['analysis_timestamp'] = datetime.now().isoformat()
        self.transaction_history.append(transaction_with_timestamp)
        
        return analysis
    
    def get_system_stats(self) -> Dict[str, Any]:
        """
        Get current system statistics
        """
        return {
            'total_transactions_analyzed': len(self.transaction_history),
            'monitored_addresses': len(self.address_activity),
            'known_fraudulent_addresses': len(self.validator.known_fraudulent_addresses),
            'analysis_active': self._analysis_active
        }