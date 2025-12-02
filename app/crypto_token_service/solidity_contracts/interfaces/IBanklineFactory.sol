pragma solidity ^0.8.20;

/**
 * @title IBanklineFactory
 * @dev Interface para a fábrica de tokens do Crypto Bankline
 */
interface IBanklineFactory {
    // ==============================
    // ENUMS & STRUCTS
    // ==============================
    
    enum TokenType {
        UTILITY,        // 0: Token de utilidade
        SECURITY,       // 1: Token de segurança
        GOVERNANCE,     // 2: Token de governança
        PAYMENT,        // 3: Token de pagamento
        NFT,            // 4: NFT
        HYBRID          // 5: Token híbrido
    }
    
    enum TokenStandard {
        ERC20,          // 0
        ERC721,         // 1
        ERC1155,        // 2
        BEP20,          // 3
        SPL             // 4 (Solana - para referência futura)
    }
    
    enum SaleType {
        PRIVATE,        // 0: Venda privada
        PUBLIC,         // 1: Venda pública
        DUTCH_AUCTION,  // 2: Leilão holandês
        BATCH_AUCTION,  // 3: Leilão em lote
        HYBRID_SALE     // 4: Venda híbrida
    }
    
    struct TokenConfig {
        string name;                // Nome do token
        string symbol;              // Símbolo do token
        uint8 decimals;             // Casas decimais (0-18)
        uint256 maxSupply;          // Supply máximo
        uint256 initialSupply;      // Supply inicial
        TokenType tokenType;        // Tipo do token
        TokenStandard standard;     // Padrão do token
        address owner;              // Dono do token
        bool isTransferable;        // Se é transferível
        bool isMintable;            // Se pode mintar mais
        bool isBurnable;            // Se pode queimar
        bool isPausable;            // Se pode pausar
        bool hasStaking;            // Tem staking
        bool hasVoting;             // Tem votação
        uint256 creationFee;        // Taxa de criação
        uint256 transferFee;        // Taxa de transferência (basis points)
        uint256 cashbackRate;       // Cashback (basis points)
    }
    
    struct SaleConfig {
        address token;              // Endereço do token
        SaleType saleType;          // Tipo de venda
        uint256 pricePerToken;      // Preço por token (em wei)
        uint256 tokensForSale;      // Tokens para venda
        uint256 softCap;            // Limite mínimo
        uint256 hardCap;            // Limite máximo
        uint256 startTime;          // Início da venda
        uint256 endTime;            // Fim da venda
        uint256 minPurchase;        // Compra mínima
        uint256 maxPurchase;        // Compra máxima
        address fundWallet;         // Carteira para receber fundos
        bool isWhitelisted;         // Se requer whitelist
        bool isVestingEnabled;      // Se tem vesting
        uint256 vestingCliff;       // Cliff do vesting
        uint256 vestingDuration;    // Duração do vesting
    }
    
    struct TokenInfo {
        address tokenAddress;       // Endereço do token
        string name;                // Nome
        string symbol;              // Símbolo
        TokenType tokenType;        // Tipo
        TokenStandard standard;     // Padrão
        address owner;              // Dono
        uint256 createdAt;          // Data de criação
        bool isVerified;            // Se foi verificado
        bool isActive;              // Se está ativo
        uint256 totalSupply;        // Supply total
    }
    
    struct SaleInfo {
        address saleAddress;        // Endereço da venda
        address tokenAddress;       // Endereço do token
        SaleType saleType;          // Tipo de venda
        uint256 pricePerToken;      // Preço por token
        uint256 tokensSold;         // Tokens vendidos
        uint256 fundsRaised;        // Fundos arrecadados
        uint256 startTime;          // Início
        uint256 endTime;            // Fim
        bool isActive;              // Se está ativa
        bool isSuccessful;          // Se foi bem-sucedida
        bool isWhitelisted;         // Se tem whitelist
    }
    
    // ==============================
    // EVENTS
    // ==============================
    
    event TokenCreated(
        uint256 indexed tokenId,
        address indexed tokenAddress,
        string name,
        string symbol,
        TokenType tokenType,
        address owner,
        uint256 createdAt
    );
    
