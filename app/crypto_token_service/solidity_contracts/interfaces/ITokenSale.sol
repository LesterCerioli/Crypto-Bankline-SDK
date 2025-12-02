// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IBanklineFactory.sol";

/**
 * @title ITokenSale
 * @dev Interface para vendas de tokens do Crypto Bankline
 */
interface ITokenSale {
    // ==============================
    // ENUMS & STRUCTS
    // ==============================
    
    enum SaleStatus {
        UPCOMING,       
        ACTIVE,         
        PAUSED,         
        ENDED,          
        CANCELLED,      
        SUCCESSFUL,     
        FAILED          
    }
    
    enum PaymentCurrency {
        NATIVE,         
        STABLE_COIN,    
        CUSTOM_TOKEN    
    }
    
    struct PurchaseInfo {
        address buyer;          
        uint256 tokenAmount;    
        uint256 paidAmount;     
        uint256 purchaseTime;   
        uint256 vestingReleased; 
        uint256 vestingClaimed; 
    }
    
    struct WhitelistEntry {
        address user;           
        uint256 maxAllocation;  
        uint256 purchased;      
        bool isWhitelisted;     
    }
    
    struct VestingStage {
        uint256 unlockTime;     
        uint256 percentage;     
        bool isClaimed;         
    }
    
    struct RefundInfo {
        address buyer;          
        uint256 refundAmount;   
        bool isRefunded;        
    }
    
    // ==============================
    // EVENTS
    // ==============================
    
    event SaleCreated(
        address indexed saleAddress,
        address indexed token,
        address indexed creator,
        uint256 pricePerToken,
        uint256 startTime,
        uint256 endTime,
        uint256 softCap,
        uint256 hardCap
    );
    
    event TokensPurchased(
        address indexed buyer,
        uint256 tokenAmount,
        uint256 paidAmount,
        uint256 timestamp
    );
    
    event SalePaused(
        address indexed saleAddress,
        address indexed pauser,
        uint256 timestamp
    );
    
    event SaleResumed(
        address indexed saleAddress,
        address indexed resumer,
        uint256 timestamp
    );
    
    event SaleEnded(
        address indexed saleAddress,
        SaleStatus status,
        uint256 totalSold,
        uint256 totalRaised,
        uint256 timestamp
    );
    
    event TokensClaimed(
        address indexed buyer,
        uint256 amount,
        uint256 timestamp
    );
    
    event WhitelistUpdated(
        address indexed user,
        uint256 allocation,
        bool added,
        uint256 timestamp
    );
    
    event VestingScheduleUpdated(
        address indexed beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 duration,
        uint256 timestamp
    );
    
    event RefundIssued(
        address indexed buyer,
        uint256 amount,
        uint256 timestamp
    );
    
    event FundsWithdrawn(
        address indexed receiver,
        uint256 amount,
        uint256 timestamp
    );
    
    event UnsoldTokensBurnt(
        uint256 amount,
        uint256 timestamp
    );
    
    event PriceUpdated(
        uint256 oldPrice,
        uint256 newPrice,
        uint256 timestamp
    );
    
    event SaleTimesUpdated(
        uint256 newStartTime,
        uint256 newEndTime,
        uint256 timestamp
    );
    
    // ==============================
    // SALE CONFIGURATION
    // ==============================
    
    /**
     * @dev Retorna token sendo vendido
     */
    function token() external view returns (address);
    
    /**
     * @dev Retorna preço por token
     */
    function pricePerToken() external view returns (uint256);
    
    /**
     * @dev Retorna quantidade de tokens para venda
     */
    function tokensForSale() external view returns (uint256);
    
    /**
     * @dev Retorna quantidade de tokens vendidos
     */
    function tokensSold() external view returns (uint256);
    
    /**
     * @dev Retorna fundos arrecadados
     */
    function fundsRaised() external view returns (uint256);
    
    /**
     * @dev Retorna soft cap
     */
    function softCap() external view returns (uint256);
    
    /**
     * @dev Retorna hard cap
     */
    function hardCap() external view returns (uint256);
    
    /**
     * @dev Retorna horário de início
     */
   