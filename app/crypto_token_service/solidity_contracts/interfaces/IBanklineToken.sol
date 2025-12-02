pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IBanklineFactory.sol";

/**
 * @title IBanklineToken
 * @dev Interface para tokens do Crypto Bankline com funcionalidades avançadas
 */
interface IBanklineToken is IERC20 {
    // ==============================
    // ENUMS & STRUCTS
    // ==============================
    
    enum TokenStatus {
        ACTIVE,         
        PAUSED,         
        FROZEN,         
        BLACKLISTED,    
        BURNED          
    }
    
    enum FeeType {
        TRANSFER,       
        BUY,            
        SELL,           
        CASHBACK,       
        STAKE_REWARD    
    }
    
    struct FeeConfig {
        uint256 feeRate;        
        address feeReceiver;    
        bool isActive;          
    }
    
    struct StakeInfo {
        uint256 amount;         
        uint256 stakedAt;       
        uint256 lockPeriod;     
        uint256 rewardRate;     
        uint256 claimedRewards; 
    }
    
    struct VestingSchedule {
        uint256 totalAmount;    
        uint256 vestedAmount;   
        uint256 startTime;      
        uint256 cliff;          
        uint256 duration;       
        bool isRevocable;       
    }
    
    struct TokenSnapshot {
        uint256 snapshotId;     
        uint256 timestamp;      
        uint256 totalSupply;    
        uint256 circulatingSupply; 
    }
    
    // ==============================
    // EVENTS
    // ==============================
    
    event FeeUpdated(
        FeeType feeType,
        uint256 oldRate,
        uint256 newRate,
        address indexed receiver,
        address indexed updater
    );
    
    event TokensStaked(
        address indexed user,
        uint256 amount,
        uint256 lockPeriod,
        uint256 rewardRate,
        uint256 timestamp
    );
    
    event TokensUnstaked(
        address indexed user,
        uint256 amount,
        uint256 reward,
        uint256 timestamp
    );
    
    event RewardClaimed(
        address indexed user,
        uint256 amount,
        uint256 timestamp
    );
    
    event VestingCreated(
        address indexed beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 cliff,
        uint256 duration,
        bool isRevocable
    );
    
    event VestingReleased(
        address indexed beneficiary,
        uint256 amount,
        uint256 timestamp
    );
    
    event VestingRevoked(
        address indexed beneficiary,
        uint256 revokedAmount,
        uint256 timestamp
    );
    
    event SnapshotCreated(
        uint256 indexed snapshotId,
        uint256 timestamp,
        uint256 totalSupply
    );
    
    event CashbackDistributed(
        address indexed holder,
        uint256 amount,
        uint256 timestamp
    );
    
    event HolderBlacklisted(
        address indexed holder,
        address indexed admin,
        uint256 timestamp
    );
    
    event HolderUnblacklisted(
        address indexed holder,
        address indexed admin,
        uint256 timestamp
    );
    
    event DividendDistributed(
        uint256 indexed dividendId,
        uint256 amount,
        uint256 timestamp
    );
    
    event DividendClaimed(
        address indexed holder,
        uint256 indexed dividendId,
        uint256 amount,
        uint256 timestamp
    );
    
    // ==============================
    // TOKEN METADATA
    // ==============================
    
    /**
     * @dev Retorna nome do token
     */
    function name() external view returns (string memory);
    
    /**
     * @dev Retorna símbolo do token
     */
    function symbol() external view returns (string memory);
    
    /**
     * @dev Retorna casas decimais
     */
    function decimals() external view returns (uint8);
    
    /**
     * @dev Retorna supply máximo
     */
    function maxSupply() external view returns (uint256);
    
    /**
     * @dev Retorna status do token
     */
    function tokenStatus() external view returns (TokenStatus);
    
    /**
     * @dev Retorna tipo do token (da factory)
     */
    function tokenType() external view returns (IBanklineFactory.TokenType);
    
    /**
     * @dev Retorna dono do token
     */
    function tokenOwner() external view returns (address);
    
    /**
     * @dev Retorna timestamp de criação
     */
    function createdAt() external view returns (uint256);
    
    // ==============================
    // FEE MANAGEMENT
    // ==============================
    
    /**
     * @dev Configura taxa para um tipo específico
     * @param feeType Tipo da taxa
     * @param feeRate Taxa em basis points
     * @param feeReceiver Receptor da taxa
     */
    function setFee(
        FeeType feeType,
        uint256 feeRate,
        address feeReceiver
    ) external;
    