    event SaleCreated(
        uint256 indexed saleId,
        address indexed saleAddress,
        address indexed tokenAddress,
        SaleType saleType,
        uint256 pricePerToken,
        uint256 startTime,
        uint256 endTime,
        address creator
    );
    
    event TokenVerified(
        address indexed tokenAddress,
        address indexed verifier,
        uint256 verifiedAt
    );
    
    event TokenPaused(
        address indexed tokenAddress,
        address indexed pauser,
        uint256 pausedAt
    );
    
    event TokenUnpaused(
        address indexed tokenAddress,
        address indexed unpauser,
        uint256 unpausedAt
    );
    
    event FactoryFeeUpdated(
        uint256 oldFee,
        uint256 newFee,
        address indexed updater
    );
    
    event TreasuryUpdated(
        address oldTreasury,
        address newTreasury,
        address indexed updater
    );
    
    event TokenTransferred(
        address indexed oldOwner,
        address indexed newOwner,
        address tokenAddress,
        uint256 transferredAt
    );
    
    // ==============================
    // TOKEN CREATION FUNCTIONS
    // ==============================
    
    /**
     * @dev Cria um novo token ERC20
     * @param config Configuração do token
     * @return tokenAddress Endereço do token criado
     */
    function createERC20Token(
        TokenConfig memory config
    ) external payable returns (address tokenAddress);
    
    /**
     * @dev Cria um novo token ERC721 (NFT)
     * @param name Nome do NFT
     * @param symbol Símbolo do NFT
     * @param baseURI URI base para metadados
     * @param maxSupply Supply máximo
     * @param isSoulbound Se é soulbound (não transferível)
     * @return tokenAddress Endereço do NFT criado
     */
    function createERC721Token(
        string memory name,
        string memory symbol,
        string memory baseURI,
        uint256 maxSupply,
        bool isSoulbound
    ) external payable returns (address tokenAddress);
    
    /**
     * @dev Cria um novo token ERC1155 (Multi-token)
     * @param uri URI para metadados
     * @return tokenAddress Endereço do token criado
     */
    function createERC1155Token(
        string memory uri
    ) external payable returns (address tokenAddress);
    
    /**
     * @dev Cria token com template personalizado
     * @param templateId ID do template
     * @param name Nome do token
     * @param symbol Símbolo do token
     * @param parameters Parâmetros personalizados
     * @return tokenAddress Endereço do token criado
     */
    function createCustomToken(
        uint256 templateId,
        string memory name,
        string memory symbol,
        bytes memory parameters
    ) external payable returns (address tokenAddress);
    
    // ==============================
    // SALE CREATION FUNCTIONS
    // ==============================
    
    /**
     * @dev Cria uma venda de tokens
     * @param config Configuração da venda
     * @return saleAddress Endereço da venda criada
     */
    function createTokenSale(
        SaleConfig memory config
    ) external returns (address saleAddress);
    
    /**
     * @dev Cria um leilão holandês
     * @param config Configuração do leilão
     * @param startPrice Preço inicial
     * @param endPrice Preço final
     * @param priceDropRate Taxa de queda de preço
     * @return saleAddress Endereço do leilão criado
     */
    function createDutchAuction(
        SaleConfig memory config,
        uint256 startPrice,
        uint256 endPrice,
        uint256 priceDropRate
    ) external returns (address saleAddress);
    
    /**
     * @dev Cria uma venda com vesting
     * @param config Configuração da venda
     * @param vestingSchedule Cronograma de vesting
     * @return saleAddress Endereço da venda criada
     */
    function createVestingSale(
        SaleConfig memory config,
        uint256[] memory vestingSchedule
    ) external returns (address saleAddress);
    
    // ==============================
    // ADMIN FUNCTIONS
    // ==============================
    
    /**
     * @dev Atualiza a taxa de criação da fábrica
     * @param newFee Nova taxa em wei
     */
    function updateCreationFee(uint256 newFee) external;
    
    /**
     * @dev Atualiza o endereço do tesouro
     * @param newTreasury Novo endereço do tesouro
     */
    function updateTreasury(address newTreasury) external;
    
    /**
     * @dev Pausa um token (apenas admin ou owner)
     * @param tokenAddress Endereço do token
     */
    function pauseToken(address tokenAddress) external;
    
    /**
     * @dev Despausa um token (apenas admin ou owner)
     * @param tokenAddress Endereço do token
     */
    function unpauseToken(address tokenAddress) external;
    
