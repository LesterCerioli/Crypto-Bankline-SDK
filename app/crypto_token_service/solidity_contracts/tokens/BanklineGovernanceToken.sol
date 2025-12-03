pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "./BanklineBaseToken.sol";
import "../interfaces/IBanklineFactory.sol";

/**
 * @title BanklineGovernanceToken
 * @dev Advanced governance token with voting power delegation, proposal creation, and treasury management
 */
contract BanklineGovernanceToken is BanklineBaseToken, ERC20Permit, ERC20Votes {
    // ==============================
    // GOVERNANCE STRUCTS
    // ==============================
    struct Proposal {
        uint256 proposalId;
        address proposer;
        string title;
        string description;
        bytes32 executionHash;
        uint256 startTime;
        uint256 endTime;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool executed;
        bool canceled;
        uint256 minVotingPower;
        uint256 executionTimestamp;
    }
    
    struct Vote {
        bool hasVoted;
        uint8 support; // 0 = against, 1 = for, 2 = abstain
        uint256 votingPower;
    }
    
    struct TreasuryTransaction {
        uint256 transactionId;
        address recipient;
        uint256 amount;
        string description;
        bool executed;
        uint256 proposedAt;
        uint256 executedAt;
        uint256 proposalId; // Linked proposal if any
    }
    
    struct DelegateInfo {
        address delegatee;
        uint256 delegatedAt;
        uint256 delegatedAmount;
    }
    
    // ==============================
    // GOVERNANCE STATE VARIABLES
    // ==============================
    Proposal[] private _proposals;
    mapping(uint256 => mapping(address => Vote)) private _votes;
    mapping(uint256 => address[]) private _proposalVoters;
    
    TreasuryTransaction[] private _treasuryTransactions;
    uint256 public treasuryBalance;
    address public treasuryAddress;
    
    mapping(address => DelegateInfo) private _delegateInfo;
    mapping(address => address[]) private _delegators;
    
    uint256 public proposalCount;
    uint256 public constant MIN_PROPOSAL_DURATION = 1 days;
    uint256 public constant MAX_PROPOSAL_DURATION = 30 days;
    uint256 public minProposalVotingPower = 1000 * 10 ** 18; // 1000 tokens minimum
    uint256 public quorumPercentage = 400; // 4% basis points
    uint256 public votingDelay = 1 days;
    uint256 public votingPeriod = 7 days;
    uint256 public proposalThreshold = 10000 * 10 ** 18; // 10,000 tokens to propose
    
    bool public governancePaused;
    
    // ==============================
    // GOVERNANCE EVENTS
    // ==============================
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        uint256 startTime,
        uint256 endTime,
        uint256 minVotingPower
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
        uint256 executionTimestamp
    );
    
    event ProposalCanceled(
        uint256 indexed proposalId,
        address indexed canceler,
        string reason
    );
    
    event VotingPowerDelegated(
        address indexed delegator,
        address indexed delegatee,
        uint256 amount,
        uint256 timestamp
    );
    
    event DelegationRevoked(
        address indexed delegator,
        address indexed delegatee,
        uint256 amount,
        uint256 timestamp
    );
    
    event TreasuryTransactionProposed(
        uint256 indexed transactionId,
        address indexed proposer,
        address recipient,
        uint256 amount,
        string description,
        uint256 linkedProposalId
    );
    
    event TreasuryTransactionExecuted(
        uint256 indexed transactionId,
        address indexed executor,
        uint256 timestamp
    );
    
    event QuorumUpdated(
        uint256 oldQuorum,
        uint256 newQuorum,
        address indexed updater
    );
    
    event ProposalThresholdUpdated(
        uint256 oldThreshold,
        uint256 newThreshold,
        address indexed updater
    );
    
    event GovernancePaused(
        address indexed pauser,
        uint256 timestamp
    );
    
    event GovernanceUnpaused(
        address indexed unpauser,
        uint256 timestamp
    );
    
    // ==============================
    // MODIFIERS
    // ==============================
    modifier governanceNotPaused() {
        require(!governancePaused, "GovernanceToken: governance is paused");
        _;
    }
    
    modifier onlyProposer(uint256 proposalId) {
        require(_proposals[proposalId].proposer == msg.sender, 
                "GovernanceToken: not the proposer");
        _;
    }
    
    modifier proposalExists(uint256 proposalId) {
        require(proposalId < _proposals.length, 
                "GovernanceToken: proposal does not exist");
        _;
    }
    
    modifier proposalActive(uint256 proposalId) {
        Proposal storage proposal = _proposals[proposalId];
        require(!proposal.executed, "GovernanceToken: proposal already executed");
        require(!proposal.canceled, "GovernanceToken: proposal canceled");
        require(block.timestamp >= proposal.startTime, 
                "GovernanceToken: voting not started");
        require(block.timestamp <= proposal.endTime, 
                "GovernanceToken: voting ended");
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
    ) 
        BanklineBaseToken(
            name_,
            symbol_,
            decimals_,
            maxSupply_,
            IBanklineFactory.TokenType.GOVERNANCE,
            owner_,
            factory_
        )
        ERC20Permit(name_)
    {
        treasuryAddress = owner_;
        treasuryBalance = 0;
        governancePaused = false;
        
        
        _initializeGovernanceParameters();
    }
    
    function _initializeGovernanceParameters() private {
        
        minProposalVotingPower = 1000 * 10 ** decimals();
        quorumPercentage = 400; // 4%
        votingDelay = 1 days;
        votingPeriod = 7 days;
        proposalThreshold = 10000 * 10 ** decimals();
    }
    
    // ==============================
    // GOVERNANCE PARAMETER MANAGEMENT
    // ==============================
    function setQuorumPercentage(uint256 newQuorum) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(newQuorum <= 10000, "GovernanceToken: invalid quorum percentage");
        uint256 oldQuorum = quorumPercentage;
        quorumPercentage = newQuorum;
        
        emit QuorumUpdated(oldQuorum, newQuorum, msg.sender);
    }
    
    function setProposalThreshold(uint256 newThreshold) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        uint256 oldThreshold = proposalThreshold;
        proposalThreshold = newThreshold;
        
        emit ProposalThresholdUpdated(oldThreshold, newThreshold, msg.sender);
    }
    
    function setVotingParameters(
        uint256 newVotingDelay,
        uint256 newVotingPeriod
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newVotingDelay <= 30 days, "GovernanceToken: voting delay too long");
        require(newVotingPeriod >= 1 days && newVotingPeriod <= 30 days, 
                "GovernanceToken: invalid voting period");
        
        votingDelay = newVotingDelay;
        votingPeriod = newVotingPeriod;
    }
    
    function pauseGovernance() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(!governancePaused, "GovernanceToken: already paused");
        governancePaused = true;
        
        emit GovernancePaused(msg.sender, block.timestamp);
    }
    
    function unpauseGovernance() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(governancePaused, "GovernanceToken: not paused");
        governancePaused = false;
        
        emit GovernanceUnpaused(msg.sender, block.timestamp);
    }
    
    // ==============================
    // PROPOSAL MANAGEMENT
    // ==============================
    function createProposal(
        string memory title,
        string memory description,
        bytes32 executionHash,
        uint256 minVotingPower
    ) external governanceNotPaused returns (uint256) {
        require(getVotes(msg.sender) >= proposalThreshold, 
                "GovernanceToken: insufficient voting power");
        
        uint256 proposalId = _proposals.length;
        uint256 startTime = block.timestamp + votingDelay;
        uint256 endTime = startTime + votingPeriod;
        
        require(minVotingPower >= minProposalVotingPower, 
                "GovernanceToken: min voting power too low");
        
        _proposals.push(Proposal({
            proposalId: proposalId,
            proposer: msg.sender,
            title: title,
            description: description,
            executionHash: executionHash,
            startTime: startTime,
            endTime: endTime,
            forVotes: 0,
            againstVotes: 0,
            abstainVotes: 0,
            executed: false,
            canceled: false,
            minVotingPower: minVotingPower,
            executionTimestamp: 0
        }));
        
        proposalCount++;
        
        emit ProposalCreated(
            proposalId,
            msg.sender,
            title,
            startTime,
            endTime,
            minVotingPower
        );
        
        return proposalId;
    }
    
    function castVote(
        uint256 proposalId,
        uint8 support,
        string memory reason
    ) external governanceNotPaused proposalExists(proposalId) proposalActive(proposalId) {
        require(support <= 2, "GovernanceToken: invalid vote type");
        require(!_votes[proposalId][msg.sender].hasVoted, 
                "GovernanceToken: already voted");
        
        uint256 votingPower = getVotes(msg.sender);
        require(votingPower > 0, "GovernanceToken: no voting power");
        
        Proposal storage proposal = _proposals[proposalId];
        
        if (support == 1) { // For
            proposal.forVotes += votingPower;
        } else if (support == 0) { // Against
            proposal.againstVotes += votingPower;
        } else { // Abstain
            proposal.abstainVotes += votingPower;
        }
        
        _votes[proposalId][msg.sender] = Vote({
            hasVoted: true,
            support: support,
            votingPower: votingPower
        });
        
        _proposalVoters[proposalId].push(msg.sender);
        
        emit VoteCast(msg.sender, proposalId, support, votingPower, reason);
    }
    
    function executeProposal(
        uint256 proposalId,
        bytes memory executionData
    ) external governanceNotPaused proposalExists(proposalId) {
        Proposal storage proposal = _proposals[proposalId];
        
        require(!proposal.executed, "GovernanceToken: already executed");
        require(!proposal.canceled, "GovernanceToken: proposal canceled");
        require(block.timestamp > proposal.endTime, 
                "GovernanceToken: voting period not ended");
        
        
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes + proposal.abstainVotes;
        uint256 totalSupplyAtProposal = totalSupply();
        uint256 quorumRequired = (totalSupplyAtProposal * quorumPercentage) / 10000;
        
        require(totalVotes >= quorumRequired, "GovernanceToken: quorum not reached");
        require(totalVotes >= proposal.minVotingPower, 
                "GovernanceToken: minimum voting power not reached");
        
        
        require(proposal.forVotes > proposal.againstVotes, 
                "GovernanceToken: proposal did not pass");
        
        
        bytes32 calculatedHash = keccak256(executionData);
        require(calculatedHash == proposal.executionHash, 
                "GovernanceToken: execution data hash mismatch");
        
        proposal.executed = true;
        proposal.executionTimestamp = block.timestamp;
        
        
        (bool success, ) = address(this).call(executionData);
        require(success, "GovernanceToken: execution failed");
        
        emit ProposalExecuted(proposalId, msg.sender, block.timestamp);
    }
    
    function cancelProposal(uint256 proposalId, string memory reason) 
        external 
        onlyProposer(proposalId) 
        proposalExists(proposalId) 
    {
        Proposal storage proposal = _proposals[proposalId];
        
        require(!proposal.executed, "GovernanceToken: already executed");
        require(!proposal.canceled, "GovernanceToken: already canceled");
        require(block.timestamp < proposal.startTime, 
                "GovernanceToken: voting already started");
        
        proposal.canceled = true;
        
        emit ProposalCanceled(proposalId, msg.sender, reason);
    }
    
    // ==============================
    // DELEGATION SYSTEM
    // ==============================
    function delegateVotes(address delegatee, uint256 amount) external governanceNotPaused {
        require(delegatee != address(0), "GovernanceToken: delegate to zero address");
        require(delegatee != msg.sender, "GovernanceToken: cannot delegate to self");
        require(amount > 0, "GovernanceToken: delegation amount must be > 0");
        require(balanceOf(msg.sender) >= amount, 
                "GovernanceToken: insufficient balance");
        
        DelegateInfo storage currentDelegation = _delegateInfo[msg.sender];
        
        
        if (currentDelegation.delegatee != address(0)) {
            _revokeDelegation(msg.sender);
        }
        
        
        _delegate(msg.sender, delegatee);
        
        currentDelegation.delegatee = delegatee;
        currentDelegation.delegatedAt = block.timestamp;
        currentDelegation.delegatedAmount = amount;
        
        _delegators[delegatee].push(msg.sender);
        
        emit VotingPowerDelegated(msg.sender, delegatee, amount, block.timestamp);
    }
    
    function revokeDelegation() external governanceNotPaused {
        _revokeDelegation(msg.sender);
    }
    
    function _revokeDelegation(address delegator) private {
        DelegateInfo storage delegation = _delegateInfo[delegator];
        
        require(delegation.delegatee != address(0), 
                "GovernanceToken: no active delegation");
        
        address delegatee = delegation.delegatee;
        uint256 amount = delegation.delegatedAmount;
        
        
        delete _delegateInfo[delegator];
        
        
        address[] storage delegators = _delegators[delegatee];
        for (uint256 i = 0; i < delegators.length; i++) {
            if (delegators[i] == delegator) {
                delegators[i] = delegators[delegators.length - 1];
                delegators.pop();
                break;
            }
        }
        
        emit DelegationRevoked(delegator, delegatee, amount, block.timestamp);
    }
    
    // ==============================
    // TREASURY MANAGEMENT
    // ==============================
    function proposeTreasuryTransaction(
        address recipient,
        uint256 amount,
        string memory description,
        uint256 linkedProposalId
    ) external governanceNotPaused returns (uint256) {
        require(recipient != address(0), "GovernanceToken: zero address recipient");
        require(amount > 0, "GovernanceToken: amount must be > 0");
        require(treasuryBalance >= amount, "GovernanceToken: insufficient treasury balance");
        
        uint256 transactionId = _treasuryTransactions.length;
        
        _treasuryTransactions.push(TreasuryTransaction({
            transactionId: transactionId,
            recipient: recipient,
            amount: amount,
            description: description,
            executed: false,
            proposedAt: block.timestamp,
            executedAt: 0,
            proposalId: linkedProposalId
        }));
        
        emit TreasuryTransactionProposed(
            transactionId,
            msg.sender,
            recipient,
            amount,
            description,
            linkedProposalId
        );
        
        return transactionId;
    }
    
    function executeTreasuryTransaction(uint256 transactionId) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
        governanceNotPaused 
    {
        require(transactionId < _treasuryTransactions.length, 
                "GovernanceToken: invalid transaction ID");
        
        TreasuryTransaction storage transaction = _treasuryTransactions[transactionId];
        
        require(!transaction.executed, "GovernanceToken: already executed");
        require(treasuryBalance >= transaction.amount, 
                "GovernanceToken: insufficient treasury balance");
        
        
        if (transaction.proposalId != 0) {
            Proposal storage proposal = _proposals[transaction.proposalId];
            require(proposal.executed, "GovernanceToken: linked proposal not executed");
        }
        
        treasuryBalance -= transaction.amount;
        transaction.executed = true;
        transaction.executedAt = block.timestamp;
        
        
        _transfer(treasuryAddress, transaction.recipient, transaction.amount);
        
        emit TreasuryTransactionExecuted(transactionId, msg.sender, block.timestamp);
    }
    
    function depositToTreasury(uint256 amount) external {
        require(amount > 0, "GovernanceToken: amount must be > 0");
        require(balanceOf(msg.sender) >= amount, "GovernanceToken: insufficient balance");
        
        _transfer(msg.sender, treasuryAddress, amount);
        treasuryBalance += amount;
    }
    
    function updateTreasuryAddress(address newTreasury) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(newTreasury != address(0), "GovernanceToken: zero address");
        
        
        if (treasuryBalance > 0) {
            _transfer(treasuryAddress, newTreasury, treasuryBalance);
        }
        
        treasuryAddress = newTreasury;
    }
    
    // ==============================
    // VIEW FUNCTIONS
    // ==============================
    function getProposal(uint256 proposalId) 
        external 
        view 
        returns (Proposal memory) 
    {
        require(proposalId < _proposals.length, "GovernanceToken: invalid proposal ID");
        return _proposals[proposalId];
    }
    
    function getAllProposals() external view returns (Proposal[] memory) {
        return _proposals;
    }
    
    function getProposalVotes(uint256 proposalId) 
        external 
        view 
        returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes) 
    {
        require(proposalId < _proposals.length, "GovernanceToken: invalid proposal ID");
        Proposal memory proposal = _proposals[proposalId];
        return (proposal.forVotes, proposal.againstVotes, proposal.abstainVotes);
    }
    
    function getUserVote(uint256 proposalId, address voter) 
        external 
        view 
        returns (Vote memory) 
    {
        require(proposalId < _proposals.length, "GovernanceToken: invalid proposal ID");
        return _votes[proposalId][voter];
    }
    
    function getProposalVoters(uint256 proposalId) 
        external 
        view 
        returns (address[] memory) 
    {
        require(proposalId < _proposals.length, "GovernanceToken: invalid proposal ID");
        return _proposalVoters[proposalId];
    }
    
    function getDelegateInfo(address delegator) 
        external 
        view 
        returns (DelegateInfo memory) 
    {
        return _delegateInfo[delegator];
    }
    
    function getDelegators(address delegatee) 
        external 
        view 
        returns (address[] memory) 
    {
        return _delegators[delegatee];
    }
    
    function getTreasuryTransactions() 
        external 
        view 
        returns (TreasuryTransaction[] memory) 
    {
        return _treasuryTransactions;
    }
    
    function getGovernanceParameters() 
        external 
        view 
        returns (
            uint256 minVotingPower,
            uint256 quorum,
            uint256 delay,
            uint256 period,
            uint256 threshold,
            bool paused
        ) 
    {
        return (
            minProposalVotingPower,
            quorumPercentage,
            votingDelay,
            votingPeriod,
            proposalThreshold,
            governancePaused
        );
    }
    
    function calculateQuorum() external view returns (uint256) {
        uint256 totalSupply = totalSupply();
        return (totalSupply * quorumPercentage) / 10000;
    }
    
    // ==============================
    // OVERRIDES FOR VOTES
    // ==============================
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
        
        
        if (from != address(0)) {
            _updateDelegateVotes(from);
        }
        if (to != address(0)) {
            _updateDelegateVotes(to);
        }
    }
    
    function _mint(address to, uint256 amount) 
        internal 
        override(ERC20, ERC20Votes) 
    {
        super._mint(to, amount);
    }
    
    function _burn(address account, uint256 amount) 
        internal 
        override(ERC20, ERC20Votes) 
    {
        super._burn(account, amount);
    }
    
    function _updateDelegateVotes(address account) private {
        DelegateInfo storage delegation = _delegateInfo[account];
        if (delegation.delegatee != address(0)) {
            // Update delegation amount to current balance
            delegation.delegatedAmount = balanceOf(account);
        }
    }
    
    // ==============================
    // EMERGENCY FUNCTIONS
    // ==============================
    function emergencyCancelProposal(uint256 proposalId, string memory reason) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        Proposal storage proposal = _proposals[proposalId];
        require(!proposal.executed, "GovernanceToken: already executed");
        
        proposal.canceled = true;
        
        emit ProposalCanceled(proposalId, msg.sender, reason);
    }
    
    function emergencyWithdrawTreasury(address recipient, uint256 amount) 
        external 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        require(recipient != address(0), "GovernanceToken: zero address recipient");
        require(amount > 0, "GovernanceToken: amount must be > 0");
        require(treasuryBalance >= amount, "GovernanceToken: insufficient treasury balance");
        
        treasuryBalance -= amount;
        _transfer(treasuryAddress, recipient, amount);
    }
}