    /**
     * @dev Retorna configuração de uma taxa
     * @param feeType Tipo da taxa
     * @return feeConfig Configuração da taxa
     */
    function getFeeConfig(
        FeeType feeType
    ) external view returns (FeeConfig memory feeConfig);
    
    /**
     * @dev Calcula taxa para uma transferência
     * @param from Remetente
     * @param to Destinatário
     * @param amount Quantidade
     * @return feeAmount Valor da taxa
     * @return netAmount Valor líquido
     */
    function calculateTransferFee(
        address from,
        address to,
        uint256 amount
    ) external view returns (uint256 feeAmount, uint256 netAmount);
    
    /**
     * @dev Distribui cashback para holders
     * @param holders Array de holders
     * @param amounts Array de amounts
     */
    function distributeCashback(
        address[] memory holders,
        uint256[] memory amounts
    ) external;
    
    // ==============================
    // STAKING FUNCTIONS
    // ==============================
    
    /**
     * @dev Stake tokens
     * @param amount Quantidade para staking
     * @param lockPeriod Período de lock em segundos
     */
    function stakeTokens(uint256 amount, uint256 lockPeriod) external;
    
    /**
     * @dev Unstake tokens
     * @param amount Quantidade para unstake
     */
    function unstakeTokens(uint256 amount) external;
    
    /**
     * @dev Resgata recompensas de staking
     */
    function claimStakingRewards() external;
    
    /**
     * @dev Retorna informações de staking de um usuário
     * @param user Endereço do usuário
     * @return stakeInfo Informações do stake
     */
    function getUserStakeInfo(
        address user
    ) external view returns (StakeInfo memory stakeInfo);
    
    /**
     * @dev Retorna quantidade total staked
     * @return totalStaked Quantidade total staked
     */
    function totalStaked() external view returns (uint256 totalStaked);
    
    /**
     * @dev Calcula recompensas pendentes
     * @param user Endereço do usuário
     * @return pendingRewards Recompensas pendentes
     */
    function calculatePendingRewards(
        address user
    ) external view returns (uint256 pendingRewards);
    
    // ==============================
    // VESTING FUNCTIONS
    // ==============================
    
    /**
     * @dev Cria um schedule de vesting
     * @param beneficiary Beneficiário
     * @param amount Quantidade total
     * @param startTime Início do vesting
     * @param cliff Período de cliff
     * @param duration Duração total
     * @param isRevocable Se é revogável
     */
    function createVestingSchedule(
        address beneficiary,
        uint256 amount,
        uint256 startTime,
        uint256 cliff,
        uint256 duration,
        bool isRevocable
    ) external;
    
    /**
     * @dev Libera tokens vestidos
     * @param beneficiary Beneficiário
     */
    function releaseVestedTokens(address beneficiary) external;
    
    /**
     * @dev Revoga vesting schedule
     * @param beneficiary Beneficiário
     */
    function revokeVestingSchedule(address beneficiary) external;
    
    /**
     * @dev Retorna schedule de vesting
     * @param beneficiary Beneficiário
     * @return vestingSchedule Schedule de vesting
     */
    function getVestingSchedule(
        address beneficiary
    ) external view returns (VestingSchedule memory vestingSchedule);
    
    /**
     * @dev Calcula tokens vestidos disponíveis
     * @param beneficiary Beneficiário
     * @return vestedAmount Quantidade vestida disponível
     */
    function getReleasableAmount(
        address beneficiary
    ) external view returns (uint256 vestedAmount);
    
    // ==============================
    // SNAPSHOT FUNCTIONS
    // ==============================
    
    /**
     * @dev Cria um snapshot do token
     * @return snapshotId ID do snapshot criado
     */
    function createSnapshot() external returns (uint256 snapshotId);
    
    /**
     * @dev Retorna informações de um snapshot
     * @param snapshotId ID do snapshot
     * @return snapshotInfo Informações do snapshot
     */
    function getSnapshotInfo(
        uint256 snapshotId
    ) external view returns (TokenSnapshot memory snapshotInfo);
    
    /**
     * @dev Retorna saldo no snapshot
     * @param account Endereço da conta
     * @param snapshotId ID do snapshot
     * @return balance Saldo no snapshot
     */
    function balanceOfAt(
        address account,
        uint256 snapshotId
    ) external view returns (uint256 balance);
    
    /**
     * @dev Retorna supply total no snapshot
     * @param snapshotId ID do snapshot
     * @return totalSupply Supply total no snapshot
     */
    function totalSupplyAt(
        uint256 snapshotId
    ) external view returns (uint256 totalSupply);
    
    // ==============================
    // COMPLIANCE & SECURITY
    // ==============================
    
