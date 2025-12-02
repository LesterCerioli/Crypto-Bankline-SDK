pragma solidity ^0.8.20;

import "./BanklineBaseToken.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IBanklineFactory.sol";

/**
 * @title BanklineUtilityToken
 * @dev Production-grade utility token with advanced loyalty, governance, and reward systems
 * @notice Features: Tier-based loyalty, achievement tracking, on-chain governance, referral system
 */
contract BanklineUtilityToken is BanklineBaseToken, ReentrancyGuard {
    using Math for uint256;
    
    // ==============================
    // STRUCTS
    // ==============================
    struct LoyaltyTier {
        bytes32 tierId;
        string name;
        uint256 minBalance;
        uint256 rewardMultiplier;      // basis points (10000 = 1x)
        uint256 feeDiscount;           // basis points
        uint256 votingPowerMultiplier; // basis points
        uint256 referralBonus;         // basis points
        uint256 stakingBoost;          // basis points
        bool isActive;
    }
    
    struct Achievement {
        bytes32 achievementId;
        string name;
        string description;
        uint256 rewardAmount;
        uint256 requiredBalance;
        uint256 requiredTransactions;
        uint256 expirationTime;
        bool isRepeatable;
        bool isActive;
    }
    
    struct UserAchievement {
        bool completed;
        uint256 completedAt;
        uint256 completions;
        uint256 lastRewardClaimed;
    }
    
    struct Proposal {
        uint256 proposalId;
        string title;
        string description;
        bytes callData;
        address targetContract;
        uint256 votingStart;
        uint256 votingEnd;
        uint256 executionDeadline;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool executed;
        bool canceled;
        address proposer;
        uint256 quorumRequired; // basis points
        uint256 minVotingPowerRequired;
    }
    
    struct Vote {
        bool hasVoted;
        uint8 support; // 1 = for, 2 = against, 3 = abstain
        uint256 votingPower;
    }
    
    struct ReferralInfo {
        address referrer;
        uint256 totalReferred;
        uint256 referralRewards;
        uint256 lastReferralAt;
        uint256 referralTier;
    }
    
    struct StakingBoost {
        uint256 multiplier; // basis points
        uint256 expiresAt;
    }
    
    // ==============================
    // STATE VARIABLES
    // ==============================
    LoyaltyTier[] private _loyaltyTiers;
    mapping(bytes32 => uint256) private _tierIndex;
    
    Achievement[] private _achievements;
    mapping(bytes32 => uint256) private _achievementIndex;
    mapping(address => mapping(bytes32 => UserAchievement)) private _userAchievements;
    
    Proposal[] private _proposals;
    mapping(uint256 => mapping(address => Vote)) private _votes;
    mapping(uint256 => uint256) private _proposalSnapshots;
    
    mapping(address => ReferralInfo) private _referralInfo;
    mapping(address => uint256) private _referralCodes;
    mapping(uint256 => address) private _codeToAddress;
    uint256 private _referralCodeCounter;
    
    mapping(address => uint256) private _loyaltyPoints;
    mapping(address => StakingBoost) private _stakingBoosts;
    
    uint256 private _governanceThreshold = 1000 * 10**18; // 1000 tokens to propose
    uint256 private _votingDelay = 1 days;
    uint256 private _votingPeriod = 3 days;
    uint256 private _executionDelay = 1 days;
    uint256 private _quorumNumerator = 400; // 4% quorum (basis points)
    uint256 private _minVotingPower = 100 * 10**18; // 100 tokens minimum to vote
    
    bytes32 private _merkleRoot; // For whitelisted governance
        
    bool private _emergencyPaused;
    uint256 private _emergencyPausedAt;
    address private _emergencyPauser;
        
    mapping(bytes32 => uint256) private _timelocks;
    uint256 private _timelockDuration = 2 days;
        
    mapping(address => uint256) private _lastTierCheck;
    uint256 private _tierCheckCooldown = 1 days;
    
    // ==============================
    // EVENTS
    // ==============================
    event LoyaltyTierAdded(
        bytes32 indexed tierId,
        string name,
        uint256 minBalance,
        uint256 rewardMultiplier,
        uint256 feeDiscount,
        uint256 votingPowerMultiplier
    );
    
    event LoyaltyTierUpdated(
        bytes32 indexed tierId,
        string name,
        uint256 minBalance,
        uint256 rewardMultiplier,
        uint256 feeDiscount
    );
    
    event LoyaltyPointsEarned(
        address indexed user,
        uint256 points,
        string reason,
        bytes32 indexed contextId,
        uint256 timestamp
    );
    
    event LoyaltyPointsSpent(
        address indexed user,
        uint256 points,
        string purpose,
        uint256 timestamp
    );
    
    event TierUpgraded(
        address indexed user,
        bytes32 indexed oldTierId,
        bytes32 indexed newTierId,
        uint256 timestamp
    );
    
    event AchievementCreated(
        bytes32 indexed achievementId,
        string name,
        uint256 rewardAmount,
        uint256 expirationTime,
        bool isRepeatable
    );
    
    event AchievementCompleted(
        address indexed user,
        bytes32 indexed achievementId,
        uint256 rewardAmount,
        uint256 timestamp,
        uint256 completionCount
    );
    
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        uint256 startTime,
        uint256 endTime,
        uint256 quorumRequired
    );
    
    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        uint8 support,
        uint256 votingPower,
        string reason
    );
    
    event ProposalExecuted(
        uint256 indexed proposalId,
        address indexed executor,
        bytes returnData
    );
    
    event ProposalCanceled(
        uint256 indexed proposalId,
        address indexed canceler
    );
    
    event ReferralRegistered(
        address indexed referrer,
        address indexed referred,
        uint256 referralCode,
        uint256 timestamp
    );
    
    event ReferralReward(
        address indexed referrer,
        address indexed referred,
        uint256 rewardAmount,
        uint256 timestamp
    );
    
    event StakingBoostActivated(
        address indexed user,
        uint256 multiplier,
        uint256 duration,
        uint256 expiresAt
    );
    
    event GovernanceThresholdUpdated(
        uint256 oldThreshold,
        uint256 newThreshold,
        address indexed updater
    );
    
    event QuorumUpdated(
        uint256 oldQuorum,
        uint256 newQuorum,
        address indexed updater
    );
    
    event EmergencyPaused(
        address indexed pauser,
        uint256 timestamp,
        string reason
    );
    
    event EmergencyUnpaused(
        address indexed unpauser,
        uint256 timestamp
    );
    
    event TimelockSet(
        bytes32 indexed operationId,
        uint256 executeAfter,
        bytes data
    );
    
    event TimelockExecuted(
        bytes32 indexed operationId,
        address indexed executor,
        bytes data
    );
    
    // ==============================
    // MODIFIERS
    // ==============================
    modifier onlyGovernance() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "UtilityToken: not governance");
        _;
    }
    
    modifier onlyActiveProposal(uint256 proposalId) {
        require(proposalId < _proposals.length, "UtilityToken: invalid proposal");
        Proposal storage proposal = _proposals[proposalId];
        require(!proposal.executed, "UtilityToken: already executed");
        require(!proposal.canceled, "UtilityToken: canceled");
        _;
    }
    
    modifier duringVotingPeriod(uint256 proposalId) {
        Proposal storage proposal = _proposals[proposalId];
        require(block.timestamp >= proposal.votingStart, "UtilityToken: voting not started");
        require(block.timestamp <= proposal.votingEnd, "UtilityToken: voting ended");
        _;
    }
    
    modifier notEmergencyPaused() {
        require(!_emergencyPaused, "UtilityToken: emergency paused");
        _;
    }
    
    modifier withTimelock(bytes32 operationId) {
        require(_timelocks[operationId] == 0, "UtilityToken: operation already queued");
        _timelocks[operationId] = block.timestamp + _timelockDuration;
        emit TimelockSet(operationId, block.timestamp + _timelockDuration, msg.data);
        _;
    }
    
    modifier checkTimelock(bytes32 operationId) {
        require(_timelocks[operationId] > 0, "UtilityToken: operation not queued");
        require(block.timestamp >= _timelocks[operationId], "UtilityToken: timelock not passed");
        delete _timelocks[operationId];
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
        address owner_,
        address factory_
    ) BanklineBaseToken(
        name_,
        symbol_,
        decimals_,
        maxSupply_,
        IBanklineFactory.TokenType.UTILITY,
        owner_,
        factory_
    ) {
        
        _initializeDefaultTiers();
        
        
        _generateReferralCode(owner_);
    }
    
    // ==============================
    // EMERGENCY CONTROLS
    // ==============================
    function emergencyPause(string memory reason) external onlyGovernance {
        require(!_emergencyPaused, "UtilityToken: already paused");
        _emergencyPaused = true;
        _emergencyPausedAt = block.timestamp;
        _emergencyPauser = msg.sender;
        
        emit EmergencyPaused(msg.sender, block.timestamp, reason);
    }
    
    function emergencyUnpause() external onlyGovernance {
        require(_emergencyPaused, "UtilityToken: not paused");
        _emergencyPaused = false;
        
        emit EmergencyUnpaused(msg.sender, block.timestamp);
    }
    
    function isEmergencyPaused() external view returns (bool) {
        return _emergencyPaused;
    }
    
    // ==============================
    // LOYALTY SYSTEM (OPTIMIZED)
    // ==============================
    function _initializeDefaultTiers() private {
        
        _addLoyaltyTier(
            keccak256("BRONZE"),
            "Bronze",
            100 * 10**decimals(),
            10000, 
            0,     
            10000, 
            500,   
            10000  
        );
        
        
        _addLoyaltyTier(
            keccak256("SILVER"),
            "Silver",
            1000 * 10**decimals(),
            11000, 
            100,   
            11000, 
            1000,  
            11000  
        );
        
        
        _addLoyaltyTier(
            keccak256("GOLD"),
            "Gold",
            10000 * 10**decimals(),
            12500, 
            250,   
            12500, 
            1500,  
            12500  
        );
        
        
        _addLoyaltyTier(
            keccak256("PLATINUM"),
            "Platinum",
            50000 * 10**decimals(),
            15000, 
            500,   
            15000, 
            2000,  
            15000  
        );
    }
    
    function _addLoyaltyTier(
        bytes32 tierId,
        string memory name,
        uint256 minBalance,
        uint256 rewardMultiplier,
        uint256 feeDiscount,
        uint256 votingPowerMultiplier,
        uint256 referralBonus,
        uint256 stakingBoost
    ) private {
        require(_tierIndex[tierId] == 0, "UtilityToken: tier already exists");
        require(rewardMultiplier >= 10000, "UtilityToken: multiplier too low");
        require(feeDiscount <= 10000, "UtilityToken: discount too high");
        
        _loyaltyTiers.push(LoyaltyTier({
            tierId: tierId,
            name: name,
            minBalance: minBalance,
            rewardMultiplier: rewardMultiplier,
            feeDiscount: feeDiscount,
            votingPowerMultiplier: votingPowerMultiplier,
            referralBonus: referralBonus,
            stakingBoost: stakingBoost,
            isActive: true
        }));
        
        _tierIndex[tierId] = _loyaltyTiers.length;
        
        emit LoyaltyTierAdded(
            tierId,
            name,
            minBalance,
            rewardMultiplier,
            feeDiscount,
            votingPowerMultiplier
        );
    }
    
    function addLoyaltyTier(
        bytes32 tierId,
        string memory name,
        uint256 minBalance,
        uint256 rewardMultiplier,
        uint256 feeDiscount,
        uint256 votingPowerMultiplier,
        uint256 referralBonus,
        uint256 stakingBoost
    ) external onlyGovernance {
        _addLoyaltyTier(
            tierId,
            name,
            minBalance,
            rewardMultiplier,
            feeDiscount,
            votingPowerMultiplier,
            referralBonus,
            stakingBoost
        );
    }
    
    function updateLoyaltyTier(
        bytes32 tierId,
        string memory name,
        uint256 minBalance,
        uint256 rewardMultiplier,
        uint256 feeDiscount,
        uint256 votingPowerMultiplier,
        uint256 referralBonus,
        uint256 stakingBoost,
        bool isActive
    ) external onlyGovernance withTimelock(keccak256(abi.encodePacked("updateTier", tierId))) {
        uint256 index = _tierIndex[tierId];
        require(index > 0, "UtilityToken: tier not found");
        index--; 
        
        LoyaltyTier storage tier = _loyaltyTiers[index];
        tier.name = name;
        tier.minBalance = minBalance;
        tier.rewardMultiplier = rewardMultiplier;
        tier.feeDiscount = feeDiscount;
        tier.votingPowerMultiplier = votingPowerMultiplier;
        tier.referralBonus = referralBonus;
        tier.stakingBoost = stakingBoost;
        tier.isActive = isActive;
        
        emit LoyaltyTierUpdated(
            tierId,
            name,
            minBalance,
            rewardMultiplier,
            feeDiscount
        );
    }
    
    function earnLoyaltyPoints(
        address user,
        uint256 points,
        string memory reason,
        bytes32 contextId
    ) external onlyRole(FEE_MANAGER_ROLE) {
        require(user != address(0), "UtilityToken: zero address");
        require(points > 0, "UtilityToken: points must be > 0");
        
        _loyaltyPoints[user] += points;
        
        
        if (block.timestamp >= _lastTierCheck[user] + _tierCheckCooldown) {
            _checkAndUpgradeTier(user);
            _lastTierCheck[user] = block.timestamp;
        }
        
        emit LoyaltyPointsEarned(user, points, reason, contextId, block.timestamp);
    }
    
    function spendLoyaltyPoints(
        uint256 points,
        string memory purpose
    ) external nonReentrant {
        require(_loyaltyPoints[msg.sender] >= points, "UtilityToken: insufficient points");
        require(points > 0, "UtilityToken: points must be > 0");
        
        _loyaltyPoints[msg.sender] -= points;
        
        emit LoyaltyPointsSpent(msg.sender, points, purpose, block.timestamp);
    }
    
    function redeemLoyaltyPointsForTokens(uint256 points) external nonReentrant {
        require(_loyaltyPoints[msg.sender] >= points, "UtilityToken: insufficient points");
                
        uint256 tokenAmount = points / 100;
        require(tokenAmount > 0, "UtilityToken: minimum 100 points required");
        
        uint256 pointsToSpend = tokenAmount * 100;
        _loyaltyPoints[msg.sender] -= pointsToSpend;
                
        _mint(msg.sender, tokenAmount);
        
        emit LoyaltyPointsSpent(msg.sender, pointsToSpend, "token_redeem", block.timestamp);
    }
    
    function _checkAndUpgradeTier(address user) private {
        uint256 balance = balanceOf(user);
        bytes32 currentTierId = _getUserTierId(user);

        bytes32 newTierId = _calculateTierForBalance(balance);
        if (newTierId != currentTierId && newTierId != bytes32(0)) {
            _updateTierCache(user, newTierId, balance);
            emit TierUpgraded(user, currentTierId, newTierId, block.timestamp);
        } else if (newTierId == currentTierId) {
            _updateTierCache(user, newTierId, balance);
        }
    }
    
    function _calculateTierForBalance(uint256 balance) private view returns (bytes32) {
        
        for (uint256 i = _loyaltyTiers.length; i > 0; i--) {
            uint256 index = i - 1;
            LoyaltyTier memory tier = _loyaltyTiers[index];
            if (tier.isActive && balance >= tier.minBalance) {
                return tier.tierId;
            }
        }
        
        return bytes32(0);
    }
    
    function _getUserTierId(address user) private view returns (bytes32) {
        
        if (block.timestamp < _lastTierCheck[user] + _tierCheckCooldown) {
            if (_isBalanceWithinTolerance(currentBalance, cache.cachedBalance)) {
                return cache.tierId;
            }
            if (cache.tierId != bytes32(0)) {
                uint256 tierIndex = _tierIndex[cache.tierId] - 1;
                LoyaltyTier memory cacheTier = _loyaltyTiers[tierIndex];
                if (currentBalance >= bytes32(0)) {
                    uint256 tierIndex = _tierIndex[cache.tierId] - 1;
                    LoyaltyTier memory cachedTier = _loyaltyTiers[tierIndex];

                    if (currentBalance >= cachedTier.minBalance) {
                        bytes32 calculatedTier = _calculateTierForBalance(currentBalance);
                        if (calculatedTier == cache.tierId) {
                            return cache.tierId;
                        }
                    }

                }
            }
            bytes32 newTierId = _calculateTierForBalance(currentBalance);
            return newTierId;
        }
        
        uint256 balance = balanceOf(user);
        return _calculateTierForBalance(balance);
    }
    function _updateTierCache(address user, bytes32 tierId, uint256 balance) private {
        _tierCache[user] = TierCache({
            tierId: tierId,
            cachedAt: block.timestamp,
            cachedBalance: balance
        });
    }
    function _isBalanceWithinTolerance(uint256 currentBalance, uint256 cachedBalance) 
        private 
        pure 
        returns (bool) 
    {
        if (cachedBalance == 0) return false;
        uint256 tolerance = cachedBalance / 100;
        uint256 minBalance = cachedBalance > tolerance ? cachedBalance - tolerance : 0;
        uint256 maxBalance = cachedBalance + tolerance;

        return currentBalance >= minBalance && currentBalance <= maxBalance;
    }
    
    function getUserTierInfo(address user) 
        external 
        view 
        returns (
            bytes32 tierId,
            string memory tierName,
            uint256 rewardMultiplier,
            uint256 feeDiscount,
            uint256 votingPowerMultiplier,
            uint256 referralBonus,
            uint256 stakingBoost,
            uint256 points
        ) 
    {
        bytes32 userTierId = _getUserTierId(user);
        
        if (userTierId != bytes32(0)) {
            uint256 index = _tierIndex[userTierId] - 1;
            LoyaltyTier memory tier = _loyaltyTiers[index];
            
            tierId = tier.tierId;
            tierName = tier.name;
            rewardMultiplier = tier.rewardMultiplier;
            feeDiscount = tier.feeDiscount;
            votingPowerMultiplier = tier.votingPowerMultiplier;
            referralBonus = tier.referralBonus;
            stakingBoost = tier.stakingBoost;
        } else {
            tierId = bytes32(0);
            tierName = "None";
            rewardMultiplier = 10000;
            feeDiscount = 0;
            votingPowerMultiplier = 10000;
            referralBonus = 0;
            stakingBoost = 10000;
        }
        
        points = _loyaltyPoints[user];
    }
    
    function getLoyaltyTiers() external view returns (LoyaltyTier[] memory) {
        return _loyaltyTiers;
    }
    
    // ==============================
    // ACHIEVEMENT SYSTEM (OPTIMIZED)
    // ==============================
    function createAchievement(
        bytes32 achievementId,
        string memory name,
        string memory description,
        uint256 rewardAmount,
        uint256 requiredBalance,
        uint256 requiredTransactions,
        uint256 expirationTime,
        bool isRepeatable
    ) external onlyGovernance {
        require(_achievementIndex[achievementId] == 0, "UtilityToken: achievement exists");
        
        _achievements.push(Achievement({
            achievementId: achievementId,
            name: name,
            description: description,
            rewardAmount: rewardAmount,
            requiredBalance: requiredBalance,
            requiredTransactions: requiredTransactions,
            expirationTime: expirationTime,
            isRepeatable: isRepeatable,
            isActive: true
        }));
        
        _achievementIndex[achievementId] = _achievements.length;
        
        emit AchievementCreated(
            achievementId,
            name,
            rewardAmount,
            expirationTime,
            isRepeatable
        );
    }
    
    function completeAchievement(
        bytes32 achievementId,
        bytes32[] memory proof
    ) external nonReentrant notEmergencyPaused {
        uint256 index = _achievementIndex[achievementId];
        require(index > 0, "UtilityToken: achievement not found");
        index--;
        
        Achievement storage achievement = _achievements[index];
        require(achievement.isActive, "UtilityToken: inactive achievement");
        require(achievement.expirationTime == 0 || block.timestamp <= achievement.expirationTime,
                "UtilityToken: achievement expired");
        
        
        require(balanceOf(msg.sender) >= achievement.requiredBalance,
                "UtilityToken: insufficient balance");
        
        
        UserAchievement storage userAchievement = _userAchievements[msg.sender][achievementId];
        if (!achievement.isRepeatable) {
            require(!userAchievement.completed, "UtilityToken: already completed");
        }
        
        
        if (proof.length > 0) {
            bytes32 leaf = keccak256(abi.encodePacked(msg.sender, achievementId));
            require(MerkleProof.verify(proof, _merkleRoot, leaf), 
                    "UtilityToken: not whitelisted");
        }
        
        
        userAchievement.completed = true;
        userAchievement.completedAt = block.timestamp;
        userAchievement.completions++;
        userAchievement.lastRewardClaimed = achievement.rewardAmount;
        
        
        if (achievement.rewardAmount > 0) {
            _mint(msg.sender, achievement.rewardAmount);
        }
        
        
        uint256 pointsEarned = achievement.rewardAmount * 10; // 10 points per token
        _loyaltyPoints[msg.sender] += pointsEarned;
        
        emit AchievementCompleted(
            msg.sender,
            achievementId,
            achievement.rewardAmount,
            block.timestamp,
            userAchievement.completions
        );
        
        emit LoyaltyPointsEarned(
            msg.sender,
            pointsEarned,
            "achievement_completion",
            achievementId,
            block.timestamp
        );
    }
    
    
    function getUserAchievementsPaginated(
        address user,
        uint256 offset,
        uint256 limit
    ) external view returns (bytes32[] memory, UserAchievement[] memory) {
        require(limit > 0 && limit <= 100, "UtilityToken: invalid limit");
        
        
        uint256 count = 0;
        uint256 end = Math.min(offset + limit, _achievements.length);
        
        
        for (uint256 i = offset; i < end; i++) {
            bytes32 achievementId = _achievements[i].achievementId;
            if (_userAchievements[user][achievementId].completed) {
                count++;
            }
        }
        
        
        bytes32[] memory achievementIds = new bytes32[](count);
        UserAchievement[] memory achievements = new UserAchievement[](count);
        
        
        uint256 index = 0;
        for (uint256 i = offset; i < end; i++) {
            bytes32 achievementId = _achievements[i].achievementId;
            UserAchievement storage userAchievement = _userAchievements[user][achievementId];
            
            if (userAchievement.completed) {
                achievementIds[index] = achievementId;
                achievements[index] = userAchievement;
                index++;
            }
        }
        
        return (achievementIds, achievements);
    }
    
    function getAchievementInfo(bytes32 achievementId) 
        external 
        view 
        returns (Achievement memory) 
    {
        uint256 index = _achievementIndex[achievementId];
        require(index > 0, "UtilityToken: achievement not found");
        return _achievements[index - 1];
    }
    
    // ==============================
    // GOVERNANCE SYSTEM (SECURE)
    // ==============================
    function propose(
        string memory title,
        string memory description,
        bytes memory callData,
        address targetContract
    ) external notEmergencyPaused returns (uint256) {
        require(balanceOf(msg.sender) >= _governanceThreshold,
                "UtilityToken: insufficient governance power");
        
        uint256 proposalId = _proposals.length;
        
        _proposals.push(Proposal({
            proposalId: proposalId,
            title: title,
            description: description,
            callData: callData,
            targetContract: targetContract,
            votingStart: block.timestamp + _votingDelay,
            votingEnd: block.timestamp + _votingDelay + _votingPeriod,
            executionDeadline: block.timestamp + _votingDelay + _votingPeriod + _executionDelay,
            forVotes: 0,
            againstVotes: 0,
            abstainVotes: 0,
            executed: false,
            canceled: false,
            proposer: msg.sender,
            quorumRequired: _quorumNumerator,
            minVotingPowerRequired: _minVotingPower
        }));
        
        
        uint256 snapshotId = createSnapshot();
        _proposalSnapshots[proposalId] = snapshotId;
        
        emit ProposalCreated(
            proposalId,
            msg.sender,
            title,
            block.timestamp + _votingDelay,
            block.timestamp + _votingDelay + _votingPeriod,
            _quorumNumerator
        );
        
        return proposalId;
    }
    
    function castVote(
        uint256 proposalId,
        uint8 support,
        string memory reason
    ) external duringVotingPeriod(proposalId) notEmergencyPaused {
        require(support >= 1 && support <= 3, "UtilityToken: invalid vote type");
        
        Proposal storage proposal = _proposals[proposalId];
        Vote storage vote = _votes[proposalId][msg.sender];
        
        require(!vote.hasVoted, "UtilityToken: already voted");
        
        
        uint256 snapshotId = _proposalSnapshots[proposalId];
        uint256 baseVotingPower = balanceOfAt(msg.sender, snapshotId);
        
        require(baseVotingPower >= proposal.minVotingPowerRequired,
                "UtilityToken: insufficient voting power");
        
        
        bytes32 tierId = _getUserTierId(msg.sender);
        uint256 votingMultiplier = 10000; // Default
        
        if (tierId != bytes32(0)) {
            uint256 tierIndex = _tierIndex[tierId] - 1;
            votingMultiplier = _loyaltyTiers[tierIndex].votingPowerMultiplier;
        }
        
        uint256 votingPower = (baseVotingPower * votingMultiplier) / 10000;
        
        vote.hasVoted = true;
        vote.support = support;
        vote.votingPower = votingPower;
        
        if (support == 1) {
            proposal.forVotes += votingPower;
        } else if (support == 2) {
            proposal.againstVotes += votingPower;
        } else if (support == 3) {
            proposal.abstainVotes += votingPower;
        }
        
        emit VoteCast(msg.sender, proposalId, support, votingPower, reason);
    }
    
    function executeProposal(uint256 proposalId) 
        external 
        nonReentrant
        onlyActiveProposal(proposalId) 
        notEmergencyPaused
    {
        Proposal storage proposal = _proposals[proposalId];
        
        require(block.timestamp >= proposal.votingEnd, "UtilityToken: voting not ended");
        require(block.timestamp <= proposal.executionDeadline, "UtilityToken: execution deadline passed");
        
        
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;
        uint256 totalSupplyAtSnapshot = totalSupplyAt(_proposalSnapshots[proposalId]);
        uint256 quorum = (totalSupplyAtSnapshot * proposal.quorumRequired) / 10000;
        
        require(totalVotes >= quorum, "UtilityToken: quorum not reached");
        
        
        require(proposal.forVotes > proposal.againstVotes, "UtilityToken: proposal not passed");
        
        
        proposal.executed = true;
        
        (bool success, bytes memory returnData) = proposal.targetContract.call(proposal.callData);
        require(success, "UtilityToken: execution failed");
        
        emit ProposalExecuted(proposalId, msg.sender, returnData);
    }
    
    function cancelProposal(uint256 proposalId) 
        external 
        onlyActiveProposal(proposalId) 
    {
        Proposal storage proposal = _proposals[proposalId];
        
        require(msg.sender == proposal.proposer || hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
                "UtilityToken: not proposer or admin");
        require(block.timestamp < proposal.votingStart, "UtilityToken: voting already started");
        
        proposal.canceled = true;
        
        emit ProposalCanceled(proposalId, msg.sender);
    }
    
    function getProposal(uint256 proposalId) 
        external 
        view 
        returns (Proposal memory) 
    {
        require(proposalId < _proposals.length, "UtilityToken: invalid proposal");
        return _proposals[proposalId];
    }
    
    function getProposalsPaginated(uint256 offset, uint256 limit) 
        external 
        view 
        returns (Proposal[] memory) 
    {
        require(limit > 0 && limit <= 50, "UtilityToken: limit 1-50");
        
        uint256 end = Math.min(offset + limit, _proposals.length);
        uint256 size = end - offset;
        
        Proposal[] memory result = new Proposal[](size);
        for (uint256 i = 0; i < size; i++) {
            result[i] = _proposals[offset + i];
        }
        
        return result;
    }
    
    function getVote(uint256 proposalId, address voter) 
        external 
        view 
        returns (Vote memory) 
    {
        return _votes[proposalId][voter];
    }
    
    // ==============================
    // REFERRAL SYSTEM
    // ==============================
    function _generateReferralCode(address user) private {
        _referralCodeCounter++;
        _referralCodes[user] = _referralCodeCounter;
        _codeToAddress[_referralCodeCounter] = user;
    }
    
    function registerWithReferral(uint256 referralCode) external nonReentrant notEmergencyPaused {
        require(_referralCodes[msg.sender] == 0, "UtilityToken: already registered");
        require(referralCode > 0 && referralCode <= _referralCodeCounter, 
                "UtilityToken: invalid referral code");
        
        address referrer = _codeToAddress[referralCode];
        require(referrer != address(0) && referrer != msg.sender, 
                "UtilityToken: invalid referrer");
        
        
        _generateReferralCode(msg.sender);
        
        
        ReferralInfo storage referrerInfo = _referralInfo[referrer];
        referrerInfo.totalReferred++;
        referrerInfo.lastReferralAt = block.timestamp;
        
        ReferralInfo storage referredInfo = _referralInfo[msg.sender];
        referredInfo.referrer = referrer;
        
        
        bytes32 referrerTier = _getUserTierId(referrer);
        uint256 referralBonus = 0;
        
        if (referrerTier != bytes32(0)) {
            uint256 tierIndex = _tierIndex[referrerTier] - 1;
            referralBonus = _loyaltyTiers[tierIndex].referralBonus;
        }
        
        if (referralBonus > 0) {
            uint256 rewardAmount = (100 * 10**decimals() * referralBonus) / 10000; // 100 tokens base
            _mint(referrer, rewardAmount);
            
            referrerInfo.referralRewards += rewardAmount;
            
            emit ReferralReward(referrer, msg.sender, rewardAmount, block.timestamp);
        }
        
        emit ReferralRegistered(referrer, msg.sender, referralCode, block.timestamp);
    }
    
    function getReferralInfo(address user) 
        external 
        view 
        returns (ReferralInfo memory) 
    {
        return _referralInfo[user];
    }
    
    function getReferralCode(address user) external view returns (uint256) {
        return _referralCodes[user];
    }
    
    // ==============================
    // STAKING BOOST SYSTEM
    // ==============================
    function activateStakingBoost(uint256 duration) external nonReentrant notEmergencyPaused {
        require(duration <= 30 days, "UtilityToken: max 30-day boost");
        
        bytes32 tierId = _getUserTierId(msg.sender);
        uint256 boostMultiplier = 10000; // Default
        
        if (tierId != bytes32(0)) {
            uint256 tierIndex = _tierIndex[tierId] - 1;
            boostMultiplier = _loyaltyTiers[tierIndex].stakingBoost;
        }
        
        _stakingBoosts[msg.sender] = StakingBoost({
            multiplier: boostMultiplier,
            expiresAt: block.timestamp + duration
        });
        
        emit StakingBoostActivated(
            msg.sender,
            boostMultiplier,
            duration,
            block.timestamp + duration
        );
    }
    
    function getStakingBoost(address user) external view returns (StakingBoost memory) {
        return _stakingBoosts[user];
    }
    
    // ==============================
    // FIXED TRANSFER FUNCTION (CRITICAL FIX)
    // ==============================
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override notEmergencyPaused {
        require(from != address(0), "UtilityToken: transfer from zero address");
        require(to != address(0), "UtilityToken: transfer to zero address");
                
        bytes32 tierId = _getUserTierId(from);
        uint256 feeDiscount = 0;
        
        if (tierId != bytes32(0)) {
            uint256 tierIndex = _tierIndex[tierId] - 1;
            feeDiscount = _loyaltyTiers[tierIndex].feeDiscount;
        }
        FeeConfig memory transferFee = _feeConfigs[FeeType.TRANSFER];
        uint256 effectiveFeeRate = transferFee.feeRate;

        if (feeDiscount > 0 && transferFee.isActive && transferFee.feeRate > 0) {
            effectiveFeeRate = transferFee.feeRate - 
                (transferFee.feeRate * feeDiscount) / 10000;
        }
        uint256 originalFeeRate = transferFee.feeRate;
        if (effectiveFeeRate != originalFeeRate) {
            uint256 feeAmount = 0;
            uint256 netAmount = amount;

            if (effectiveFeeRate > 0 && from != address(0) && to != address(0)) {
                feeAmount = (amount * effectiveFeeRate) / 10000;
                netAmount = amount - feeAmount;

                if (feeAmount > 0 && transferFee.feeReceiver != address(0)) {
                    super._transfer(from, transferFee.feeReceiver, feeAmount);
                }
                super._transfer(from, to, netAmount);
            } else {
                super._transfer(from, to, amount);
            }
        } else {
            super._transfer(from, to, amount);
        }
        uint256 fromBalance = balanceOf(from);
        uint256 toBalance = balanceOf(to);

        bytes32 fromNewTier = _calculateTierForBalance(fromBalance);
        bytes32 toNewTier = _calculateTierForBalance(toBalance);

        _updateTierCache(from, fromNewTier, fromBalance);
        _updateTierCache(to, toNewTier, toBalance);

        if (block.timestamp >= _lastTierCheck[from] + _tierCheckCooldown) {
            _checkAndUpgradeTier(from);
            _lastTierCheck[from] = block.timestamp;
        }
        if (block.timestamp >= _lastTierCheck[to] + _tierCheckCooldown) {
            _checkAndUpgradeTier(to);
            _lastTierCheck[to] = block.timestamp;
        }
    }
    
    function calculatePendingRewards(address user) 
        public 
        view 
        override 
        returns (uint256) 
    {
        uint256 baseReward = super.calculatePendingRewards(user);
                
        StakingBoost memory boost = _stakingBoosts[user];
        if (boost.expiresAt > block.timestamp) {
            baseReward = (baseReward * boost.multiplier) / 10000;
        } else {
            
            bytes32 tierId = _getUserTierId(user);
            if (tierId != bytes32(0)) {
                uint256 tierIndex = _tierIndex[tierId] - 1;
                uint256 multiplier = _loyaltyTiers[tierIndex].rewardMultiplier;
                baseReward = (baseReward * multiplier) / 10000;
            }
        }
        
        return baseReward;
    }
    
    // ==============================
    // GOVERNANCE SETTINGS (WITH TIMELOCKS)
    // ==============================
    function updateGovernanceThreshold(uint256 newThreshold) 
        external 
        onlyGovernance 
        withTimelock(keccak256("updateGovThreshold"))
    {
        require(newThreshold > 0, "UtilityToken: threshold must be > 0");
        
        uint256 oldThreshold = _governanceThreshold;
        _governanceThreshold = newThreshold;
        
        emit GovernanceThresholdUpdated(oldThreshold, newThreshold, msg.sender);
    }
    
    function updateQuorum(uint256 newQuorum) 
        external 
        onlyGovernance 
        withTimelock(keccak256("updateQuorum"))
        checkTimelock(keccak256("updateQuorum"))
    {
        require(newQuorum <= 10000, "UtilityToken: quorum too high");
        
        uint256 oldQuorum = _quorumNumerator;
        _quorumNumerator = newQuorum;
        
        emit QuorumUpdated(oldQuorum, newQuorum, msg.sender);
    }
    
    function updateVotingSettings(
        uint256 votingDelay,
        uint256 votingPeriod,
        uint256 executionDelay
    ) external onlyGovernance withTimelock(keccak256("updateVotingSettings")) {
        require(votingDelay <= 7 days, "UtilityToken: voting delay too long");
        require(votingPeriod >= 1 days && votingPeriod <= 14 days, 
                "UtilityToken: invalid voting period");
        require(executionDelay <= 30 days, "UtilityToken: execution delay too long");
        
        _votingDelay = votingDelay;
        _votingPeriod = votingPeriod;
        _executionDelay = executionDelay;
    }
    
    function setMerkleRoot(bytes32 merkleRoot) external onlyGovernance {
        _merkleRoot = merkleRoot;
    }
    
    function setMinVotingPower(uint256 minVotingPower) 
        external 
        onlyGovernance 
        withTimelock(keccak256("setMinVotingPower"))
    {
        _minVotingPower = minVotingPower;
    }
    
    function setTimelockDuration(uint256 newDuration) 
        external 
        onlyGovernance 
        withTimelock(keccak256("setTimelockDuration"))
    {
        require(newDuration >= 1 days && newDuration <= 30 days, 
                "UtilityToken: invalid timelock duration");
        _timelockDuration = newDuration;
    }
    
    // ==============================
    // VIEW FUNCTIONS
    // ==============================
    function getGovernanceSettings() 
        external 
        view 
        returns (
            uint256 governanceThreshold,
            uint256 votingDelay,
            uint256 votingPeriod,
            uint256 executionDelay,
            uint256 quorumNumerator,
            uint256 minVotingPower,
            uint256 timelockDuration
        ) 
    {
        return (
            _governanceThreshold,
            _votingDelay,
            _votingPeriod,
            _executionDelay,
            _quorumNumerator,
            _minVotingPower,
            _timelockDuration
        );
    }
    
    function getLoyaltyPoints(address user) external view returns (uint256) {
        return _loyaltyPoints[user];
    }
    
    function getTimelock(bytes32 operationId) external view returns (uint256) {
        return _timelocks[operationId];
    }
    
    function getEmergencyStatus() external view returns (bool, uint256, address) {
        return (_emergencyPaused, _emergencyPausedAt, _emergencyPauser);
    }
    
    // ==============================
    // BATCH OPERATIONS (GAS OPTIMIZATION)
    // ==============================
    function batchCheckTiers(address[] memory users) external {
        for (uint256 i = 0; i < users.length; i++) {
            if (block.timestamp >= _lastTierCheck[users[i]] + _tierCheckCooldown) {
                _checkAndUpgradeTier(users[i]);
                _lastTierCheck[users[i]] = block.timestamp;
            }
        }
    }
}