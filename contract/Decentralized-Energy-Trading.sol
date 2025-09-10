// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Decentralized Energy Trading Platform
 * @dev Smart contract for peer-to-peer energy trading between prosumers
 * @author Energy Trading DApp Team
 */
contract DecentralizedEnergyTrading {
    
    // Struct to represent an energy listing
    struct EnergyListing {
        uint256 listingId;
        address seller;
        uint256 energyAmount; // in kWh
        uint256 pricePerUnit; // in wei per kWh
        uint256 timestamp;
        bool isActive;
        string location;
        string energySource; // solar, wind, hydro, etc.
    }
    
    // Struct to represent an energy trade
    struct EnergyTrade {
        uint256 tradeId;
        uint256 listingId;
        address buyer;
        address seller;
        uint256 energyAmount;
        uint256 totalPrice;
        uint256 timestamp;
        bool isCompleted;
    }
    
    // State variables
    uint256 private nextListingId = 1;
    uint256 private nextTradeId = 1;
    uint256 public platformFeePercent = 25; // 2.5% (25/1000)
    address public platformOwner;
    
    // Mappings
    mapping(uint256 => EnergyListing) public energyListings;
    mapping(uint256 => EnergyTrade) public energyTrades;
    mapping(address => uint256[]) public userListings;
    mapping(address => uint256[]) public userTrades;
    mapping(address => uint256) public userBalances;
    
    // Events
    event EnergyListed(
        uint256 indexed listingId,
        address indexed seller,
        uint256 energyAmount,
        uint256 pricePerUnit,
        string location,
        string energySource
    );
    
    event EnergyTraded(
        uint256 indexed tradeId,
        uint256 indexed listingId,
        address indexed buyer,
        address seller,
        uint256 energyAmount,
        uint256 totalPrice
    );
    
    event ListingCancelled(uint256 indexed listingId, address indexed seller);
    
    // Modifiers
    modifier onlyPlatformOwner() {
        require(msg.sender == platformOwner, "Only platform owner can call this function");
        _;
    }
    
    modifier validListing(uint256 _listingId) {
        require(_listingId > 0 && _listingId < nextListingId, "Invalid listing ID");
        require(energyListings[_listingId].isActive, "Listing is not active");
        _;
    }
    
    constructor() {
        platformOwner = msg.sender;
    }
    
    /**
     * @dev Core Function 1: List energy for sale
     * @param _energyAmount Amount of energy in kWh
     * @param _pricePerUnit Price per kWh in wei
     * @param _location Location of energy source
     * @param _energySource Type of energy source
     */
    function listEnergy(
        uint256 _energyAmount,
        uint256 _pricePerUnit,
        string memory _location,
        string memory _energySource
    ) external {
        require(_energyAmount > 0, "Energy amount must be greater than 0");
        require(_pricePerUnit > 0, "Price per unit must be greater than 0");
        require(bytes(_location).length > 0, "Location cannot be empty");
        require(bytes(_energySource).length > 0, "Energy source cannot be empty");
        
        uint256 listingId = nextListingId++;
        
        energyListings[listingId] = EnergyListing({
            listingId: listingId,
            seller: msg.sender,
            energyAmount: _energyAmount,
            pricePerUnit: _pricePerUnit,
            timestamp: block.timestamp,
            isActive: true,
            location: _location,
            energySource: _energySource
        });
        
        userListings[msg.sender].push(listingId);
        
        emit EnergyListed(listingId, msg.sender, _energyAmount, _pricePerUnit, _location, _energySource);
    }
    
    /**
     * @dev Core Function 2: Purchase energy from a listing
     * @param _listingId ID of the energy listing to purchase
     * @param _energyAmount Amount of energy to purchase in kWh
     */
    function purchaseEnergy(uint256 _listingId, uint256 _energyAmount) 
        external 
        payable 
        validListing(_listingId) 
    {
        EnergyListing storage listing = energyListings[_listingId];
        
        require(msg.sender != listing.seller, "Cannot buy your own energy");
        require(_energyAmount > 0, "Energy amount must be greater than 0");
        require(_energyAmount <= listing.energyAmount, "Not enough energy available");
        
        uint256 totalPrice = _energyAmount * listing.pricePerUnit;
        require(msg.value >= totalPrice, "Insufficient payment");
        
        // Calculate platform fee
        uint256 platformFee = (totalPrice * platformFeePercent) / 1000;
        uint256 sellerAmount = totalPrice - platformFee;
        
        // Create trade record
        uint256 tradeId = nextTradeId++;
        energyTrades[tradeId] = EnergyTrade({
            tradeId: tradeId,
            listingId: _listingId,
            buyer: msg.sender,
            seller: listing.seller,
            energyAmount: _energyAmount,
            totalPrice: totalPrice,
            timestamp: block.timestamp,
            isCompleted: true
        });
        
        // Update listing
        listing.energyAmount -= _energyAmount;
        if (listing.energyAmount == 0) {
            listing.isActive = false;
        }
        
        // Update user records
        userTrades[msg.sender].push(tradeId);
        userTrades[listing.seller].push(tradeId);
        
        // Transfer payments
        userBalances[listing.seller] += sellerAmount;
        userBalances[platformOwner] += platformFee;
        
        // Refund excess payment
        if (msg.value > totalPrice) {
            payable(msg.sender).transfer(msg.value - totalPrice);
        }
        
        emit EnergyTraded(tradeId, _listingId, msg.sender, listing.seller, _energyAmount, totalPrice);
    }
    
    /**
     * @dev Core Function 3: Cancel an active energy listing
     * @param _listingId ID of the listing to cancel
     */
    function cancelListing(uint256 _listingId) external {
        require(_listingId > 0 && _listingId < nextListingId, "Invalid listing ID");
        EnergyListing storage listing = energyListings[_listingId];
        
        require(msg.sender == listing.seller, "Only seller can cancel the listing");
        require(listing.isActive, "Listing is already inactive");
        
        listing.isActive = false;
        
        emit ListingCancelled(_listingId, msg.sender);
    }
    
    /**
     * @dev Withdraw accumulated balance
     */
    function withdrawBalance() external {
        uint256 balance = userBalances[msg.sender];
        require(balance > 0, "No balance to withdraw");
        
        userBalances[msg.sender] = 0;
        payable(msg.sender).transfer(balance);
    }
    
    /**
     * @dev Get all active listings (view function)
     */
    function getActiveListings() external view returns (uint256[] memory) {
        uint256 activeCount = 0;
        
        // Count active listings
        for (uint256 i = 1; i < nextListingId; i++) {
            if (energyListings[i].isActive) {
                activeCount++;
            }
        }
        
        // Create array of active listing IDs
        uint256[] memory activeListings = new uint256[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 1; i < nextListingId; i++) {
            if (energyListings[i].isActive) {
                activeListings[index] = i;
                index++;
            }
        }
        
        return activeListings;
    }
    
    /**
     * @dev Get user's listings
     */
    function getUserListings(address _user) external view returns (uint256[] memory) {
        return userListings[_user];
    }
    
    /**
     * @dev Get user's trades
     */
    function getUserTrades(address _user) external view returns (uint256[] memory) {
        return userTrades[_user];
    }
    
    /**
     * @dev Update platform fee (only owner)
     */
    function updatePlatformFee(uint256 _newFeePercent) external onlyPlatformOwner {
        require(_newFeePercent <= 100, "Fee cannot exceed 10%"); // 100/1000 = 10%
        platformFeePercent = _newFeePercent;
    }
    
    /**
     * @dev Get platform statistics
     */
    function getPlatformStats() external view returns (
        uint256 totalListings,
        uint256 totalTrades,
        uint256 activeListings
    ) {
        totalListings = nextListingId - 1;
        totalTrades = nextTradeId - 1;
        
        uint256 active = 0;
        for (uint256 i = 1; i < nextListingId; i++) {
            if (energyListings[i].isActive) {
                active++;
            }
        }
        activeListings = active;
    }
}