    /**
     * @dev Adiciona endereço à blacklist
     * @param account Endereço para blacklist
     */
    function blacklist(address account) external;
    
    /**
     * @dev Remove endereço da blacklist
     * @param account Endereço para remover
     */
    function unblacklist(address account) external;
    
    /**
     * @dev Verifica se endereço está na blacklist
     * @param account Endereço para verificar
     * @return isBlacklisted True se está na blacklist
     */
    function isBlacklisted(address account) external view returns (bool);
    
    /**
     * @dev Pausa todas as transferências
     */
    function pause() external;
    
    /**
     * @dev Despausa todas as transferências
     */
    function unpause() external;
    
    /**
     * @dev Verifica se o token está pausado
     * @return isPaused True se está pausado
     */
    function isPaused() external view returns (bool);
    
    // ==============================
    // DIVIDEND FUNCTIONS
    // ==============================
    
    /**
     * @dev Distribui dividendos para holders
     * @param amount Quantidade para distribuir
     */
    function distributeDividends(uint256 amount) external;
    
    /**
     * @dev Resgata dividendos pendentes
     */
    function claimDividends() external;
    
    /**
     * @dev Retorna dividendos pendentes
     * @param holder Endereço do holder
     * @return pendingDividends Dividendos pendentes
     */
    function getPendingDividends(
        address holder
    ) external view returns (uint256 pendingDividends);
    
    /**
     * @dev Retorna total de dividendos distribuídos
     * @return totalDividends Total distribuído
     */
    function totalDividendsDistributed() external view returns (uint256);
    
    // ==============================
    // ADVANCED FUNCTIONS
    // ==============================
    
    /**
     * @dev Minta novos tokens (apenas owner)
     * @param to Destinatário
     * @param amount Quantidade
     */
    function mint(address to, uint256 amount) external;
    
    /**
     * @dev Queima tokens
     * @param amount Quantidade para queimar
     */
    function burn(uint256 amount) external;
    
    /**
     * @dev Queima tokens de outra conta (com permissão)
     * @param account Conta para queimar tokens
     * @param amount Quantidade para queimar
     */
    function burnFrom(address account, uint256 amount) external;
    
    /**
     * @dev Congela tokens de uma conta
     * @param account Conta para congelar
     * @param amount Quantidade para congelar
     */
    function freeze(address account, uint256 amount) external;
    
    /**
     * @dev Descongela tokens de uma conta
     * @param account Conta para descongelar
     * @param amount Quantidade para descongelar
     */
    function unfreeze(address account, uint256 amount) external;
    
    /**
     * @dev Retorna quantidade congelada
     * @param account Conta para verificar
     * @return frozenAmount Quantidade congelada
     */
    function frozenBalanceOf(address account) external view returns (uint256);
    
    /**
     * @dev Atualiza metadata do token
     * @param newName Novo nome
     * @param newSymbol Novo símbolo
     */
    function updateMetadata(string memory newName, string memory newSymbol) external;
    
    // ==============================
    // VIEW FUNCTIONS
    // ==============================
    
    /**
     * @dev Retorna holders do token
     * @param limit Limite de resultados
     * @param offset Offset para paginação
     * @return holders Array de endereços de holders
     * @return balances Array de saldos correspondentes
     */
    function getTokenHolders(
        uint256 limit,
        uint256 offset
    ) external view returns (address[] memory holders, uint256[] memory balances);
    
    /**
     * @dev Retorna estatísticas do token
     * @return holdersCount Número de holders
     * @return totalStakedQuant Total staked
     * @return totalFrozen Quantidade total congelada
     * @return totalDividends Dividendos totais
     * @return avgHolderBalance Saldo médio por holder
     */
    function getTokenStats() external view returns (
        uint256 holdersCount,
        uint256 totalStakedQuant,
        uint256 totalFrozen,
        uint256 totalDividends,
        uint256 avgHolderBalance
    );
    
    /**
     * @dev Verifica se endereço é holder
     * @param account Endereço para verificar
     * @return isHolder True se é holder
     */
    function isHolder(address account) external view returns (bool);
    
    /**
     * @dev Retorna histórico de taxas pagas
     * @param account Endereço da conta
     * @param limit Limite de transações
     * @return timestamps Array de timestamps
     * @return feeTypes Array de tipos de taxa
     * @return amounts Array de amounts
     */
    function getFeeHistory(
        address account,
        uint256 limit
    ) external view returns (
        uint256[] memory timestamps,
        FeeType[] memory feeTypes,
        uint256[] memory amounts
    );
}