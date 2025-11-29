// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title Rental Property Smart Contract Registry
 * @dev A decentralized registry for rental properties with secure payment handling
 */

contract RentalPropertyRegistry {
    
    // Struct to represent a rental property
    struct Property {
        uint256 id;
        address payable owner;
        string title;
        string description;
        string location;
        uint256 pricePerDay; // in wei
        uint256 securityDeposit; // in wei
        bool isAvailable;
        bool exists;
    }
    
    // Struct to represent a rental agreement
    struct RentalAgreement {
        uint256 propertyId;
        address tenant;
        uint256 startDate;
        uint256 endDate;
        uint256 totalAmount;
        uint256 securityDeposit;
        bool isActive;
        bool securityDepositReturned;
    }
    
    // State variables
    address public admin;
    uint256 public propertyCounter;
    uint256 public agreementCounter;
    
    // Mappings
    mapping(uint256 => Property) public properties;
    mapping(uint256 => RentalAgreement) public rentalAgreements;
    mapping(uint256 => mapping(address => bool)) public tenantReviews;
    mapping(address => uint256[]) public userProperties;
    mapping(address => uint256[]) public userRentals;
    
    // Events
    event PropertyRegistered(
        uint256 indexed propertyId,
        address indexed owner,
        string title,
        uint256 pricePerDay
    );
    
    event PropertyAvailabilityUpdated(
        uint256 indexed propertyId,
        bool isAvailable
    );
    
    event RentalAgreementCreated(
        uint256 indexed agreementId,
        uint256 indexed propertyId,
        address indexed tenant,
        uint256 startDate,
        uint256 endDate,
        uint256 totalAmount
    );
    
    event PaymentProcessed(
        uint256 indexed agreementId,
        address indexed from,
        address indexed to,
        uint256 amount
    );
    
    event SecurityDepositReturned(
        uint256 indexed agreementId,
        address indexed tenant,
        uint256 amount
    );
    
    event ReviewSubmitted(
        uint256 indexed propertyId,
        address indexed tenant,
        uint256 rating
    );
    
    // Modifiers
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this action");
        _;
    }
    
    modifier onlyPropertyOwner(uint256 _propertyId) {
        require(properties[_propertyId].owner == msg.sender, "Only property owner can perform this action");
        _;
    }
    
    modifier propertyExists(uint256 _propertyId) {
        require(properties[_propertyId].exists, "Property does not exist");
        _;
    }
    
    modifier agreementExists(uint256 _agreementId) {
        require(rentalAgreements[_agreementId].tenant != address(0), "Rental agreement does not exist");
        _;
    }
    
    // Constructor
    constructor() {
        admin = msg.sender;
        propertyCounter = 0;
        agreementCounter = 0;
    }
    
    /**
     * @dev Register a new rental property
     * @param _title Property title
     * @param _description Property description
     * @param _location Property location
     * @param _pricePerDay Rental price per day in wei
     * @param _securityDeposit Security deposit amount in wei
     */
    function registerProperty(
        string memory _title,
        string memory _description,
        string memory _location,
        uint256 _pricePerDay,
        uint256 _securityDeposit
    ) external returns (uint256) {
        require(_pricePerDay > 0, "Price must be greater than 0");
        require(_securityDeposit >= 0, "Security deposit cannot be negative");
        
        propertyCounter++;
        
        Property memory newProperty = Property({
            id: propertyCounter,
            owner: payable(msg.sender),
            title: _title,
            description: _description,
            location: _location,
            pricePerDay: _pricePerDay,
            securityDeposit: _securityDeposit,
            isAvailable: true,
            exists: true
        });
        
        properties[propertyCounter] = newProperty;
        userProperties[msg.sender].push(propertyCounter);
        
        emit PropertyRegistered(propertyCounter, msg.sender, _title, _pricePerDay);
        
        return propertyCounter;
    }
    
    /**
     * @dev Update property availability
     * @param _propertyId ID of the property
     * @param _isAvailable New availability status
     */
    function updatePropertyAvailability(
        uint256 _propertyId,
        bool _isAvailable
    ) external propertyExists(_propertyId) onlyPropertyOwner(_propertyId) {
        properties[_propertyId].isAvailable = _isAvailable;
        
        emit PropertyAvailabilityUpdated(_propertyId, _isAvailable);
    }
    
    /**
     * @dev Create a rental agreement and process payment
     * @param _propertyId ID of the property to rent
     * @param _startDate Start date of rental (timestamp)
     * @param _endDate End date of rental (timestamp)
     */
    function createRentalAgreement(
        uint256 _propertyId,
        uint256 _startDate,
        uint256 _endDate
    ) external payable propertyExists(_propertyId) {
        Property storage property = properties[_propertyId];
        
        require(property.isAvailable, "Property is not available for rent");
        require(_startDate < _endDate, "Start date must be before end date");
        require(_startDate > block.timestamp, "Start date must be in the future");
        
        // Calculate rental duration and total amount
        uint256 rentalDays = (_endDate - _startDate) / 1 days;
        require(rentalDays > 0, "Rental period must be at least 1 day");
        
        uint256 totalRent = rentalDays * property.pricePerDay;
        uint256 totalAmount = totalRent + property.securityDeposit;
        
        require(msg.value == totalAmount, "Incorrect payment amount");
        
        agreementCounter++;
        
        RentalAgreement memory newAgreement = RentalAgreement({
            propertyId: _propertyId,
            tenant: msg.sender,
            startDate: _startDate,
            endDate: _endDate,
            totalAmount: totalAmount,
            securityDeposit: property.securityDeposit,
            isActive: true,
            securityDepositReturned: false
        });
        
        rentalAgreements[agreementCounter] = newAgreement;
        userRentals[msg.sender].push(agreementCounter);
        
        // Mark property as unavailable
        property.isAvailable = false;
        
        // Transfer rental amount to property owner (hold security deposit in contract)
        property.owner.transfer(totalRent);
        
        emit RentalAgreementCreated(
            agreementCounter,
            _propertyId,
            msg.sender,
            _startDate,
            _endDate,
            totalAmount
        );
        
        emit PaymentProcessed(
            agreementCounter,
            msg.sender,
            property.owner,
            totalRent
        );
    }
    
    /**
     * @dev Return security deposit after rental period ends
     * @param _agreementId ID of the rental agreement
     */
    function returnSecurityDeposit(
        uint256 _agreementId
    ) external agreementExists(_agreementId) {
        RentalAgreement storage agreement = rentalAgreements[_agreementId];
        Property storage property = properties[agreement.propertyId];
        
        require(
            msg.sender == property.owner || msg.sender == admin,
            "Only property owner or admin can return deposit"
        );
        require(agreement.isActive, "Rental agreement is not active");
        require(block.timestamp > agreement.endDate, "Rental period has not ended yet");
        require(!agreement.securityDepositReturned, "Security deposit already returned");
        
        agreement.securityDepositReturned = true;
        
        // Return security deposit to tenant
        payable(agreement.tenant).transfer(agreement.securityDeposit);
        
        // Mark property as available again
        property.isAvailable = true;
        agreement.isActive = false;
        
        emit SecurityDepositReturned(_agreementId, agreement.tenant, agreement.securityDeposit);
    }
    
    /**
     * @dev Get all properties
     * @return Array of property IDs
     */
    function getAllProperties() external view returns (uint256[] memory) {
        uint256[] memory propertyIds = new uint256[](propertyCounter);
        for (uint256 i = 1; i <= propertyCounter; i++) {
            propertyIds[i - 1] = i;
        }
        return propertyIds;
    }
    
    /**
     * @dev Get properties by owner
     * @param _owner Address of the property owner
     * @return Array of property IDs owned by the address
     */
    function getPropertiesByOwner(address _owner) external view returns (uint256[] memory) {
        return userProperties[_owner];
    }
    
    /**
     * @dev Get rental agreements by tenant
     * @param _tenant Address of the tenant
     * @return Array of rental agreement IDs
     */
    function getRentalsByTenant(address _tenant) external view returns (uint256[] memory) {
        return userRentals[_tenant];
    }
    
    /**
     * @dev Get property details
     * @param _propertyId ID of the property
     * @return Property details
     */
    function getPropertyDetails(
        uint256 _propertyId
    ) external view propertyExists(_propertyId) returns (Property memory) {
        return properties[_propertyId];
    }
    
    /**
     * @dev Get rental agreement details
     * @param _agreementId ID of the rental agreement
     * @return Rental agreement details
     */
    function getRentalAgreementDetails(
        uint256 _agreementId
    ) external view agreementExists(_agreementId) returns (RentalAgreement memory) {
        return rentalAgreements[_agreementId];
    }
    
    /**
     * @dev Emergency function to recover stuck funds (admin only)
     */
    function recoverStuckFunds() external onlyAdmin {
        payable(admin).transfer(address(this).balance);
    }
}
