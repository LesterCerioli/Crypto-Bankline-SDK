import requests
import json
import time
from typing import Dict, Any, Optional, List
from datetime import datetime, timedelta
import logging
from urllib.parse import urljoin

from .models import BaseFeeResponse, GasRecommendation, NetworkStats
from .exceptions import (
    GasAPIError, InvalidChainError, RateLimitError, 
    AuthenticationError, ConfigurationError
)
from app.config import GasServiceConfig


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class InfuraGasClient:
        
    def __init__(
        self, 
        project_id: Optional[str] = None,
        project_secret: Optional[str] = None,
        base_url: Optional[str] = None
    ):
        self.project_id = project_id or GasServiceConfig.INFURA_PROJECT_ID
        self.project_secret = project_secret or GasServiceConfig.INFURA_PROJECT_SECRET
        self.base_url = base_url or GasServiceConfig.INFURA_GAS_API_BASE_URL
        self.timeout = GasServiceConfig.REQUEST_TIMEOUT
        self.max_retries = GasServiceConfig.MAX_RETRIES
        self.retry_delay = GasServiceConfig.RETRY_DELAY
        
        self._session = requests.Session()
        self._setup_session()
        
        self._validate_credentials()
    
    def _validate_credentials(self):
        
        if not self.project_id:
            raise ConfigurationError("Infura Project ID is required")
        if not self.project_secret:
            raise ConfigurationError("Infura Project Secret is required")
    
    def _setup_session(self):
        
        self._session.auth = (self.project_id, self.project_secret)
        self._session.headers.update({
            'Content-Type': 'application/json',
            'User-Agent': 'Blockchain-Gas-Service/1.0.0'
        })
    
    def _make_request(self, method: str, endpoint: str, **kwargs) -> Dict[str, Any]:
        
        url = urljoin(self.base_url, endpoint)
        
        for attempt in range(self.max_retries):
            try:
                logger.debug(f"Making request to {url} (attempt {attempt + 1})")
                
                response = self._session.request(
                    method=method,
                    url=url,
                    timeout=self.timeout,
                    **kwargs
                )
                                
                if response.status_code == 200:
                    return response.json()
                
                elif response.status_code == 401:
                    raise AuthenticationError(
                        "Invalid Infura credentials",
                        status_code=response.status_code,
                        response_text=response.text
                    )
                
                elif response.status_code == 429:
                    if attempt < self.max_retries - 1:
                        wait_time = self.retry_delay * (2 ** attempt)  # Exponential backoff
                        logger.warning(f"Rate limited, waiting {wait_time}s before retry")
                        time.sleep(wait_time)
                        continue
                    raise RateLimitError(
                        "Rate limit exceeded",
                        status_code=response.status_code,
                        response_text=response.text
                    )
                
                elif response.status_code >= 400:
                    raise GasAPIError(
                        f"API request failed with status {response.status_code}",
                        status_code=response.status_code,
                        response_text=response.text
                    )
                    
            except requests.exceptions.Timeout:
                logger.warning(f"Request timeout (attempt {attempt + 1})")
                if attempt == self.max_retries - 1:
                    raise GasAPIError("Request timeout after multiple retries")
                
            except requests.exceptions.ConnectionError:
                logger.warning(f"Connection error (attempt {attempt + 1})")
                if attempt == self.max_retries - 1:
                    raise GasAPIError("Connection error after multiple retries")
                
            except json.JSONDecodeError as e:
                raise GasAPIError(f"Invalid JSON response: {e}")
                        
            if attempt < self.max_retries - 1:
                time.sleep(self.retry_delay)
        
        raise GasAPIError("Max retries exceeded")
    
    def _validate_chain_id(self, chain_id: str) -> None:
        
        if not isinstance(chain_id, str) or not chain_id.isdigit():
            raise InvalidChainError(f"Invalid chain ID format: {chain_id}")
        
        if chain_id not in GasServiceConfig.SUPPORTED_CHAINS:
            logger.warning(f"Chain ID {chain_id} may not be supported by Infura Gas API")
    
    def get_base_fee_percentile(self, chain_id: str) -> BaseFeeResponse:
        
        self._validate_chain_id(chain_id)
        
        try:
            endpoint = f"/networks/{chain_id}/baseFeePercentile"
            response_data = self._make_request('GET', endpoint)
                        
            if 'baseFeePercentile' not in response_data:
                raise GasAPIError("Invalid response format: missing 'baseFeePercentile'")
            
            base_fee_str = response_data['baseFeePercentile']
            
            try:
                base_fee_float = float(base_fee_str)
            except ValueError:
                raise GasAPIError(f"Invalid base fee value: {base_fee_str}")
            
            return BaseFeeResponse(
                chain_id=chain_id,
                base_fee_percentile=base_fee_float,
                timestamp=datetime.now(),
                raw_response=response_data
            )
            
        except Exception as e:
            logger.error(f"Error getting base fee percentile for chain {chain_id}: {e}")
            raise
    
    def get_gas_recommendation(self, chain_id: str) -> GasRecommendation:
        
        base_fee_response = self.get_base_fee_percentile(chain_id)
        base_fee = base_fee_response.base_fee_percentile
                
        if base_fee < 20:
            recommendation = "Low network activity - optimal time for transactions"
            confidence = "high"
        elif base_fee < 50:
            recommendation = "Moderate network activity - standard fees recommended"
            confidence = "medium"
        elif base_fee < 100:
            recommendation = "High network activity - consider higher fees for faster confirmation"
            confidence = "medium"
        else:
            recommendation = "Very high network activity - expect slow confirmations with standard fees"
            confidence = "high"
        
        historical_context = {
            'current_percentile_50': base_fee,
            'suggested_multiplier': 1.2,
            'estimated_confirmation_time': self._estimate_confirmation_time(base_fee)
        }
        
        return GasRecommendation(
            chain_id=chain_id,
            base_fee=base_fee,
            recommendation=recommendation,
            confidence=confidence,
            historical_context=historical_context
        )
    
    def _estimate_confirmation_time(self, base_fee: float) -> str:
        
        if base_fee < 20:
            return "1-2 minutes"
        elif base_fee < 50:
            return "2-5 minutes"
        elif base_fee < 100:
            return "5-15 minutes"
        else:
            return "15+ minutes"
    
    def get_network_stats(self, chain_id: str) -> NetworkStats:
        
        base_fee_response = self.get_base_fee_percentile(chain_id)
                
        percentile_75 = base_fee_response.base_fee_percentile * 1.5
        percentile_90 = base_fee_response.base_fee_percentile * 2.0
        
        return NetworkStats(
            chain_id=chain_id,
            current_base_fee=base_fee_response.base_fee_percentile,
            percentile_50=base_fee_response.base_fee_percentile,
            percentile_75=round(percentile_75, 6),
            percentile_90=round(percentile_90, 6),
            is_congested=base_fee_response.base_fee_percentile > 50
        )
    
    def batch_get_base_fees(self, chain_ids: List[str]) -> Dict[str, BaseFeeResponse]:
        
        results = {}
        
        for chain_id in chain_ids:
            try:
                results[chain_id] = self.get_base_fee_percentile(chain_id)
            except Exception as e:
                logger.error(f"Failed to get base fee for chain {chain_id}: {e}")
                
        
        return results
    
    def test_connection(self) -> bool:
        
        try:
            
            self.get_base_fee_percentile("1")
            return True
        except Exception as e:
            logger.error(f"Connection test failed: {e}")
            return False
    
    def close(self):
        """Close the HTTP session"""
        self._session.close()
    
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.close()