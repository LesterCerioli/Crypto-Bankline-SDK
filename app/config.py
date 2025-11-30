import os
from typing import Dict, Any
from dotenv import load_dotenv

load_dotenv()

class GasServiceConfig:
            
    INFURA_GAS_API_BASE_URL = os.getenv('INFURA_GAS_API_BASE_URL')
    INFURA_PROJECT_ID = os.getenv('INFURA_PROJECT_ID')
    INFURA_PROJECT_SECRET = os.getenv('INFURA_PROJECT_SECRET')
        
    REQUEST_TIMEOUT = 30
    MAX_RETRIES = 3
    RETRY_DELAY = 1
        
    SUPPORTED_CHAINS = {
        '1': 'ethereum',
        '137': 'polygon',
        '56': 'binance',
        '42161': 'arbitrum',
        '10': 'optimism',
        '43114': 'avalanche'
    }
    
    @classmethod
    def validate_config(cls):
        
        if not cls.INFURA_PROJECT_ID:
            raise ValueError("INFURA_PROJECT_ID environment variable is required")
        if not cls.INFURA_PROJECT_SECRET:
            raise ValueError("INFURA_PROJECT_SECRET environment variable is required")


GasServiceConfig.validate_config()