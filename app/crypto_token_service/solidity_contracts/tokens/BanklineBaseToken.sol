// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "../interfaces/IBanklineToken.sol";
import "../interfaces/IBanklineFactory.sol";

/**
 * @title BanklineBaseToken
 * @dev Token base do Crypto Bankline com todas as funcionalidades principais
 */
contract BanklineBaseToken is 
    ERC20, 
    AccessControl, 
    Pausable, 
    ERC20Burnable, 
    ERC20Snapshot,
    ERC20Capped,
    IBanklineToken
{
    // ==============================
    // ROLES
    // ==============================
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");
    
    // ==============================
    // STATE VARIABLES
    // ==============================
    uint8 private _decimals;
    IBanklineFactory.TokenType private _tokenType;
    TokenStatus private _tokenStatus;
    
    // Metadata
    address private _tokenOwner;
    uint256 private _createdAt;
    string private _tokenURI;
    
    // Fee Management
    mapping(FeeType => FeeConfig) private _feeConfigs;
    mapping(address => uint256) private _totalFeesPaid;
    
    // Sale Contract Registry
    mapping(address => bool) private _registeredSaleContracts;
    mapping(address => SaleContractInfo) private _saleContractInfo;
    
    // Fee Exemptions
    mapping(address => bool) private _feeExemptions;
    mapping(address => mapping(FeeType => bool)) private _specificFeeExemptions;
    
    // Fee Statistics
    mapping(address => FeeStatistics) private _userFeeStatistics;
    
    // Fee Tiers for dynamic fees
    mapping(FeeType => FeeTier[]) private _feeTiers;
    
    // Staking
    mapping(address => StakeInfo) private _stakes;
    uint256 private _totalStaked;
    uint256 public constant MAX_STAKE_PERIOD = 365 days;
    
    // Vesting
    mapping(address => VestingSchedule) private _vestingSchedules;
    
    // Compliance & Security
    mapping(address => bool) private _blacklist;
    mapping(address => uint256) private _frozenBalances;
    
    // Snapshots
    mapping(uint256 => TokenSnapshot) private _snapshots;
    uint256 private _currentSnapshotId;
    
    // Dividends
    uint256 private _totalDividendsDistributed;
    mapping(address => uint256) private _lastDividendClaim;
    mapping(address => uint256) private _dividendCredits;
    
    // Holders tracking
    address[] private _holders;
    mapping(address => bool) private _isHolder;
    
    // ==============================
    // STRUCTS
    // ==============================
    struct SaleContractInfo {
        bool isRegistered;
        uint256 registeredAt;
        address registrar;
        bool isActive;
        SaleType saleType;
    }
    
    struct FeeStatistics {
        uint256 totalBuyFees;
        uint256 totalSellFees;
        uint256 totalTransferFees;
        uint256 totalCashbackDistributed;
        uint256 totalStakingRewards;
    }
    
    struct FeeTier {
        uint256 minTransactionAmount;
        uint256 feeRate;
    }
    
    // ==============================
    // CASHBACK DISTRIBUTION
    // ==============================
    function distributeCashback(
        address[] memory holders,
        uint256[] memory amounts
    ) external override onlyRole(FEE_MANAGER_ROLE) {
        require(holders.length == amounts.length, 
                "BanklineToken: arrays length mismatch");
        
        FeeConfig memory config = _feeConfigs[FeeType.CASHBACK];
        require(config.isActive, "BanklineToken: cashback not active");
        
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            uint256 amount = amounts[i];
            
            if (amount > 0 && balanceOf(holder) > 0) {
                _mint(holder, amount);
                emit CashbackDistributed(holder, amount, block.timestamp);
                                
                FeeStatistics storage stats = _userFeeStatistics[holder];
                stats.totalCashbackDistributed += amount;
            }
        }
    }
    
    /**
     * @dev Applies automatic cashback to holders during transfers
     * @param to Recipient of the transfer
     * @param amount Amount transferred
     */
    function _applyAutoCashback(address to, uint256 amount) private {
        FeeConfig memory cashbackConfig = _feeConfigs[FeeType.CASHBACK];
        
        if (!cashbackConfig.isActive || cashbackConfig.feeRate == 0) {
            return;
        }
        
        
        uint256 recipientBalance = balanceOf(to);
                
        if (recipientBalance > 0) {
            uint256 cashbackAmount = (amount * cashbackConfig.feeRate) / 10000;
            
            if (cashbackAmount > 0) {
                // Check if there's available supply
                if (totalSupply() + cashbackAmount <= cap()) {
                    _mint(to, cashbackAmount);
                    
                    // Update fee statistics
                    FeeStatistics storage stats = _userFeeStatistics[to];
                    stats.totalCashbackDistributed += cashbackAmount;
                    
                    emit CashbackDistributed(to, cashbackAmount, block.timestamp);
                }
            }
        }
    }
    
    // ==============================
    // MODIFIERS
    // ==============================
    modifier notBlacklisted(address account) {
        require(!_blacklist[account], "BanklineToken: account is blacklisted");
        _;
    }
    
    modifier notPaused() {
        require(!paused(), "BanklineToken: token transfers are paused");
        _;
    }
    
    modifier onlyTokenOwner() {
        require(msg.sender == _tokenOwner, "BanklineToken: caller is not token owner");
        _;
    }
    
    // ==============================
    // CONSTRUCTOR
    // ==============================
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 maxSupply_,
        IBanklineFactory.TokenType tokenType_,
        address owner_,
        address factory_
    ) ERC20(name_, symbol_) ERC20Capped(maxSupply_ * 10 ** decimals_) {
        _decimals = decimals_;
        _tokenType = tokenType_;
        _tokenOwner = owner_;
        _createdAt = block.timestamp;
        _tokenStatus = TokenStatus.ACTIVE;
                
        _grantRole(DEFAULT_ADMIN_ROLE, owner_);
        _grantRole(MINTER_ROLE, owner_);
        _grantRole(PAUSER_ROLE, owner_);
        _grantRole(SNAPSHOT_ROLE, owner_);
        _grantRole(FEE_MANAGER_ROLE, owner_);
        _grantRole(COMPLIANCE_ROLE, owner_);
                
        _grantRole(MINTER_ROLE, factory_);
        
        
        _initializeDefaultFees();
                
        uint256 initialSupply = (maxSupply_ * 10 ** decimals_) / 2; // 50% initial
        _mint(owner_, initialSupply);
        _addHolder(owner_);
    }

     // ==============================
    // REST OF THE CONTRACT...
    // (Staking, Vesting, Compliance, Snapshot, Dividend functions remain the same)
    // ==============================
    
    
    function stakeTokens(uint256 amount, uint256 lockPeriod) external override notPaused {
        require(amount > 0, "BanklineToken: cannot stake 0");
        require(balanceOf(msg.sender) >= amount, "BanklineToken: insufficient balance");
        require(lockPeriod <= MAX_STAKE_PERIOD, "BanklineToken: lock period too long");
        require(lockPeriod >= 7 days, "BanklineToken: minimum lock period is 7 days");
        
        StakeInfo storage stake = _stakes[msg.sender];
                
        _transfer(msg.sender, address(this), amount);
                
        stake.amount += amount;
        stake.stakedAt = block.timestamp;
        stake.lockPeriod = lockPeriod;
        stake.rewardRate = _feeConfigs[FeeType.STAKE_REWARD].feeRate;
        
        _totalStaked += amount;
        
        
        FeeStatistics storage stats = _userFeeStatistics[msg.sender];
        stats.totalStakingRewards = calculatePendingRewards(msg.sender);
        
        emit TokensStaked(
            msg.sender,
            amount,
            lockPeriod,
            stake.rewardRate,
            block.timestamp
        );
    }
    
    function unstakeTokens(uint256 amount) external override {
        StakeInfo storage stake = _stakes[msg.sender];
        require(stake.amount >= amount, "BanklineToken: insufficient staked amount");
        require(
            block.timestamp >= stake.stakedAt + stake.lockPeriod,
            "BanklineToken: lock period not ended"
        );
                
        uint256 reward = calculatePendingRewards(msg.sender);
                
        stake.amount -= amount;
        stake.claimedRewards += reward;
        
        _totalStaked -= amount;
                
        _transfer(address(this), msg.sender, amount);
                
        if (reward > 0) {
            _mint(msg.sender, reward);
        }
        
        emit TokensUnstaked(msg.sender, amount, reward, block.timestamp);
                
        if (stake.amount == 0) {
            delete _stakes[msg.sender];
        }
    }
    
    function calculatePendingRewards(address user) 
        public 
        view 
        override 
        returns (uint256) 
    {
        StakeInfo memory stake = _stakes[user];
        if (stake.amount == 0) return 0;
        
        uint256 stakingDuration = block.timestamp - stake.stakedAt;
        uint256 annualReward = (stake.amount * stake.rewardRate) / 10000;
        uint256 reward = (annualReward * stakingDuration) / 365 days;
        
        return reward;
    }
        
    function _addHolder(address account) private {
        if (!_isHolder[account] && account != address(0)) {
            _isHolder[account] = true;
            _holders.push(account);
        }
    }
    
    function _updateHolderStatus(address account) private {
        if (balanceOf(account) == 0 && _isHolder[account]) {
            _isHolder[account] = false;
        }
    }
        
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Snapshot) whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }
        
    function _mint(address account, uint256 amount) internal virtual override(ERC20, ERC20Capped) {
        super._mint(account, amount);
        _addHolder(account);
    }
        
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    function tokenType() public view override returns (IBanklineFactory.TokenType) {
        return _tokenType;
    }
    
    function tokenOwner() public view override returns (address) {
        return _tokenOwner;
    }
    
    function createdAt() public view override returns (uint256) {
        return _createdAt;
    }
    
    function tokenStatus() public view override returns (TokenStatus) {
        return _tokenStatus;
    }
    
    function maxSupply() public view override returns (uint256) {
        return cap();
    }
        
    function blacklist(address account) external override onlyRole(COMPLIANCE_ROLE) {
        require(!_blacklist[account], "BanklineToken: already blacklisted");
        _blacklist[account] = true;
        
        emit HolderBlacklisted(account, msg.sender, block.timestamp);
    }
    
    function unblacklist(address account) external override onlyRole(COMPLIANCE_ROLE) {
        require(_blacklist[account], "BanklineToken: not blacklisted");
        _blacklist[account] = false;
        
        emit HolderUnblacklisted(account, msg.sender, block.timestamp);
    }
    
    function isBlacklisted(address account) external view override returns (bool) {
        return _blacklist[account];
    }
    
    function pause() external override onlyRole(PAUSER_ROLE) {
        _pause();
        _tokenStatus = TokenStatus.PAUSED;
    }
    
    function unpause() external override onlyRole(PAUSER_ROLE) {
        _unpause();
        _tokenStatus = TokenStatus.ACTIVE;
    }
    
    function isPaused() external view override returns (bool) {
        return paused();
    }
}

    // ==============================
    // FEE CALCULATION FUNCTIONS
    // ==============================
    function calculateTransferFee(
        address from,
        address to,
        uint256 amount
    ) external view override returns (uint256 feeAmount, uint256 netAmount) {
        if (amount == 0) {
            return (0, 0);
        }
                
        FeeType feeType = _determineFeeType(from, to);
                
        bool isExempt = _feeExemptions[from] || _specificFeeExemptions[from][feeType];
        
        if (isExempt) {
            return (0, amount);
        }
                
        uint256 applicableFeeRate = _getApplicableFeeRate(feeType, amount);
        
        if (applicableFeeRate == 0) {
            return (0, amount);
        }
        
        feeAmount = (amount * applicableFeeRate) / 10000;
        netAmount = amount - feeAmount;
    }
    
    /**
     * @dev Determines fee type based on transaction context
     * @param from Sender address
     * @param to Recipient address
     * @return feeType Type of fee to apply
     */
    function _determineFeeType(address from, address to) 
        private 
        view 
        returns (FeeType) 
    {
        
        if (from == address(0)) {
            return FeeType.TRANSFER;
        }
                
        if (to == address(0)) {
            return FeeType.TRANSFER;
        }
        
        bool fromIsSaleContract = _registeredSaleContracts[from] && 
                                 _saleContractInfo[from].isActive;
        bool toIsSaleContract = _registeredSaleContracts[to] && 
                               _saleContractInfo[to].isActive;
        
        
        if (fromIsSaleContract && !toIsSaleContract) {
            return FeeType.BUY;
        }
        
        
        if (!fromIsSaleContract && toIsSaleContract) {
            return FeeType.SELL;
        }
                
        if (fromIsSaleContract && toIsSaleContract) {
            return FeeType.TRANSFER;
        }
                
        return FeeType.TRANSFER;
    }
    
    /**
     * @dev Gets applicable fee rate considering dynamic tiers
     * @param feeType Type of fee
     * @param transactionAmount Transaction amount
     * @return applicableFeeRate Fee rate to apply
     */
    function _getApplicableFeeRate(
        FeeType feeType,
        uint256 transactionAmount
    ) private view returns (uint256 applicableFeeRate) {
        FeeConfig memory config = _feeConfigs[feeType];
        
        if (!config.isActive) {
            return 0;
        }
                
        FeeTier[] memory tiers = _feeTiers[feeType];
        
        if (tiers.length == 0) {
            return config.feeRate;
        }
                
        for (uint256 i = tiers.length; i > 0; i--) {
            if (tiers[i - 1].minTransactionAmount <= transactionAmount) {
                return tiers[i - 1].feeRate;
            }
        }
                
        return config.feeRate;
    }
     // ==============================
    // FEE DISTRIBUTION TO HOLDERS
    // ==============================

    event FeeDistributedToHolder(
        address indexed holder,
        uint256 amount,
        uint256 timestamp
    );
    
    /**
     * @dev Distributes part of collected fees to token holders
     * @param distributionPercentage Percentage to distribute (basis points)
     */
    function distributeFeesToHolders(uint256 distributionPercentage) 
        external 
        onlyRole(FEE_MANAGER_ROLE) 
    {
        require(distributionPercentage <= 10000, 
                "BanklineToken: invalid distribution percentage");
        
        address feeReceiver = _feeConfigs[FeeType.TRANSFER].feeReceiver;
        uint256 totalFees = balanceOf(feeReceiver);
        
        if (totalFees == 0) {
            return;
        }
        
        uint256 distributionAmount = (totalFees * distributionPercentage) / 10000;
                
        uint256 totalSupplyExcludingStaked = totalSupply() - _totalStaked;
        
        if (totalSupplyExcludingStaked == 0) {
            return;
        }
        
        for (uint256 i = 0; i < _holders.length; i++) {
            address holder = _holders[i];
            uint256 holderBalance = balanceOf(holder);
            
            if (holderBalance > 0) {
                uint256 share = (distributionAmount * holderBalance) / totalSupplyExcludingStaked;
                if (share > 0) {
                    _transfer(feeReceiver, holder, share);
                    emit FeeDistributedToHolder(holder, share, block.timestamp);
                }
            }
        }
    }

    // ==============================
    // ENHANCED TRANSFER WITH FEE LOGIC
    // ==============================
    event BuyFeeCharged(
        address indexed buyer,
        address indexed seller,
        uint256 amount,
        uint256 feeAmount,
        uint256 timestamp
    );
    
    event SellFeeCharged(
        address indexed seller,
        address indexed buyer,
        uint256 amount,
        uint256 feeAmount,
        uint256 timestamp
    );
    
    event TransferFeeCharged(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 feeAmount,
        uint256 timestamp
    );
    
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override notBlacklisted(from) notBlacklisted(to) notPaused {
        require(
            balanceOf(from) - _frozenBalances[from] >= amount,
            "BanklineToken: amount exceeds available balance"
        );
                
        FeeType feeType = _determineFeeType(from, to);
                
        bool isExempt = _feeExemptions[from] || _specificFeeExemptions[from][feeType];
        
        uint256 feeAmount = 0;
        uint256 netAmount = amount;
                
        if (!isExempt) {
            uint256 applicableFeeRate = _getApplicableFeeRate(feeType, amount);
            FeeConfig memory config = _feeConfigs[feeType];
            
            if (config.isActive && applicableFeeRate > 0 && 
                from != address(0) && to != address(0) && 
                config.feeReceiver != address(0)) {
                
                feeAmount = (amount * applicableFeeRate) / 10000;
                netAmount = amount - feeAmount;
                
                if (feeAmount > 0) {
                    
                    super._transfer(from, config.feeReceiver, feeAmount);
                    _totalFeesPaid[from] += feeAmount;
                    
                    
                    _updateFeeStatistics(from, feeType, feeAmount);
                    
                    
                    _emitFeeEvent(feeType, from, to, amount, feeAmount);
                }
            }
        }
        
        
        super._transfer(from, to, netAmount);
        
        
        _applyAutoCashback(to, netAmount);
        
        _updateHolderStatus(from);
        _addHolder(to);
    }
    
    /**
     * @dev Emits specific fee event
     */
    function _emitFeeEvent(
        FeeType feeType,
        address from,
        address to,
        uint256 amount,
        uint256 feeAmount
    ) private {
        if (feeType == FeeType.BUY) {
            emit BuyFeeCharged(from, to, amount, feeAmount, block.timestamp);
        } else if (feeType == FeeType.SELL) {
            emit SellFeeCharged(from, to, amount, feeAmount, block.timestamp);
        } else if (feeType == FeeType.TRANSFER) {
            emit TransferFeeCharged(from, to, amount, feeAmount, block.timestamp);
        }
    }



    // ==============================
    // FEE MANAGEMENT FUNCTIONS
    // ==============================
    function _initializeDefaultFees() private {
        
        _feeConfigs[FeeType.TRANSFER] = FeeConfig({
            feeRate: 50,
            feeReceiver: _tokenOwner,
            isActive: true
        });
        
        
        _feeConfigs[FeeType.BUY] = FeeConfig({
            feeRate: 100,
            feeReceiver: _tokenOwner,
            isActive: true
        });
        
        
        _feeConfigs[FeeType.SELL] = FeeConfig({
            feeRate: 200,
            feeReceiver: _tokenOwner,
            isActive: true
        });
        
        
        _feeConfigs[FeeType.CASHBACK] = FeeConfig({
            feeRate: 10,
            feeReceiver: address(0),
            isActive: true
        });
        
        
        _feeConfigs[FeeType.STAKE_REWARD] = FeeConfig({
            feeRate: 1000,
            feeReceiver: address(this),
            isActive: true
        });
    }
    
    function setFee(
        FeeType feeType,
        uint256 feeRate,
        address feeReceiver
    ) external override onlyRole(FEE_MANAGER_ROLE) {
        require(feeRate <= 10000, "BanklineToken: fee rate too high (max 100%)");
        require(feeReceiver != address(0) || feeType == FeeType.CASHBACK, 
                "BanklineToken: invalid fee receiver");
        
        FeeConfig memory oldConfig = _feeConfigs[feeType];
        
        _feeConfigs[feeType] = FeeConfig({
            feeRate: feeRate,
            feeReceiver: feeReceiver,
            isActive: true
        });
        
        emit FeeUpdated(feeType, oldConfig.feeRate, feeRate, feeReceiver, msg.sender);
    }
    
    function getFeeConfig(FeeType feeType) 
        external 
        view 
        override 
        returns (FeeConfig memory) 
    {
        return _feeConfigs[feeType];
    }

    // ==============================
    // FEE STATISTICS
    // ==============================
     /**
     * @dev Returns user fee statistics
     * @param user Address of the user
     * @return stats Fee statistics
     */
    function getUserFeeStatistics(address user) 
        external 
        view 
        returns (FeeStatistics memory) 
    {
        return _userFeeStatistics[user];
    }
    
    /**
     * @dev Updates fee statistics
     * @param payer Address paying the fee
     * @param feeType Type of fee
     * @param feeAmount Fee amount
     */
    function _updateFeeStatistics(
        address payer,
        FeeType feeType,
        uint256 feeAmount
    ) private {
        FeeStatistics storage stats = _userFeeStatistics[payer];
        
        if (feeType == FeeType.BUY) {
            stats.totalBuyFees += feeAmount;
        } else if (feeType == FeeType.SELL) {
            stats.totalSellFees += feeAmount;
        } else if (feeType == FeeType.TRANSFER) {
            stats.totalTransferFees += feeAmount;
        }
    }




    // ==============================
    // DYNAMIC FEE TIERS
    // ==============================
    /**
     * @dev Adds a fee tier
     * @param feeType Type of fee
     * @param minTransactionAmount Minimum transaction amount
     * @param feeRate Fee rate (basis points)
     */
    function addFeeTier(
        FeeType feeType,
        uint256 minTransactionAmount,
        uint256 feeRate
    ) external onlyRole(FEE_MANAGER_ROLE) {
        require(feeRate <= 10000, "BanklineToken: fee rate too high");
        
        _feeTiers[feeType].push(FeeTier({
            minTransactionAmount: minTransactionAmount,
            feeRate: feeRate
        }));
        
        
        _sortFeeTiers(feeType);
    }
    
    /**
     * @dev Returns appropriate fee rate based on transaction amount
     * @param feeType Type of fee
     * @param transactionAmount Transaction amount
     * @return applicableFeeRate Applicable fee rate
     */
    function getDynamicFeeRate(
        FeeType feeType,
        uint256 transactionAmount
    ) external view returns (uint256 applicableFeeRate) {
        return _getApplicableFeeRate(feeType, transactionAmount);
    }
    
    /**
     * @dev Sorts fee tiers
     */
    function _sortFeeTiers(FeeType feeType) private {
        FeeTier[] storage tiers = _feeTiers[feeType];
        
        for (uint256 i = 0; i < tiers.length; i++) {
            for (uint256 j = i + 1; j < tiers.length; j++) {
                if (tiers[i].minTransactionAmount > tiers[j].minTransactionAmount) {
                    FeeTier memory temp = tiers[i];
                    tiers[i] = tiers[j];
                    tiers[j] = temp;
                }
            }
        }
    }

    // ==============================
    // SALE CONTRACT REGISTRY
    // ==============================
    event SaleContractRegistered(
        address indexed saleContract,
        address indexed registrar,
        SaleType saleType,
        uint256 timestamp
    );
    
    event SaleContractUnregistered(
        address indexed saleContract,
        address indexed unregistrar,
        uint256 timestamp
    );
    
    /**
     * @dev Registers a sale contract
     * @param saleContract Address of the sale contract
     * @param saleType Type of sale
     */
    function registerSaleContract(
        address saleContract,
        SaleType saleType
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(saleContract != address(0), "BanklineToken: zero address");
        require(!_registeredSaleContracts[saleContract], 
                "BanklineToken: sale contract already registered");
        
        _registeredSaleContracts[saleContract] = true;
        _saleContractInfo[saleContract] = SaleContractInfo({
            isRegistered: true,
            registeredAt: block.timestamp,
            registrar: msg.sender,
            isActive: true,
            saleType: saleType
        });
        
        emit SaleContractRegistered(saleContract, msg.sender, saleType, block.timestamp);
    }
    
    /**
     * @dev Unregisters a sale contract
     * @param saleContract Address of the sale contract
     */
    function unregisterSaleContract(address saleContract) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_registeredSaleContracts[saleContract], 
                "BanklineToken: sale contract not registered");
        
        delete _registeredSaleContracts[saleContract];
        delete _saleContractInfo[saleContract];
        
        emit SaleContractUnregistered(saleContract, msg.sender, block.timestamp);
    }
    
    /**
     * @dev Updates sale contract status
     * @param saleContract Address of the sale contract
     * @param isActive New status
     */
    function updateSaleContractStatus(address saleContract, bool isActive) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(_registeredSaleContracts[saleContract], 
                "BanklineToken: sale contract not registered");
        
        _saleContractInfo[saleContract].isActive = isActive;
    }
    
    /**
     * @dev Checks if an address is a registered sale contract
     * @param contractAddress Address to check
     * @return isSaleContract True if it's a registered sale contract
     */
    function isRegisteredSaleContract(address contractAddress) 
        external 
        view 
        returns (bool) 
    {
        return _registeredSaleContracts[contractAddress] && 
               _saleContractInfo[contractAddress].isActive;
    }
    
    /**
     * @dev Returns sale contract information
     * @param saleContract Address of the contract
     * @return info Contract information
     */
    function getSaleContractInfo(address saleContract) 
        external 
        view 
        returns (SaleContractInfo memory) 
    {
        return _saleContractInfo[saleContract];
    }
    
    /**
     * @dev Batch registers multiple sale contracts
     * @param saleContracts Array of sale contract addresses
     * @param saleTypes Array of sale types
     */
    function batchRegisterSaleContracts(
        address[] memory saleContracts,
        SaleType[] memory saleTypes
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(saleContracts.length == saleTypes.length, 
                "BanklineToken: arrays length mismatch");
        
        for (uint256 i = 0; i < saleContracts.length; i++) {
            if (!_registeredSaleContracts[saleContracts[i]]) {
                _registeredSaleContracts[saleContracts[i]] = true;
                _saleContractInfo[saleContracts[i]] = SaleContractInfo({
                    isRegistered: true,
                    registeredAt: block.timestamp,
                    registrar: msg.sender,
                    isActive: true,
                    saleType: saleTypes[i]
                });
                
                emit SaleContractRegistered(
                    saleContracts[i], 
                    msg.sender, 
                    saleTypes[i], 
                    block.timestamp
                );
            }
        }
    }
    // ==============================
    // FEE EXEMPTIONS
    // ==============================
    /**
     * @dev Sets fee exemption for an address
     * @param account Address of the account
     * @param isExempt Whether the account is exempt
     */
    function setFeeExemption(address account, bool isExempt) 
        external 
        onlyRole(FEE_MANAGER_ROLE) 
    {
        _feeExemptions[account] = isExempt;
    }
    
    /**
     * @dev Sets specific fee exemption
     * @param account Address of the account
     * @param feeType Type of fee
     * @param isExempt Whether the account is exempt
     */
    function setSpecificFeeExemption(
        address account, 
        FeeType feeType, 
        bool isExempt
    ) external onlyRole(FEE_MANAGER_ROLE) {
        _specificFeeExemptions[account][feeType] = isExempt;
    }
    
    /**
     * @dev Checks if an address is exempt from a specific fee
     * @param account Address of the account
     * @param feeType Type of fee
     * @return isExempt True if exempt
     */
    function isFeeExempt(address account, FeeType feeType) 
        external 
        view 
        returns (bool) 
    {
        return _feeExemptions[account] || _specificFeeExemptions[account][feeType];
    }

    
    // ==============================
    // TOKEN METADATA FUNCTIONS
    // ==============================
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    function tokenType() public view override returns (IBanklineFactory.TokenType) {
        return _tokenType;
    }
    
    function tokenOwner() public view override returns (address) {
        return _tokenOwner;
    }
    
    function createdAt() public view override returns (uint256) {
        return _createdAt;
    }
    
    function tokenStatus() public view override returns (TokenStatus) {
        return _tokenStatus;
    }
    
    function maxSupply() public view override returns (uint256) {
        return cap();
    }
    
    
    
    // ==============================
    // STAKING FUNCTIONS
    // ==============================
    function stakeTokens(uint256 amount, uint256 lockPeriod) external override notPaused {
        require(amount > 0, "BanklineToken: cannot stake 0");
        require(balanceOf(msg.sender) >= amount, "BanklineToken: insufficient balance");
        require(lockPeriod <= MAX_STAKE_PERIOD, "BanklineToken: lock period too long");
        require(lockPeriod >= 7 days, "BanklineToken: minimum lock period is 7 days");
        
        StakeInfo storage stake = _stakes[msg.sender];
                
        _transfer(msg.sender, address(this), amount);
                
        stake.amount += amount;
        stake.stakedAt = block.timestamp;
        stake.lockPeriod = lockPeriod;
        stake.rewardRate = _feeConfigs[FeeType.STAKE_REWARD].feeRate;
        
        _totalStaked += amount;
        
        emit TokensStaked(
            msg.sender,
            amount,
            lockPeriod,
            stake.rewardRate,
            block.timestamp
        );
    }
    
    function unstakeTokens(uint256 amount) external override {
        StakeInfo storage stake = _stakes[msg.sender];
        require(stake.amount >= amount, "BanklineToken: insufficient staked amount");
        require(
            block.timestamp >= stake.stakedAt + stake.lockPeriod,
            "BanklineToken: lock period not ended"
        );
                
        uint256 reward = calculatePendingRewards(msg.sender);
                
        stake.amount -= amount;
        stake.claimedRewards += reward;
        
        _totalStaked -= amount;
        
        
        _transfer(address(this), msg.sender, amount);
                
        if (reward > 0) {
            _mint(msg.sender, reward);
        }
        
        emit TokensUnstaked(msg.sender, amount, reward, block.timestamp);
        
        
        if (stake.amount == 0) {
            delete _stakes[msg.sender];
        }
    }
    
    function claimStakingRewards() external override {
        StakeInfo storage stake = _stakes[msg.sender];
        require(stake.amount > 0, "BanklineToken: no staked tokens");
        
        uint256 reward = calculatePendingRewards(msg.sender);
        require(reward > 0, "BanklineToken: no rewards to claim");
        
        stake.claimedRewards += reward;
        stake.stakedAt = block.timestamp; // Reset for next period
        
        _mint(msg.sender, reward);
        
        emit RewardClaimed(msg.sender, reward, block.timestamp);
    }
    
    function getUserStakeInfo(address user) 
        external 
        view 
        override 
        returns (StakeInfo memory) 
    {
        return _stakes[user];
    }
    
    function totalStaked() external view override returns (uint256) {
        return _totalStaked;
    }
    
    function calculatePendingRewards(address user) 
        public 
        view 
        override 
        returns (uint256) 
    {
        StakeInfo memory stake = _stakes[user];
        if (stake.amount == 0) return 0;
        
        uint256 stakingDuration = block.timestamp - stake.stakedAt;
        uint256 annualReward = (stake.amount * stake.rewardRate) / 10000;
        uint256 reward = (annualReward * stakingDuration) / 365 days;
        
        return reward;
    }
    
    // ==============================
    // VESTING FUNCTIONS
    // ==============================
    function createVestingSchedule(
        address beneficiary,
        uint256 amount,
        uint256 startTime,
        uint256 cliff,
        uint256 duration,
        bool isRevocable
    ) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(beneficiary != address(0), "BanklineToken: zero address beneficiary");
        require(amount > 0, "BanklineToken: amount must be > 0");
        require(duration > 0, "BanklineToken: duration must be > 0");
        require(startTime >= block.timestamp, "BanklineToken: start time must be future");
        require(_vestingSchedules[beneficiary].totalAmount == 0, 
                "BanklineToken: beneficiary already has vesting");
        
        
        _transfer(msg.sender, address(this), amount);
        
        _vestingSchedules[beneficiary] = VestingSchedule({
            totalAmount: amount,
            vestedAmount: 0,
            startTime: startTime,
            cliff: cliff,
            duration: duration,
            isRevocable: isRevocable
        });
        
        emit VestingCreated(
            beneficiary,
            amount,
            startTime,
            cliff,
            duration,
            isRevocable
        );
    }
    
    function releaseVestedTokens(address beneficiary) external override {
        VestingSchedule storage schedule = _vestingSchedules[beneficiary];
        require(schedule.totalAmount > 0, "BanklineToken: no vesting schedule");
        
        uint256 releasable = getReleasableAmount(beneficiary);
        require(releasable > 0, "BanklineToken: no tokens to release");
        
        schedule.vestedAmount += releasable;
        
        _transfer(address(this), beneficiary, releasable);
        
        emit VestingReleased(beneficiary, releasable, block.timestamp);
    }
    
    function revokeVestingSchedule(address beneficiary) 
        external 
        override 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        VestingSchedule storage schedule = _vestingSchedules[beneficiary];
        require(schedule.totalAmount > 0, "BanklineToken: no vesting schedule");
        require(schedule.isRevocable, "BanklineToken: vesting not revocable");
        
        uint256 vested = schedule.vestedAmount;
        uint256 revoked = schedule.totalAmount - vested;
                
        if (revoked > 0) {
            _transfer(address(this), msg.sender, revoked);
        }
        
        delete _vestingSchedules[beneficiary];
        
        emit VestingRevoked(beneficiary, revoked, block.timestamp);
    }
    
    function getVestingSchedule(address beneficiary) 
        external 
        view 
        override 
        returns (VestingSchedule memory) 
    {
        return _vestingSchedules[beneficiary];
    }
    
    function getReleasableAmount(address beneficiary) 
        public 
        view 
        override 
        returns (uint256) 
    {
        VestingSchedule memory schedule = _vestingSchedules[beneficiary];
        if (schedule.totalAmount == 0) return 0;
        
        if (block.timestamp < schedule.startTime + schedule.cliff) {
            return 0;
        }
        
        if (block.timestamp >= schedule.startTime + schedule.duration) {
            return schedule.totalAmount - schedule.vestedAmount;
        }
        
        uint256 timeElapsed = block.timestamp - schedule.startTime;
        uint256 vested = (schedule.totalAmount * timeElapsed) / schedule.duration;
        
        if (vested > schedule.totalAmount) {
            vested = schedule.totalAmount;
        }
        
        return vested - schedule.vestedAmount;
    }
    
    // ==============================
    // SNAPSHOT FUNCTIONS
    // ==============================
    function createSnapshot() external override onlyRole(SNAPSHOT_ROLE) returns (uint256) {
        _currentSnapshotId += 1;
        
        _snapshots[_currentSnapshotId] = TokenSnapshot({
            snapshotId: _currentSnapshotId,
            timestamp: block.timestamp,
            totalSupply: totalSupply(),
            circulatingSupply: totalSupply() - _totalStaked
        });
                
        _snapshot();
        
        emit SnapshotCreated(_currentSnapshotId, block.timestamp, totalSupply());
        
        return _currentSnapshotId;
    }
    
    function getSnapshotInfo(uint256 snapshotId) 
        external 
        view 
        override 
        returns (TokenSnapshot memory) 
    {
        return _snapshots[snapshotId];
    }
    
    function balanceOfAt(address account, uint256 snapshotId) 
        public 
        view 
        override 
        returns (uint256) 
    {
        return super.balanceOfAt(account, snapshotId);
    }
    
    function totalSupplyAt(uint256 snapshotId) 
        public 
        view 
        override 
        returns (uint256) 
    {
        return super.totalSupplyAt(snapshotId);
    }
    
    // ==============================
    // COMPLIANCE & SECURITY FUNCTIONS
    // ==============================
    function blacklist(address account) external override onlyRole(COMPLIANCE_ROLE) {
        require(!_blacklist[account], "BanklineToken: already blacklisted");
        _blacklist[account] = true;
        
        emit HolderBlacklisted(account, msg.sender, block.timestamp);
    }
    
    function unblacklist(address account) external override onlyRole(COMPLIANCE_ROLE) {
        require(_blacklist[account], "BanklineToken: not blacklisted");
        _blacklist[account] = false;
        
        emit HolderUnblacklisted(account, msg.sender, block.timestamp);
    }
    
    function isBlacklisted(address account) external view override returns (bool) {
        return _blacklist[account];
    }
    
    function pause() external override onlyRole(PAUSER_ROLE) {
        _pause();
        _tokenStatus = TokenStatus.PAUSED;
    }
    
    function unpause() external override onlyRole(PAUSER_ROLE) {
        _unpause();
        _tokenStatus = TokenStatus.ACTIVE;
    }
    
    function isPaused() external view override returns (bool) {
        return paused();
    }
    // ==============================
    // DIVIDEND STRUCTS AND STATE
    // ==============================
    struct DividendInfo {
        uint256 distributionId;
        uint256 totalAmount;
        uint256 dividendPerToken;
        uint256 snapshotId;
        uint256 declaredAt;
        uint256 claimDeadline;
        bool isActive;
        string description;
    }
    struct HolderDividendInfo {
        uint256 lastProcessedDistributionId;
        uint256 claimableDividends;
        uint256 claimedDividends;
        uint256 lastClaimTimestamp;
    }
    DividendInfo[] private _dividendDistributions;
    uint256 private _currentDistributionId;

    mapping(address => HolderDividendInfo) private _holderDividendInfo;
    mapping(uint256 => mapping(address => bool)) private _hasClaimedDividend;

    mapping(address => uint256) private _claimableDividends;

    // ==============================
    // DIVIDEND EVENTS
    // ==============================
    event DividendDeclared(
        uint256 indexed distributionId,
        uint256 totalAmount,
        uint256 dividendPerToken,
        uint256 snapshotId,
        uint256 declaredAt,
        uint256 claimDeadline,
        string description
    );
    event DividendClaimed(
        address indexed holder,
        uint256 indexed distributionId,
        uint256 amount,
        uint256 timestamp
    );

    event DividendSkipped(
        address indexed holder,
        uint256 indexed distributionId,
        uint256 skippedAmount,
        uint256 timestamp
    );
    event DividendExpired(
         uint256 indexed distributionId,
        uint256 unclaimedAmount,
        uint256 timestamp
    );

    // ==============================
    // DIVIDEND DISTRIBUTION FUNCTIONS
    // ==============================
    function distributeDividends(uint256 amount, string memory description) 
    external 
    override 
    onlyRole(DEFAULT_ADMIN_ROLE) 
{
    require(amount > 0, "BanklineToken: amount must be > 0");
    require(balanceOf(msg.sender) >= amount, "BanklineToken: insufficient balance");
    
    uint256 totalSupplyExcludingStaked = totalSupply() - _totalStaked;
    require(totalSupplyExcludingStaked > 0, "BanklineToken: no circulating supply");
    
    
    _transfer(msg.sender, address(this), amount);
    
    
    uint256 snapshotId = createSnapshot();
    
    
    uint256 dividendPerToken = (amount * 1e18) / totalSupplyExcludingStaked;
    
    
    uint256 distributionId = _currentDistributionId++;
    
    DividendInfo memory newDividend = DividendInfo({
        distributionId: distributionId,
        totalAmount: amount,
        dividendPerToken: dividendPerToken,
        snapshotId: snapshotId,
        declaredAt: block.timestamp,
        claimDeadline: block.timestamp + 90 days, // 90-day claim period
        isActive: true,
        description: description
    });
    
    _dividendDistributions.push(newDividend);
    
    
    _totalDividendsDistributed += amount;
    
    emit DividendDeclared(
        distributionId,
        amount,
        dividendPerToken,
        snapshotId,
        block.timestamp,
        block.timestamp + 90 days,
        description
    );
    
    // Pre-calculate claimable amounts for all holders (optional optimization)
    // This could be done lazily on claim to save gas
}

    // ==============================nal overr
    // DIVIDEND CLAIM FUNCTIONS
    // ==============================
    function claimDivideds() external override {
        _claimDividendsForHolder(msg.sender);
    }
    function claimDividendsFor(address holder) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(holder != address(0), "BanklineToken: zero address");
        _claimDividendsForHolder(holder);

    }
    function _claimDividendsForHolder(address holder) private {
        HolderDividendInfo storage holderInfo = _holderDividendInfo[holder];
        uint256 totalClaimable = 0;

        for (uint256 i = holderInfo.lastProcessedDistributionId; i < _dividendDistributions.length; i++)
        {
            DividendInfo memory distribution = _dividendDistributions[i];
            if (!distribution.isActive || block.timestamp > distribution.claimDeadline) {
                continue;
            }
            if (_hasClaimedDividend[distribution.distributionId][holder]) {
                continue;
            }
            uint256 holderBalanceAtSnapshot = balanceOfAt(holder, distribution.snapshotId);
            if (holderBalanceAtSnapshot == 0) {
                _hasClaimedDividend[distribution.distributionId][holder] = true;
                emit DividendSkipped(holder, distribution.distributionId, 0, block.timestamp);
                continue;
            }
            uint256 dividendAmount = (holderBalanceAtSnapshot * distribution.dividendPerToken) / 1e18;
            if (dividendAmount > 0) {
                totalClaimable += dividendAmount;
                _hasClaimedDividend[distribution.distributionId][holder] = true;
                emit DividendClaimed(holder, distribution.distributionId, dividendAmount, block.timestamp);
            }
        }
        holderInfo.lastProcessedDistributionId = uint32(_dividendDistributions.length);
        require(totalClaimable > 0, "BanklineToken: no dividends to claim");
        holderInfo.claimedDividends += totalClaimable;
        holderInfo.lastClaimTimestamp = block.timestamp;

        _transfer(address(this), holder, totalClaimable);
        _claimableDividends[holder] = 0;
    }

 

    // ==============================
    // DIVIDEND FUNCTIONS
    // ==============================
    function distributeDividends(uint256 amount) external override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount > 0, "BanklineToken: amount must be > 0");
        require(balanceOf(msg.sender) >= amount, "BanklineToken: insufficient balance");
        
        uint256 totalSupplyExcludingStaked = totalSupply() - _totalStaked;
        require(totalSupplyExcludingStaked > 0, "BanklineToken: no circulating supply");
        
        
        _transfer(msg.sender, address(this), amount);
        
        
        uint256 dividendPerToken = (amount * 1e18) / totalSupplyExcludingStaked;
        
        
        _totalDividendsDistributed += amount;
        
        // Store dividend for distribution on claim
        // In a full implementation, you'd track per holder
        
        emit DividendDistributed(_totalDividendsDistributed, amount, block.timestamp);
    }
    
    function claimDividends() external override {
        // Simplified implementation - in production, calculate based on snapshots
        uint256 claimable = getPendingDividends(msg.sender);
        require(claimable > 0, "BanklineToken: no dividends to claim");
        
        _dividendCredits[msg.sender] += claimable;
        _lastDividendClaim[msg.sender] = block.timestamp;
        
        _transfer(address(this), msg.sender, claimable);
        
        emit DividendClaimed(msg.sender, _totalDividendsDistributed, claimable, block.timestamp);
    }
    
    function getPendingDividends(address holder) 
        public 
        view 
        override 
        returns (uint256) 
    {
        // Simplified - in production, use snapshot-based calculation
        uint256 balance = balanceOf(holder);
        if (balance == 0) return 0;
        
        // This is a placeholder - real implementation would track dividends per snapshot
        return 0;
    }
    
    function totalDividendsDistributed() external view override returns (uint256) {
        return _totalDividendsDistributed;
    }

    // ==============================
    // DIVIDEND BATCH OPERATIONS
    // ==============================
    function batchProcessDividendClaims(address[] memory holders) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        for (uint256 i = 0; i < holders.length; i++) {
            address holder = holders[i];
            if (getPendingDividends(holder) > 0) {
                try this._claimDividendsForHolder(holder) {
                    // Successfully claimed
                } catch {
                    // Skip if claim fails
                    continue;
                }

            }
        }

    }
    // ==============================
    // AUTOMATIC DIVIDEND ACCRUAL
    // ==============================
    function _updateDividendCredits(address holder, uint256 amount) private {
         // This function can be called during token transfers to update
        // dividend credits based on token movement
    
        // For simplicity, we're using snapshot-based dividends
        // But this could be extended to support pro-rata daily accrual
    }
    // ==============================
    // DIVIDEND REINVESTMENT
    // ==============================
    function reinvestDividends() external {
        uint256 claimable = getPendingDividends(msg.sender);
        require(claimable > 0, "BanklineToken: no dividends to reinvest");
        _claimDividendsForHolder(msg.sender);
        uint256 tokensToMint = claimable; // Simplified 1:1 rate
        if (totalSupply() + tokensToMint <= cap()) {
            _mint(msg.sender, tokensToMint);
            emit DividendReinvested(msg.sender, claimable, tokensToMint, block.timestamp);
        } else {
            _transfer(address(this), msg.sender, claimable);
        }
    }
    event DividendReinvested(
        address indexed holder,
        uint256 dividendAmount,
        uint256 tokensMinted,
        uint256 timestamp
    );

    // ==============================
    // DIVIDEND STATISTICS
    // ==============================
    function getDividendStatistics() 
        external 
        view 
        return (
            uint256 totalDistributions,
            uint256 activeDistributions,
            uint256 totalDistributedAmount,
            uint256 totalClaimedAmount,
            uint256 totalUnclaimedAmount,
            uint256 averageDividendPerToken
        )
    {
        totalDistributions = _dividendDistributions.length;
        totalDistributedAmount = _totalDividendsDistributed;

        uint256 totalClaimed = 0;
        uint256 activeCount = 0;
        for (uint256 i = 0; i < _dividendDistributions.length; i++)  {
            DividendInfo memory distribution = _dividendDistributions[i];
            if (distribution.isActive) {
                activeCount++;
            }
            // Note: Calculating total claimed would require iterating all holders
            // This is simplified - in production, you'd track this separately
        }
        activeDistributions = activeCount;
        totalClaimedAmount = totalClaimed;
        totalUnclaimedAmount = totalDistributedAmount - totalClaimed;

        if (totalDistributions > 0) {
            averageDividendPerToken = _totalDividendsDistributed / totalDistributions;
        }
        return (
            totalDistributions,
            activeDistributions,
            totalDistributedAmount,
            totalClaimedAmount,
            totalUnclaimedAmount,
            averageDividendPerToken
        )
    }
 
    
    // ==============================
    // ADVANCED FUNCTIONS
    // ==============================
    function mint(address to, uint256 amount) external override onlyRole(MINTER_ROLE) {
        require(to != address(0), "BanklineToken: mint to zero address");
        _mint(to, amount);
        _addHolder(to);
    }
    
    function burn(uint256 amount) external override {
        _burn(msg.sender, amount);
        _updateHolderStatus(msg.sender);
    }
    
    function burnFrom(address account, uint256 amount) external override {
        uint256 currentAllowance = allowance(account, msg.sender);
        require(currentAllowance >= amount, "BanklineToken: burn amount exceeds allowance");
        
        _approve(account, msg.sender, currentAllowance - amount);
        _burn(account, amount);
        _updateHolderStatus(account);
    }
    
    function freeze(address account, uint256 amount) external override onlyRole(COMPLIANCE_ROLE) {
        require(balanceOf(account) >= amount, "BanklineToken: amount exceeds balance");
        _frozenBalances[account] += amount;
    }
    
    function unfreeze(address account, uint256 amount) external override onlyRole(COMPLIANCE_ROLE) {
        require(_frozenBalances[account] >= amount, "BanklineToken: amount exceeds frozen");
        _frozenBalances[account] -= amount;
    }
    
    function frozenBalanceOf(address account) external view override returns (uint256) {
        return _frozenBalances[account];
    }
    
    function updateMetadata(string memory newName, string memory newSymbol) 
        external 
        override 
        onlyTokenOwner 
    {
        // Note: ERC20 doesn't support name/symbol change directly
        // This would require a different approach in production
    }
    // ==============================
    // BATCH DIVIDEND CLAIM
    // ==============================
    function claimMultipleDividends(uint256[] memory distributionIds) external {
        uint256 totalClaimable = 0;
        for (uint256 i = 0; i < distributionIds.length; i++) {
            uint256 distributionId = distributionIds[i];
            require(distributionId < _dividendDistributions.length, 
                "BanklineToken: invalid distribution ID");
            DividendInfo memory distribution = _dividendDistributions[distributionId];
            require(distribution.isActive, "BanklineToken: distribution not active");
            require(block.timestamp <= distribution.claimDeadline, 
                "BanklineToken: claim period expired");

            require(!_hasClaimedDividend[distributionId][msg.sender], 
                "BanklineToken: already claimed");

            uint256 holderBalanceAtSnapshot = balanceOfAt(msg.sender, distribution.snapshotId);
            if (holderBalanceAtSnapshot == 0) {
                _hasClaimedDividend[distributionId][msg.sender] = true;
                emit DividendSkipped(msg.sender, distributionId, 0, block.timestamp);
                continue;
            }
            uint256 dividendAmount = (holderBalanceAtSnapshot * distribution.dividendPerToken) / 1e18;
            if (dividendAmount > 0) {
                totalClaimable += dividendAmount;
                _hasClaimedDividend[distributionId][msg.sender] = true;
            
                emit DividendClaimed(msg.sender, distributionId, dividendAmount, block.timestamp);
            }
        }
        require(totalClaimable > 0, "BanklineToken: no dividends to claim");
        HolderDividendInfo storage holderInfo = _holderDividendInfo[msg.sender];
        holderInfo.claimedDividends += totalClaimable;
        holderInfo.lastClaimTimestamp = block.timestamp;

        uint256 maxDistributionId = distributionIds[distributionIds.length - 1];
        if (maxDistributionId >= holderInfo.lastProcessedDistributionId) {
            holderInfo.lastProcessedDistributionId = uint32(maxDistributionId + 1);
        }
        _transfer(address(this), msg.sender, totalClaimable);
        _claimableDividends[msg.sender] = getPendingDividends(msg.sender);
    }

    // ==============================
    // DIVIDEND VIEW FUNCTIONS
    // ==============================
    function getPendingDividends(address holder) 
        public 
        view 
        override 
        returns (uint256) 
    {
        uint256 totalPending = 0;
        HolderDividendInfo memory holderInfo = _holderDividendInfo[holder];
        uint256 startFrom = holderInfo.lastProcessedDistributionId;
        for (uint256 i = startFrom; i < _dividendDistributions.length; i++) {
            DividendInfo memory distribution = _dividendDistributions[i];
            if (!distribution.isActive || block.timestamp > distribution.claimDeadline) {
                continue;
            }
            if (_hasClaimedDividend[distribution.distributionId][holder]) {
                continue;
            }
            uint256 holderBalanceAtSnapshot = balanceOfAt(holder, distribution.snapshotId);
            if (holderBalanceAtSnapshot > 0) {
                uint256 dividendAmount = (holderBalanceAtSnapshot * distribution.dividendPerToken) / 1e18;
                totalPending += dividendAmount;
            }
        }
        return totalPending;

    }
    function getClaimableDividends(address holder) 
        external 
        view 
        returns (uint256) 

    {
        return _claimableDividends[holder] + getPendingDividends(holder);

    }
    function getHolderDividendInfo(address holder) 
        external 
        view 
        returns (HolderDividendInfo memory) 
    {
        HolderDividendInfo memory info = _holderDividendInfo[holder];
        info.claimableDividends = getPendingDividends(holder);
        return info;

    }
    function getDividendDistribution(uint256 distributionId) 
        external 
        view 
        returns (DividendInfo memory) 
    {
        require(distributionId < _dividendDistributions.length, 
             "BanklineToken: invalid distribution ID");
        return _dividendDistributions[distributionId];

    }
    function getAllDividendDistributions() 
        external 
        view 
        returns (DividendInfo[] memory) 

    {
        return _dividendDistributions;

    }
    function hasClaimedDividend(address holder, uint256 distributionId) 
        external 
        view 
        returns (bool) 
    {
        require(distributionId < _dividendDistributions.length, 
            "BanklineToken: invalid distribution ID");
        return _hasClaimedDividend[distributionId][holder];

    }
    function totalDividendsDistributed() 
        external 
        view 
        override 
        returns (uint256) 
    {
        return _totalDividendsDistributed;

    }

    // ==============================
    // DIVIDEND ADMIN FUNCTIONS
    // ==============================
    function expireDividend(uint256 distributionId) 
        external 
            onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(distributionId < _dividendDistributions.length, 
            "BanklineToken: invalid distribution ID");

        DividendInfo storage distribution = _dividendDistributions[distributionId];
        require(distribution.isActive, "BanklineToken: already expired");
        require(block.timestamp > distribution.claimDeadline, 
            "BanklineToken: claim period not expired");

        distribution.isActive = false;

        uint256 totalClaimed = 0;
        uint256 totalEligible = 0;

        // This calculation could be gas-intensive for many holders
        // Consider alternative approaches for large holder bases

        emit DividendExpired(distributionId, distribution.totalAmount - totalClaimed, block.timestamp);
    }
    function extendClaimDeadline(uint256 distributionId, uint256 newDeadline) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(distributionId < _dividendDistributions.length, 
            "BanklineToken: invalid distribution ID");

        DividendInfo storage distribution = _dividendDistributions[distributionId];
        require(distribution.isActive, "BanklineToken: distribution not active");
        require(newDeadline > distribution.claimDeadline, 
            "BanklineToken: new deadline must be later");
        distribution.claimDeadline = newDeadline;

    }
    function updateDividendDescription(uint256 distributionId, string memory newDescription) 
     external 
        onlyRole(DEFAULT_ADMIN_ROLE)    
    {
        require(distributionId < _dividendDistributions.length, 
            "BanklineToken: invalid distribution ID");

        DividendInfo storage distribution = _dividendDistributions[distributionId];
        distribution.description = newDescription;
        
    }



    // ==============================
    // VIEW FUNCTIONS
    // ==============================
    function getTokenHolders(uint256 limit, uint256 offset) 
        external 
        view 
        override 
        returns (address[] memory holders, uint256[] memory balances) 
    {
        uint256 end = offset + limit;
        if (end > _holders.length) {
            end = _holders.length;
        }
        
        uint256 resultSize = end - offset;
        holders = new address[](resultSize);
        balances = new uint256[](resultSize);
        
        for (uint256 i = 0; i < resultSize; i++) {
            address holder = _holders[offset + i];
            holders[i] = holder;
            balances[i] = balanceOf(holder);
        }
    }
    
    function getTokenStats() 
        external 
        view 
        override 
        returns (
            uint256 holdersCount,
            uint256 totalStakedQuant,
            uint256 totalFrozen,
            uint256 totalDividends,
            uint256 avgHolderBalance
        ) 
    {
        holdersCount = _holders.length;
        totalStakedQuant = _totalStaked;
        
        
        totalFrozen = 0;
        for (uint256 i = 0; i < _holders.length; i++) {
            totalFrozen += _frozenBalances[_holders[i]];
        }
        
        totalDividends = _totalDividendsDistributed;
        
        if (holdersCount > 0) {
            avgHolderBalance = totalSupply() / holdersCount;
        } else {
            avgHolderBalance = 0;
        }
    }
    
    function isHolder(address account) external view override returns (bool) {
        return _isHolder[account] && balanceOf(account) > 0;
    }
    
    function getFeeHistory(address account, uint256 limit) 
        external 
        view 
        override 
        returns (
            uint256[] memory timestamps,
            FeeType[] memory feeTypes,
            uint256[] memory amounts
        ) 
    {
        // Simplified - in production, track fee history
        return (new uint256[](0), new FeeType[](0), new uint256[](0));
    }
    
    // ==============================
    // INTERNAL FUNCTIONS
    // ==============================
    function _mint(address account, uint256 amount) internal virtual override(ERC20, ERC20Capped) {
        super._mint(account, amount);
        _addHolder(account);
    }
    
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override notBlacklisted(from) notBlacklisted(to) notPaused {
        require(
            balanceOf(from) - _frozenBalances[from] >= amount,
            "BanklineToken: amount exceeds available balance"
        );
        
        // Apply transfer fee if active
        FeeConfig memory transferFee = _feeConfigs[FeeType.TRANSFER];
        if (transferFee.isActive && transferFee.feeRate > 0 && from != address(0) && to != address(0)) {
            uint256 feeAmount = (amount * transferFee.feeRate) / 10000;
            uint256 netAmount = amount - feeAmount;
            
            if (feeAmount > 0) {
                super._transfer(from, transferFee.feeReceiver, feeAmount);
                _totalFeesPaid[from] += feeAmount;
            }
            
            super._transfer(from, to, netAmount);
        } else {
            super._transfer(from, to, amount);
        }
        
        _updateHolderStatus(from);
        _addHolder(to);
    }
    
    function _addHolder(address account) private {
        if (!_isHolder[account] && account != address(0)) {
            _isHolder[account] = true;
            _holders.push(account);
        }
    }
    
    function _updateHolderStatus(address account) private {
        if (balanceOf(account) == 0 && _isHolder[account]) {
            _isHolder[account] = false;
            // Note: Removing from _holders array is gas-intensive
            // In production, use a different data structure
        }
    }
    
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Snapshot) whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }
}