    /**
     * @dev Verifica um token (marca como verificado)
     * @param tokenAddress Endereço do token
     */
    function verifyToken(address tokenAddress) external;
    
    /**
     * @dev Transfere ownership de um token
     * @param tokenAddress Endereço do token
     * @param newOwner Novo dono
     */
    function transferTokenOwnership(
        address tokenAddress,
        address newOwner
    ) external;
    
    // ==============================
    // VIEW FUNCTIONS
    // ==============================
    
    /**
     * @dev Retorna informações de um token
     * @param tokenAddress Endereço do token
     * @return tokenInfo Informações do token
     */
    function getTokenInfo(
        address tokenAddress
    ) external view returns (TokenInfo memory tokenInfo);
    
    /**
     * @dev Retorna informações de uma venda
     * @param saleAddress Endereço da venda
     * @return saleInfo Informações da venda
     */
    function getSaleInfo(
        address saleAddress
    ) external view returns (SaleInfo memory saleInfo);
    
    /**
     * @dev Retorna todos os tokens criados
     * @return tokens Array de informações de tokens
     */
    function getAllTokens() external view returns (TokenInfo[] memory tokens);
    
    /**
     * @dev Retorna tokens por owner
     * @param owner Endereço do owner
     * @return tokens Array de tokens do owner
     */
    function getTokensByOwner(
        address owner
    ) external view returns (TokenInfo[] memory tokens);
    
    /**
     * @dev Retorna vendas por token
     * @param tokenAddress Endereço do token
     * @return sales Array de vendas do token
     */
    function getSalesByToken(
        address tokenAddress
    ) external view returns (SaleInfo[] memory sales);
    
    /**
     * @dev Retorna vendas ativas
     * @return sales Array de vendas ativas
     */
    function getActiveSales() external view returns (SaleInfo[] memory sales);
    
    /**
     * @dev Verifica se um token foi criado pela fábrica
     * @param tokenAddress Endereço do token
     * @return isFactoryToken True se foi criado pela fábrica
     */
    function isFactoryToken(
        address tokenAddress
    ) external view returns (bool isFactoryToken);
    
    /**
     * @dev Retorna a taxa de criação atual
     * @return fee Taxa atual em wei
     */
    function getCreationFee() external view returns (uint256 fee);
    
    /**
     * @dev Retorna o endereço do tesouro
     * @return treasury Endereço do tesouro
     */
    function getTreasury() external view returns (address treasury);
    
    /**
     * @dev Retorna estatísticas da fábrica
     * @return totalTokens Número total de tokens criados
     * @return totalSales Número total de vendas criadas
     * @return totalVolume Volume total em wei
     * @return activeTokens Número de tokens ativos
     * @return activeSales Número de vendas ativas
     */
    function getFactoryStats() external view returns (
        uint256 totalTokens,
        uint256 totalSales,
        uint256 totalVolume,
        uint256 activeTokens,
        uint256 activeSales
    );
    
    /**
     * @dev Retorna templates disponíveis
     * @return templateIds Array de IDs de templates
     * @return templateNames Array de nomes de templates
     */
    function getAvailableTemplates() external view returns (
        uint256[] memory templateIds,
        string[] memory templateNames
    );
    
    // ==============================
    // UTILITY FUNCTIONS
    // ==============================
    
    /**
     * @dev Calcula taxa para criar um token
     * @param tokenType Tipo do token
     * @param standard Padrão do token
     * @return fee Taxa calculada em wei
     */
    function calculateCreationFee(
        TokenType tokenType,
        TokenStandard standard
    ) external view returns (uint256 fee);
    
    /**
     * @dev Valida configuração de um token
     * @param config Configuração do token
     * @return isValid True se a configuração é válida
     * @return errorMessage Mensagem de erro se inválida
     */
    function validateTokenConfig(
        TokenConfig memory config
    ) external view returns (bool isValid, string memory errorMessage);
    
    /**
     * @dev Valida configuração de uma venda
     * @param config Configuração da venda
     * @return isValid True se a configuração é válida
     * @return errorMessage Mensagem de erro se inválida
     */
    function validateSaleConfig(
        SaleConfig memory config
    ) external view returns (bool isValid, string memory errorMessage);
}