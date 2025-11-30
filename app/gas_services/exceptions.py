class GasServiceError(Exception):
    pass

class GasAPIError(GasServiceError):
    def __init__(self, message: str, status_code: int = None, response_text: str = None):
        self.status_code = status_code
        self.response_text = response_text
        super().__init__(message)

class InvalidChainError(GasServiceError):
    pass

class ConfigurationError(GasServiceError):
    pass

class RateLimitError(GasAPIError):
    pass

class AuthenticationError(GasAPIError):
    pass