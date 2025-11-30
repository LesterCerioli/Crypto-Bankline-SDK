from dataclasses import dataclass
from typing import Optional, Dict, Any
from datetime import datetime

@dataclass
class BaseFeeResponse:
    chain_id: str
    base_fee_percentile: float
    unit: str = "Gwei"
    timestamp: Optional[datetime] = None
    raw_response: Optional[Dict[str, Any]] = None
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            'chain_id': self.chain_id,
            'base_fee_percentile': self.base_fee_percentile,
            'unit': self.unit,
            'timestamp': self.timestamp.isoformat() if self.timestamp else None
        }

@dataclass
class GasRecommendation:
    chain_id: str
    base_fee: float
    recommendation: str
    confidence: str
    historical_context: Dict[str, Any]
    
    def get_suggested_fee(self, multiplier: float = 1.2) -> float:
        return round(self.base_fee * multiplier, 6)

@dataclass
class NetworkStats:
    chain_id: str
    current_base_fee: float
    percentile_50: float
    percentile_75: float
    percentile_90: float
    gas_used_ratio: Optional[float] = None
    is_congested: bool = False