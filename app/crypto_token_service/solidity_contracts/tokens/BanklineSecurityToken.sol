pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "./BanklineBaseToken.sol";
import "../interfaces/IBanklineFactory.sol";

/**
 * @title BanklineSecurityToken
 * @dev Security Token with advanced compliance features for regulated financial instruments
 */
contract BanklineSecurityToken is BanklineBaseToken {
    // ==============================
    // COMPLIANCE STRUCTS
    // ==============================
    struct Investor {
        bool isVerified;
        uint8 accreditationLevel; // 0-3 (0=non-accredited, 1-3=accredited tiers)
        uint256 verifiedAt;
        uint256 verificationExpiry;
        string jurisdiction;
        uint256 maxInvestmentAmount;
        uint256 currentInvestment;
        uint256 investmentLockUntil;
        bool isWhitelisted;
        uint256 whitelistedAt;
    }
    
    struct TransferRestriction {
        uint256 holdingPeriod; // Minimum holding period in seconds
        uint256 maxTransferPercentage; // Basis points (10000 = 100%)
        uint256 dailyTransferLimit;
        uint256 lastTransferDate;
        uint256 dailyTransferredAmount;
        bool requiresApproval;
    }
    
    struct CorporateAction {
        uint256 actionId;
        string actionType; // DIVIDEND, SPLIT, MERGER, BUYBACK
        uint256 recordDate;
        uint256 executionDate;
        uint256 amount;
        bool executed;
        string description;
        bytes32 actionHash;
        uint256 snapshotId;
        address dividendToken; // Address of token used for dividend payments
        uint256 splitRatioNumerator;
        uint256 splitRatioDenominator;
    }
    
    struct DividendDistribution {
        uint256 distributionId;
        uint256 amountDistributed;
        uint256 dividendPerToken;
        uint256 snapshotId;
        uint256 distributedAt;
        address dividendToken;
    }
    
    struct LockupSchedule {
        uint256 totalAmount;
        uint256 releasedAmount;
        uint256 startTime;
        uint256 cliffPeriod;
        uint256 vestingDuration;
        uint256 releaseInterval;
        bool isRevocable;
        address beneficiary;
    }
    
    // ==============================
    // COMPLIANCE STATE VARIABLES
    // ==============================
    mapping(address => Investor) private _investors;
    mapping(address => TransferRestriction) private _transferRestrictions;
    
    CorporateAction[] private _corporateActions;
    DividendDistribution[] private _dividendDistributions;
    mapping(uint256 => mapping(address => bool)) private _dividendClaimed;
    mapping(uint256 => mapping(address => uint256)) private _dividendAmounts;
    
    LockupSchedule[] private _lockupSchedules;
    mapping(address => uint256[]) private _beneficiaryLockups;
    
    address public complianceOfficer;
    address public transferAgent;
    
    uint256 public maxInvestorCount = 2000; // Regulation D limit
    uint256 public minInvestmentAmount = 100 * 10 ** 18; // 100 tokens minimum
    uint256 public maxInvestmentPercentage = 1000; // 10% basis points
    uint256 public holdingPeriod = 90 days; // Default 90-day holding period
    
    bool public onlyAccreditedInvestors = true;
    bool public transfersRestricted = true;
    bool public tradingEnabled = false;
    
    uint256 public totalVerifiedInvestors;
    uint256 public totalLockedTokens;
    
    // ==============================
    // COMPLIANCE EVENTS
    // ==============================
    event InvestorVerified(
        address indexed investor,
        uint8 accreditationLevel,
        uint256 expiryDate,
        string jurisdiction,
        uint256 maxInvestmentAmount,
        address indexed verifier
    );
    
    event InvestorVerificationUpdated(
        address indexed investor,
        uint8 newAccreditationLevel,
        uint256 newExpiryDate,
        address indexed updater
    );
    
    event InvestorRemoved(
        address indexed investor,
        address indexed remover,
        string reason
    );
    
    event TransferRestrictionSet(
        address indexed investor,
        uint256 holdingPeriod,
        uint256 maxTransferPercentage,
        uint256 dailyTransferLimit,
        bool requiresApproval
    );
    
    event TransferApproved(
        address indexed from,
        address indexed to,
        uint256 amount,
        address indexed approver,
        uint256 timestamp
    );
    
    event CorporateActionCreated(
        uint256 indexed actionId,
        string actionType,
        uint256 recordDate,
        uint256 executionDate,
        uint256 amount,
        string description
    );
    
    event CorporateActionExecuted(
        uint256 indexed actionId,
        address indexed executor,
        uint256 timestamp
    );
    
    event DividendDistributed(
        uint256 indexed distributionId,
        uint256 totalAmount,
        uint256 dividendPerToken,
        uint256 snapshotId,
        address dividendToken
    );
    
    event DividendClaimed(
        address indexed holder,
        uint256 indexed distributionId,
        uint256 amount,
        uint256 timestamp
    );
    
    event StockSplitExecuted(
        uint256 indexed actionId,
        uint256 ratioNumerator,
        uint256 ratioDenominator,
        uint256 newTotalSupply
    );
    
    event LockupScheduleCreated(
        uint256 indexed scheduleId,
        address indexed beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 cliffPeriod,
        uint256 vestingDuration,
        bool isRevocable
    );
    
    event TokensReleased(
        uint256 indexed scheduleId,
        address indexed beneficiary,
        uint256 amount,
        uint256 timestamp
    );
    
    event LockupRevoked(
        uint256 indexed scheduleId,
        address indexed revoker,
        uint256 revokedAmount,
        uint256 timestamp
    );
    
    event ComplianceOfficerUpdated(
        address oldOfficer,
        address newOfficer,
        address indexed updater
    );
    
    event TransferAgentUpdated(
        address oldAgent,
        address newAgent,
        address indexed updater
    );
    
    event TradingEnabled(
        address indexed enabler,
        uint256 timestamp
    );
    
    event TradingDisabled(
        address indexed disabler,
        uint256 timestamp
    );
    
    event ApprovalHashCreated(
        bytes32 indexed approvalHash,
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 timestamp
    );
    
    // ==============================
    // MODIFIERS
    // ==============================
    modifier onlyComplianceOfficer() {
        require(msg.sender == complianceOfficer, 
                "SecurityToken: not compliance officer");
        _;
    }
    
    modifier onlyTransferAgent() {
        require(msg.sender == transferAgent, 
                "SecurityToken: not transfer agent");
        _;
    }
    
    modifier onlyVerifiedInvestor(address investor) {
        require(_isInvestorVerified(investor), 
                "SecurityToken: investor not verified");
        _;
    }
    
    modifier tradingAllowed() {
        require(tradingEnabled || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), 
                "SecurityToken: trading not enabled");
        _;
    }
    
    modifier withinInvestmentLimits(address investor, uint256 amount) {
        _checkInvestmentLimits(investor, amount);
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
        IBanklineFactory.TokenType.SECURITY,
        owner_,
        factory_
    ) {
        complianceOfficer = owner_;
        transferAgent = owner_;
        
        _initializeComplianceParameters();
    }
    
    function _initializeComplianceParameters() private {
        onlyAccreditedInvestors = true;
        transfersRestricted = true;
        tradingEnabled = false;
        maxInvestorCount = 2000;
        minInvestmentAmount = 100 * 10 ** decimals();
        maxInvestmentPercentage = 1000;
        holdingPeriod = 90 days;
    }
    
    // ==============================
    // INVESTOR MANAGEMENT
    // ==============================
    function verifyInvestor(
        address investor,
        uint8 accreditationLevel,
        uint256 expiryDate,
        string memory jurisdiction,
        uint256 maxInvestmentAmount
    ) external onlyComplianceOfficer {
        require(investor != address(0), "SecurityToken: zero address investor");
        require(accreditationLevel <= 3, "SecurityToken: invalid accreditation level");
        require(expiryDate > block.timestamp, "SecurityToken: expiry must be future");
        require(maxInvestmentAmount > 0, "SecurityToken: max investment must be > 0");
        
        if (!_investors[investor].isVerified) {
            totalVerifiedInvestors++;
        }
        
        _investors[investor] = Investor({
            isVerified: true,
            accreditationLevel: accreditationLevel,
            verifiedAt: block.timestamp,
            verificationExpiry: expiryDate,
            jurisdiction: jurisdiction,
            maxInvestmentAmount: maxInvestmentAmount,
            currentInvestment: 0,
            investmentLockUntil: block.timestamp + holdingPeriod,
            isWhitelisted: true,
            whitelistedAt: block.timestamp
        });
        
        emit InvestorVerified(
            investor,
            accreditationLevel,
            expiryDate,
            jurisdiction,
            maxInvestmentAmount,
            msg.sender
        );
    }
    
    function updateInvestorVerification(
        address investor,
        uint8 newAccreditationLevel,
        uint256 newExpiryDate
    ) external onlyComplianceOfficer {
        require(_investors[investor].isVerified, "SecurityToken: investor not verified");
        require(newAccreditationLevel <= 3, "SecurityToken: invalid accreditation level");
        require(newExpiryDate > block.timestamp, "SecurityToken: expiry must be future");
        
        _investors[investor].accreditationLevel = newAccreditationLevel;
        _investors[investor].verificationExpiry = newExpiryDate;
        _investors[investor].verifiedAt = block.timestamp;
        
        emit InvestorVerificationUpdated(
            investor,
            newAccreditationLevel,
            newExpiryDate,
            msg.sender
        );
    }
    
    function removeInvestor(address investor, string memory reason) 
        external 
        onlyComplianceOfficer 
    {
        require(_investors[investor].isVerified, "SecurityToken: investor not verified");
        
        uint256 investorBalance = balanceOf(investor);
        if (investorBalance > 0) {
            _frozenBalances[investor] = investorBalance;
        }
        
        delete _investors[investor];
        totalVerifiedInvestors--;
        
        emit InvestorRemoved(investor, msg.sender, reason);
    }
    
    function setTransferRestriction(
        address investor,
        uint256 customHoldingPeriod,
        uint256 maxTransferPercentage,
        uint256 dailyTransferLimit,
        bool requiresApproval
    ) external onlyComplianceOfficer {
        require(_investors[investor].isVerified, "SecurityToken: investor not verified");
        require(maxTransferPercentage <= 10000, "SecurityToken: invalid percentage");
        
        _transferRestrictions[investor] = TransferRestriction({
            holdingPeriod: customHoldingPeriod > 0 ? customHoldingPeriod : holdingPeriod,
            maxTransferPercentage: maxTransferPercentage,
            dailyTransferLimit: dailyTransferLimit,
            lastTransferDate: 0,
            dailyTransferredAmount: 0,
            requiresApproval: requiresApproval
        });
        
        emit TransferRestrictionSet(
            investor,
            customHoldingPeriod,
            maxTransferPercentage,
            dailyTransferLimit,
            requiresApproval
        );
    }
    
    function approveTransfer(
        address from,
        address to,
        uint256 amount
    ) external onlyTransferAgent {
        require(_transferRestrictions[from].requiresApproval, 
                "SecurityToken: approval not required");
        require(balanceOf(from) >= amount, "SecurityToken: insufficient balance");
        
        bytes32 approvalHash = keccak256(abi.encodePacked(from, to, amount, block.timestamp));
        
        emit TransferApproved(from, to, amount, msg.sender, block.timestamp);
        emit ApprovalHashCreated(approvalHash, from, to, amount, block.timestamp);
    }
    
    // ==============================
    // INVESTMENT LIMIT CHECKS
    // ==============================
    function _checkInvestmentLimits(address investor, uint256 amount) private view {
        if (!_isHolder[investor] && totalVerifiedInvestors >= maxInvestorCount) {
            revert("SecurityToken: maximum investor count reached");
        }
        
        if (!_isHolder[investor] && amount < minInvestmentAmount) {
            revert("SecurityToken: below minimum investment");
        }
        
        Investor memory investorInfo = _investors[investor];
        
        if (onlyAccreditedInvestors && investorInfo.accreditationLevel == 0 && !_isHolder[investor]) {
            revert("SecurityToken: only accredited investors allowed");
        }
        
        uint256 newTotal = investorInfo.currentInvestment + amount;
        require(
            newTotal <= investorInfo.maxInvestmentAmount,
            "SecurityToken: exceeds maximum investment limit"
        );
        
        require(
            block.timestamp >= investorInfo.investmentLockUntil,
            "SecurityToken: investment locked"
        );
        
        uint256 maxByPercentage = (totalSupply() * maxInvestmentPercentage) / 10000;
        require(
            newTotal <= maxByPercentage,
            "SecurityToken: exceeds maximum percentage per investor"
        );
    }
    
    function _updateInvestmentAmount(address investor, uint256 amount) private {
        Investor storage investorInfo = _investors[investor];
        if (investorInfo.isVerified) {
            investorInfo.currentInvestment += amount;
        }
    }
    
    // ==============================
    // TRANSFER RESTRICTION CHECKS
    // ==============================
    function _checkTransferRestrictions(address from, uint256 amount) private {
        TransferRestriction storage restriction = _transferRestrictions[from];
        
        if (!restriction.requiresApproval) {
            return;
        }
        
        require(
            block.timestamp >= _investors[from].whitelistedAt + restriction.holdingPeriod,
            "SecurityToken: minimum holding period not met"
        );
        
        uint256 balance = balanceOf(from);
        uint256 maxTransfer = (balance * restriction.maxTransferPercentage) / 10000;
        require(
            amount <= maxTransfer,
            "SecurityToken: transfer exceeds maximum percentage"
        );
        
        if (block.timestamp > restriction.lastTransferDate + 1 days) {
            restriction.dailyTransferredAmount = 0;
            restriction.lastTransferDate = block.timestamp;
        }
        
        require(
            restriction.dailyTransferredAmount + amount <= restriction.dailyTransferLimit,
            "SecurityToken: daily transfer limit exceeded"
        );
        
        restriction.dailyTransferredAmount += amount;
    }
    
    // ==============================
    // COMPLIANCE SETTINGS MANAGEMENT
    // ==============================
    function setComplianceOfficer(address newOfficer) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(newOfficer != address(0), "SecurityToken: zero address");
        
        address oldOfficer = complianceOfficer;
        complianceOfficer = newOfficer;
        
        emit ComplianceOfficerUpdated(oldOfficer, newOfficer, msg.sender);
    }
    
    function setTransferAgent(address newAgent) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(newAgent != address(0), "SecurityToken: zero address");
        
        address oldAgent = transferAgent;
        transferAgent = newAgent;
        
        emit TransferAgentUpdated(oldAgent, newAgent, msg.sender);
    }
    
    function enableTrading() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!tradingEnabled, "SecurityToken: trading already enabled");
        tradingEnabled = true;
        
        emit TradingEnabled(msg.sender, block.timestamp);
    }
    
    function disableTrading() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(tradingEnabled, "SecurityToken: trading already disabled");
        tradingEnabled = false;
        
        emit TradingDisabled(msg.sender, block.timestamp);
    }
    
    function setAccreditedOnly(bool accreditedOnly) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        onlyAccreditedInvestors = accreditedOnly;
    }
    
    function setTransfersRestricted(bool restricted) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        transfersRestricted = restricted;
    }
    
    function updateInvestmentParameters(
        uint256 newMaxInvestorCount,
        uint256 newMinInvestment,
        uint256 newMaxPercentage,
        uint256 newHoldingPeriod
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newMaxInvestorCount >= totalVerifiedInvestors, 
                "SecurityToken: cannot set below current investors");
        require(newMaxPercentage <= 10000, "SecurityToken: invalid percentage");
        
        maxInvestorCount = newMaxInvestorCount;
        minInvestmentAmount = newMinInvestment;
        maxInvestmentPercentage = newMaxPercentage;
        holdingPeriod = newHoldingPeriod;
    }
    
    // ==============================
    // CORPORATE ACTIONS
    // ==============================
    function createCorporateAction(
        string memory actionType,
        uint256 recordDate,
        uint256 executionDate,
        uint256 amount,
        string memory description,
        address dividendToken,
        uint256 splitRatioNumerator,
        uint256 splitRatioDenominator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256) {
        require(recordDate > block.timestamp, "SecurityToken: record date must be future");
        require(executionDate > recordDate, "SecurityToken: execution must be after record");
        
        bytes32 actionHash;
        if (keccak256(bytes(actionType)) == keccak256(bytes("DIVIDEND"))) {
            require(amount > 0, "SecurityToken: dividend amount must be > 0");
            require(dividendToken != address(0), "SecurityToken: dividend token address required");
            actionHash = keccak256(abi.encodePacked("DIVIDEND", amount, dividendToken, recordDate));
        } else if (keccak256(bytes(actionType)) == keccak256(bytes("SPLIT"))) {
            require(splitRatioNumerator > 0 && splitRatioDenominator > 0, 
                    "SecurityToken: invalid split ratio");
            require(splitRatioNumerator != splitRatioDenominator,
                   "SecurityToken: split ratio must change supply");
            actionHash = keccak256(abi.encodePacked("SPLIT", splitRatioNumerator, splitRatioDenominator));
        } else {
            revert("SecurityToken: unsupported action type");
        }
        
        uint256 actionId = _corporateActions.length;
        
        _corporateActions.push(CorporateAction({
            actionId: actionId,
            actionType: actionType,
            recordDate: recordDate,
            executionDate: executionDate,
            amount: amount,
            executed: false,
            description: description,
            actionHash: actionHash,
            snapshotId: 0,
            dividendToken: dividendToken,
            splitRatioNumerator: splitRatioNumerator,
            splitRatioDenominator: splitRatioDenominator
        }));
        
        emit CorporateActionCreated(
            actionId,
            actionType,
            recordDate,
            executionDate,
            amount,
            description
        );
        
        return actionId;
    }
    
    function executeCorporateAction(uint256 actionId) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(actionId < _corporateActions.length, "SecurityToken: invalid action ID");
        
        CorporateAction storage action = _corporateActions[actionId];
        require(!action.executed, "SecurityToken: already executed");
        require(block.timestamp >= action.executionDate, "SecurityToken: execution date not reached");
        
        action.snapshotId = createSnapshot();
        action.executed = true;
        
        if (keccak256(bytes(action.actionType)) == keccak256(bytes("DIVIDEND"))) {
            _executeDividend(actionId);
        } else if (keccak256(bytes(action.actionType)) == keccak256(bytes("SPLIT"))) {
            _executeStockSplit(actionId);
        }
        
        emit CorporateActionExecuted(actionId, msg.sender, block.timestamp);
    }
    
    function _executeDividend(uint256 actionId) private {
        CorporateAction storage action = _corporateActions[actionId];
        
        require(action.dividendToken != address(0), "SecurityToken: dividend token not set");
        require(action.amount > 0, "SecurityToken: dividend amount not set");
        
        uint256 totalSupplyAtSnapshot = totalSupplyAt(action.snapshotId);
        uint256 totalStakedAtSnapshot = _getTotalStakedAtSnapshot(action.snapshotId);
        uint256 circulatingSupplyAtSnapshot = totalSupplyAtSnapshot - totalStakedAtSnapshot;

        require(circulatingSupplyAtSnapshot > 0, "SecurityToken: no circulating supply at snapshot");
        
        uint256 dividendPerToken = (action.amount * 1e18) / circulatingSupplyAtSnapshot;
        uint256 distributionId = _dividendDistributions.length;
        
        _dividendDistributions.push(DividendDistribution({
            distributionId: distributionId,
            amountDistributed: action.amount,
            dividendPerToken: dividendPerToken,
            snapshotId: action.snapshotId,
            distributedAt: block.timestamp,
            dividendToken: action.dividendToken
        }));
        
        if (action.dividendToken == address(this)) {
            require(balanceOf(msg.sender) >= action.amount, 
                "SecurityToken: insufficient dividend tokens");
            _transfer(msg.sender, address(this), action.amount);
        } else {
            (bool success, ) = action.dividendToken.call(
                abi.encodeWithSelector(
                    bytes4(keccak256("transferFrom(address,address,uint256)")),
                    msg.sender,
                    address(this),
                    action.amount
                )
            );
            require(success, "SecurityToken: dividend token transfer failed");
        }
        
        _preCalculateDividendAmounts(distributionId, action.snapshotId, dividendPerToken);
        
        emit DividendDistributed(
            distributionId,
            action.amount,
            dividendPerToken,
            action.snapshotId,
            action.dividendToken
        );
    }

    function _preCalculateDividendAmounts(
        uint256 distributionId,
        uint256 snapshotId,
        uint256 dividendPerToken
    ) private {
        uint256 totalHolders = _holders.length;
        uint256 batchSize = 50;

        for (uint256 i = 0; i < totalHolders; i += batchSize) {
            uint256 end = i + batchSize;
            if (end > totalHolders) {
                 end = totalHolders;
            }
            for (uint256 j = i; j < end; j++) {
                address holder = _holders[j];
                uint256 holderBalance = balanceOfAt(holder, snapshotId);
                if (holderBalance > 0) {
                    uint256 dividendAmount = (holderBalance * dividendPerToken) / 1e18;
                    if (dividendAmount > 0) {
                        _dividendAmounts[distributionId][holder] = dividendAmount;
                    }
                }
            }
        }
    }

    function _getTotalStakedAtSnapshot(uint256 snapshotId) private view returns (uint256) {
        return _totalStaked;
    }
    
    function _executeStockSplit(uint256 actionId) private {
        CorporateAction storage action = _corporateActions[actionId];
        
        require(action.splitRatioNumerator > 0, "SecurityToken: split numerator not set");
        require(action.splitRatioDenominator > 0, "SecurityToken: split denominator not set");

        uint256 totalSupplyAtSnapshot = totalSupplyAt(action.snapshotId);
        uint256 newTotalSupply;
        if (action.splitRatioNumerator > action.splitRatioDenominator) {
            newTotalSupply = (totalSupplyAtSnapshot * action.splitRatioNumerator) / action.splitRatioDenominator;
        } else {
            newTotalSupply = (totalSupplyAtSnapshot * action.splitRatioNumerator) / action.splitRatioDenominator;
        }
        
        require(newTotalSupply <= cap(), "SecurityToken: split exceeds max supply");
        
        if (action.splitRatioNumerator > action.splitRatioDenominator) {
            uint256 tokensToMint = newTotalSupply - totalSupplyAtSnapshot;
            _mintSplitTokens(action.snapshotId, tokensToMint);
        } else {
            uint256 tokensToBurn = totalSupplyAtSnapshot - newTotalSupply;
            _burnSplitTokens(action.snapshotId, tokensToBurn);
        }
        
        emit StockSplitExecuted(
            actionId,
            action.splitRatioNumerator,
            action.splitRatioDenominator,
            newTotalSupply
        );
    }
    
    function _mintSplitTokens(uint256 snapshotId, uint256 totalTokensToMint) private {
        uint256 totalSupplyAtSnapshot = totalSupplyAt(snapshotId);
        require(totalSupplyAtSnapshot > 0, "SecurityToken: no supply at snapshot");
        
        uint256 totalHolders = _holders.length;
        uint256 batchSize = 30;
        
        for (uint256 i = 0; i < totalHolders; i += batchSize) {
            uint256 end = i + batchSize;
            if (end > totalHolders) {
                end = totalHolders;
            }
            
            for (uint256 j = i; j < end; j++) {
                address holder = _holders[j];
                uint256 holderBalance = balanceOfAt(holder, snapshotId);
                
                if (holderBalance > 0) {
                    uint256 tokensToMint = (holderBalance * totalTokensToMint) / totalSupplyAtSnapshot;
                    if (tokensToMint > 0) {
                        _mint(holder, tokensToMint);
                    }
                }
            }
        }
    }
    
    function _burnSplitTokens(uint256 snapshotId, uint256 totalTokensToBurn) private {
        uint256 totalSupplyAtSnapshot = totalSupplyAt(snapshotId);
        require(totalSupplyAtSnapshot > 0, "SecurityToken: no supply at snapshot");
        
        uint256 totalHolders = _holders.length;
        uint256 batchSize = 30;
        
        for (uint256 i = 0; i < totalHolders; i += batchSize) {
            uint256 end = i + batchSize;
            if (end > totalHolders) {
                end = totalHolders;
            }
            
            for (uint256 j = i; j < end; j++) {
                address holder = _holders[j];
                uint256 holderBalance = balanceOfAt(holder, snapshotId);
                
                if (holderBalance > 0) {
                    uint256 tokensToBurn = (holderBalance * totalTokensToBurn) / totalSupplyAtSnapshot;
                    if (tokensToBurn > 0 && balanceOf(holder) >= tokensToBurn) {
                        _burn(holder, tokensToBurn);
                    }
                }
            }
        }
    }
    
    // ==============================
    // DIVIDEND CLAIM FUNCTIONS
    // ==============================
    function claimDividend(uint256 distributionId) external {
        require(distributionId < _dividendDistributions.length, 
                "SecurityToken: invalid distribution ID");
        
        DividendDistribution memory distribution = _dividendDistributions[distributionId];
        require(!_dividendClaimed[distributionId][msg.sender], 
                "SecurityToken: already claimed");
        
        uint256 dividendAmount = _dividendAmounts[distributionId][msg.sender];
        require(dividendAmount > 0, "SecurityToken: no dividend to claim");
        
        _dividendClaimed[distributionId][msg.sender] = true;
        
        if (distribution.dividendToken == address(this)) {
            _transfer(address(this), msg.sender, dividendAmount);
        } else {
            (bool success, ) = distribution.dividendToken.call(
                abi.encodeWithSelector(
                    bytes4(keccak256("transfer(address,uint256)")),
                    msg.sender,
                    dividendAmount
                )
            );
            require(success, "SecurityToken: dividend transfer failed");
        }
        
        emit DividendClaimed(msg.sender, distributionId, dividendAmount, block.timestamp);
    }
    
    function claimMultipleDividends(uint256[] memory distributionIds) external {
        uint256 totalAmount = 0;
        address dividendToken = address(0);
        
        for (uint256 i = 0; i < distributionIds.length; i++) {
            uint256 distributionId = distributionIds[i];
            
            require(distributionId < _dividendDistributions.length, 
                    "SecurityToken: invalid distribution ID");
            
            DividendDistribution memory distribution = _dividendDistributions[distributionId];
            require(!_dividendClaimed[distributionId][msg.sender], 
                    "SecurityToken: already claimed");
            
            uint256 dividendAmount = _dividendAmounts[distributionId][msg.sender];
            if (dividendAmount > 0) {
                if (dividendToken == address(0)) {
                    dividendToken = distribution.dividendToken;
                } else {
                    require(dividendToken == distribution.dividendToken, 
                            "SecurityToken: cannot batch claim different tokens");
                }
                
                totalAmount += dividendAmount;
                _dividendClaimed[distributionId][msg.sender] = true;
                
                emit DividendClaimed(msg.sender, distributionId, dividendAmount, block.timestamp);
            }
        }
        
        require(totalAmount > 0, "SecurityToken: no dividends to claim");
        
        if (dividendToken == address(this)) {
            _transfer(address(this), msg.sender, totalAmount);
        } else {
            (bool success, ) = dividendToken.call(
                abi.encodeWithSelector(
                    bytes4(keccak256("transfer(address,uint256)")),
                    msg.sender,
                    totalAmount
                )
            );
            require(success, "SecurityToken: dividend transfer failed");
        }
    }
    
    function getClaimableDividend(address holder, uint256 distributionId) 
        external 
        view 
        returns (uint256) 
    {
        if (distributionId >= _dividendDistributions.length) {
            return 0;
        }
        
        if (_dividendClaimed[distributionId][holder]) {
            return 0;
        }
        
        return _dividendAmounts[distributionId][holder];
    }
    
    function getTotalClaimableDividends(address holder) 
        external 
        view 
        returns (uint256 totalAmount, address[] memory tokens) 
    {
        uint256 distributionCount = _dividendDistributions.length;
        uint256 claimableCount = 0;
        
        for (uint256 i = 0; i < distributionCount; i++) {
            if (!_dividendClaimed[i][holder] && _dividendAmounts[i][holder] > 0) {
                claimableCount++;
            }
        }
        
        tokens = new address[](claimableCount);
        totalAmount = 0;
        uint256 index = 0;
        
        for (uint256 i = 0; i < distributionCount; i++) {
            if (!_dividendClaimed[i][holder] && _dividendAmounts[i][holder] > 0) {
                totalAmount += _dividendAmounts[i][holder];
                tokens[index] = _dividendDistributions[i].dividendToken;
                index++;
            }
        }
        
        return (totalAmount, tokens);
    }
    
    // ==============================
    // LOCKUP SCHEDULES
    // ==============================
    function createLockupSchedule(
        address beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 cliffPeriod,
        uint256 vestingDuration,
        uint256 releaseInterval,
        bool isRevocable
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256) {
        require(beneficiary != address(0), "SecurityToken: zero address beneficiary");
        require(totalAmount > 0, "SecurityToken: amount must be > 0");
        require(startTime >= block.timestamp, "SecurityToken: start time must be future");
        require(cliffPeriod <= vestingDuration, "SecurityToken: cliff exceeds duration");
        
        _transfer(msg.sender, address(this), totalAmount);
        
        uint256 scheduleId = _lockupSchedules.length;
        
        _lockupSchedules.push(LockupSchedule({
            totalAmount: totalAmount,
            releasedAmount: 0,
            startTime: startTime,
            cliffPeriod: cliffPeriod,
            vestingDuration: vestingDuration,
            releaseInterval: releaseInterval,
            isRevocable: isRevocable,
            beneficiary: beneficiary
        }));
        
        _beneficiaryLockups[beneficiary].push(scheduleId);
        totalLockedTokens += totalAmount;
        
        emit LockupScheduleCreated(
            scheduleId,
            beneficiary,
            totalAmount,
            startTime,
            cliffPeriod,
            vestingDuration,
            isRevocable
        );
        
        return scheduleId;
    }
    
    function releaseLockedTokens(uint256 scheduleId) external {
        require(scheduleId < _lockupSchedules.length, "SecurityToken: invalid schedule ID");
        
        LockupSchedule storage schedule = _lockupSchedules[scheduleId];
        require(msg.sender == schedule.beneficiary, "SecurityToken: not beneficiary");
        
        uint256 releasable = _calculateReleasableAmount(scheduleId);
        require(releasable > 0, "SecurityToken: no tokens to release");
        
        schedule.releasedAmount += releasable;
        totalLockedTokens -= releasable;
        
        _transfer(address(this), schedule.beneficiary, releasable);
        
        emit TokensReleased(scheduleId, msg.sender, releasable, block.timestamp);
    }
    
    function revokeLockupSchedule(uint256 scheduleId) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(scheduleId < _lockupSchedules.length, "SecurityToken: invalid schedule ID");
        
        LockupSchedule storage schedule = _lockupSchedules[scheduleId];
        require(schedule.isRevocable, "SecurityToken: lockup not revocable");
        
        uint256 remaining = schedule.totalAmount - schedule.releasedAmount;
        require(remaining > 0, "SecurityToken: no tokens to revoke");
        
        schedule.totalAmount = schedule.releasedAmount;
        totalLockedTokens -= remaining;
        
        _transfer(address(this), msg.sender, remaining);
        
        emit LockupRevoked(scheduleId, msg.sender, remaining, block.timestamp);
    }
    
    function _calculateReleasableAmount(uint256 scheduleId) 
        private 
        view 
        returns (uint256) 
    {
        LockupSchedule memory schedule = _lockupSchedules[scheduleId];
        
        if (block.timestamp < schedule.startTime + schedule.cliffPeriod) {
            return 0;
        }
        
        if (block.timestamp >= schedule.startTime + schedule.vestingDuration) {
            return schedule.totalAmount - schedule.releasedAmount;
        }
        
        uint256 timeElapsed = block.timestamp - schedule.startTime;
        uint256 vestedAmount;
        
        if (schedule.releaseInterval > 0) {
            uint256 intervalsPassed = timeElapsed / schedule.releaseInterval;
            uint256 totalIntervals = schedule.vestingDuration / schedule.releaseInterval;
            vestedAmount = (schedule.totalAmount * intervalsPassed) / totalIntervals;
        } else {
            vestedAmount = (schedule.totalAmount * timeElapsed) / schedule.vestingDuration;
        }
        
        if (vestedAmount > schedule.totalAmount) {
            vestedAmount = schedule.totalAmount;
        }
        
        return vestedAmount - schedule.releasedAmount;
    }
    
    // ==============================
    // OVERRIDDEN TRANSFER FUNCTIONS
    // ==============================
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        require(tradingEnabled || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), 
                "SecurityToken: trading not enabled");
        
        require(_isInvestorVerified(from), "SecurityToken: sender not verified");
        require(_isInvestorVerified(to), "SecurityToken: recipient not verified");
        
        if (transfersRestricted) {
            _checkTransferRestrictions(from, amount);
        }
        
        _checkInvestmentLimits(to, amount);
        
        super._transfer(from, to, amount);
        
        _updateInvestmentAmount(to, amount);
    }
    
    function _isInvestorVerified(address account) private view returns (bool) {
        if (account == address(this) || account == address(0) || hasRole(DEFAULT_ADMIN_ROLE, account)) {
            return true;
        }
        
        Investor memory investor = _investors[account];
        return investor.isVerified && investor.verificationExpiry > block.timestamp;
    }
    
    // ==============================
    // VIEW FUNCTIONS
    // ==============================
    function getInvestorInfo(address investor) 
        external 
        view 
        returns (Investor memory) 
    {
        return _investors[investor];
    }
    
    function getTransferRestriction(address investor) 
        external 
        view 
        returns (TransferRestriction memory) 
    {
        return _transferRestrictions[investor];
    }
    
    function getCorporateAction(uint256 actionId) 
        external 
        view 
        returns (CorporateAction memory) 
    {
        require(actionId < _corporateActions.length, "SecurityToken: invalid action ID");
        return _corporateActions[actionId];
    }
    
    function getAllCorporateActions() 
        external 
        view 
        returns (CorporateAction[] memory) 
    {
        return _corporateActions;
    }
    
    function getDividendDistribution(uint256 distributionId) 
        external 
        view 
        returns (DividendDistribution memory) 
    {
        require(distributionId < _dividendDistributions.length, "SecurityToken: invalid distribution ID");
        return _dividendDistributions[distributionId];
    }
    
    function getAllDividendDistributions() 
        external 
        view 
        returns (DividendDistribution[] memory) 
    {
        return _dividendDistributions;
    }
    
    function getLockupSchedule(uint256 scheduleId) 
        external 
        view 
        returns (LockupSchedule memory) 
    {
        require(scheduleId < _lockupSchedules.length, "SecurityToken: invalid schedule ID");
        return _lockupSchedules[scheduleId];
    }
    
    function getBeneficiaryLockups(address beneficiary) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return _beneficiaryLockups[beneficiary];
    }
    
    function calculateReleasableTokens(uint256 scheduleId) 
        external 
        view 
        returns (uint256) 
    {
        return _calculateReleasableAmount(scheduleId);
    }
    
    function getComplianceStatus() 
        external 
        view 
        returns (
            bool accreditedOnly,
            bool transfersRestrictedStatus,
            bool tradingEnabledStatus,
            uint256 investorCount,
            uint256 maxInvestors,
            uint256 lockedTokens
        ) 
    {
        return (
            onlyAccreditedInvestors,
            transfersRestricted,
            tradingEnabled,
            totalVerifiedInvestors,
            maxInvestorCount,
            totalLockedTokens
        );
    }
    
    // ==============================
    // EMERGENCY FUNCTIONS
    // ==============================
    function emergencyFreezeInvestor(address investor) 
        external 
        onlyComplianceOfficer 
    {
        require(_investors[investor].isVerified, "SecurityToken: investor not verified");
        
        uint256 balance = balanceOf(investor);
        if (balance > 0) {
            _frozenBalances[investor] = balance;
        }
    }
    
    function emergencyUnfreezeInvestor(address investor) 
        external 
        onlyComplianceOfficer 
    {
        _frozenBalances[investor] = 0;
    }
    
    function emergencyForceTransfer(
        address from,
        address to,
        uint256 amount,
        string memory reason
    ) external onlyComplianceOfficer {
        require(from != address(0), "SecurityToken: transfer from zero address");
        require(to != address(0), "SecurityToken: transfer to zero address");
        require(amount > 0, "SecurityToken: amount must be > 0");
        require(balanceOf(from) >= amount, "SecurityToken: insufficient balance");
        
        super._transfer(from, to, amount);
    }
    
    function emergencyCancelCorporateAction(uint256 actionId, string memory reason) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(actionId < _corporateActions.length, "SecurityToken: invalid action ID");
        
        CorporateAction storage action = _corporateActions[actionId];
        require(!action.executed, "SecurityToken: already executed");
        
        action.executed = true;
    }
    
    function emergencyReleaseLockup(uint256 scheduleId) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(scheduleId < _lockupSchedules.length, "SecurityToken: invalid schedule ID");
        
        LockupSchedule storage schedule = _lockupSchedules[scheduleId];
        uint256 remaining = schedule.totalAmount - schedule.releasedAmount;
        require(remaining > 0, "SecurityToken: no tokens to release");
        
        schedule.releasedAmount = schedule.totalAmount;
        totalLockedTokens -= remaining;
        
        _transfer(address(this), schedule.beneficiary, remaining);
        
        emit TokensReleased(scheduleId, schedule.beneficiary, remaining, block.timestamp);
    }
}