// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import "@inco/lightning/src/Lib.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "../ConfidentialERC20.sol";

contract ConfidentialUnicrow is Ownable2Step {
    
    
    event EscrowCreated(uint256 indexed escrowId, address indexed buyer, address indexed seller);
    event PaymentReleased(uint256 indexed escrowId, address indexed buyer, address indexed seller);
    event DisputeInitiated(uint256 indexed escrowId, address indexed buyer, address indexed seller);
    event DisputeResolved(uint256 indexed escrowId, address indexed buyer, address indexed seller, uint256 buyerAmount, uint256 sellerAmount);
    event FundsClaimed(uint256 indexed escrowId, address indexed seller, uint256 amount);
    event EscrowCancelled(uint256 indexed escrowId, address indexed buyer);


    struct Escrow {
        address buyer;
        address seller;
        address arbitrator;
        euint256 amount;
        uint256 challengePeriod;
        uint256 createdAt;
        bool isDisputed;
        bool isResolved;
        bool isClaimed;
        bool isCancelled;
    }

    struct EscrowInput {
        address seller;
        address arbitrator;
        bytes encryptedAmount;
        uint256 challengePeriod;
    }

    uint256 public nextEscrowId;
    mapping(uint256 => Escrow) public escrows;
    mapping(address => uint256[]) public buyerEscrows;
    mapping(address => uint256[]) public sellerEscrows;
    
    uint256 public constant ARBITRATOR_FEE_BPS = 100; // 1%
    uint256 public constant PLATFORM_FEE_BPS = 50;    // 0.5%

    ConfidentialERC20 public immutable confidentialToken;

    constructor(address _confidentialToken) Ownable(msg.sender) {
        confidentialToken = ConfidentialERC20(_confidentialToken);
    }

    /**
     * @dev Create a new escrow
     * @param input EscrowInput struct containing escrow details
     * @return escrowId The ID of the created escrow
     */
    function pay(EscrowInput calldata input) external returns (uint256) {
        require(input.seller != address(0), "Invalid seller address");
        require(input.arbitrator != address(0), "Invalid arbitrator address");
        require(input.challengePeriod > 0, "Challenge period must be positive");
        require(input.seller != msg.sender, "Buyer cannot be seller");
        require(input.arbitrator != msg.sender, "Buyer cannot be arbitrator");

        uint256 escrowId = nextEscrowId++;
        
        euint256 encryptedAmount = e.newEuint256(input.encryptedAmount, msg.sender);
        
        e.allow(encryptedAmount, address(confidentialToken));
        e.allow(encryptedAmount, address(this));
        
        require(
            confidentialToken.transferFrom(msg.sender, address(this), encryptedAmount),
            "Transfer failed"
        );

        escrows[escrowId] = Escrow({
            buyer: msg.sender,
            seller: input.seller,
            arbitrator: input.arbitrator,
            amount: encryptedAmount,
            challengePeriod: input.challengePeriod,
            createdAt: block.timestamp,
            isDisputed: false,
            isResolved: false,
            isClaimed: false,
            isCancelled: false
        });

        e.allow(escrows[escrowId].amount, address(this));
        e.allow(escrows[escrowId].amount, msg.sender);
        e.allow(escrows[escrowId].amount, input.seller);
        e.allow(escrows[escrowId].amount, input.arbitrator);

        buyerEscrows[msg.sender].push(escrowId);
        sellerEscrows[input.seller].push(escrowId);

        emit EscrowCreated(escrowId, msg.sender, input.seller);
        return escrowId;
    }

    /**
     * @dev Release payment to seller (buyer's action)
     * @param escrowId The ID of the escrow to release
     */
    function release(uint256 escrowId) external {
        Escrow storage escrow = escrows[escrowId];
        require(msg.sender == escrow.buyer, "Only buyer can release");
        require(!escrow.isDisputed, "Escrow is disputed");
        require(!escrow.isResolved, "Escrow is resolved");
        require(!escrow.isClaimed, "Escrow already claimed");
        require(!escrow.isCancelled, "Escrow is cancelled");

        e.allow(escrow.amount, address(confidentialToken));
        e.allow(escrow.amount, escrow.buyer);
        e.allow(escrow.amount, escrow.seller);
        
        require(
            confidentialToken.transfer(escrow.seller, escrow.amount),
            "Transfer to seller failed"
        );

        escrow.isClaimed = true;
        emit PaymentReleased(escrowId, escrow.buyer, escrow.seller);
    }

    /**
     * @dev Initiate dispute (buyer's action)
     * @param escrowId The ID of the escrow to dispute
     */
    function dispute(uint256 escrowId) external {
        Escrow storage escrow = escrows[escrowId];
        require(msg.sender == escrow.buyer, "Only buyer can dispute");
        require(!escrow.isDisputed, "Escrow already disputed");
        require(!escrow.isResolved, "Escrow already resolved");
        require(!escrow.isClaimed, "Escrow already claimed");
        require(!escrow.isCancelled, "Escrow is cancelled");

        escrow.isDisputed = true;
        emit DisputeInitiated(escrowId, escrow.buyer, escrow.seller);
    }

    /**
     * @dev Resolve dispute (arbitrator's action)
     * @param escrowId The ID of the escrow to resolve
     * @param buyerAmount Encrypted amount to return to buyer
     * @param sellerAmount Encrypted amount to send to seller
     */
    function resolve(
        uint256 escrowId,
        bytes calldata buyerAmount,
        bytes calldata sellerAmount
    ) external {
        Escrow storage escrow = escrows[escrowId];
        require(msg.sender == escrow.arbitrator, "Only arbitrator can resolve");
        require(escrow.isDisputed, "Escrow not disputed");
        require(!escrow.isResolved, "Escrow already resolved");
        require(!escrow.isClaimed, "Escrow already claimed");
        require(!escrow.isCancelled, "Escrow is cancelled");

        euint256 encryptedBuyerAmount = e.newEuint256(buyerAmount, escrow.buyer);
        euint256 encryptedSellerAmount = e.newEuint256(sellerAmount, escrow.seller);

        e.allow(encryptedBuyerAmount, address(confidentialToken));
        e.allow(encryptedBuyerAmount, escrow.buyer);
        e.allow(encryptedSellerAmount, address(confidentialToken));
        e.allow(encryptedSellerAmount, escrow.seller);

        e.allow(escrow.amount, msg.sender);

        require(
            confidentialToken.transfer(escrow.buyer, encryptedBuyerAmount),
            "Transfer to buyer failed"
        );
        require(
            confidentialToken.transfer(escrow.seller, encryptedSellerAmount),
            "Transfer to seller failed"
        );

        escrow.isResolved = true;
        escrow.isClaimed = true;

        emit DisputeResolved(escrowId, escrow.buyer, escrow.seller, 0, 0); // Amounts are encrypted
    }

    /**
     * @dev Claim funds after challenge period (seller's action)
     * @param escrowId The ID of the escrow to claim
     */
    function claim(uint256 escrowId) external {
        Escrow storage escrow = escrows[escrowId];
        require(msg.sender == escrow.seller, "Only seller can claim");
        require(!escrow.isDisputed, "Escrow is disputed");
        require(!escrow.isResolved, "Escrow is resolved");
        require(!escrow.isClaimed, "Escrow already claimed");
        require(!escrow.isCancelled, "Escrow is cancelled");
        require(
            block.timestamp >= escrow.createdAt + escrow.challengePeriod,
            "Challenge period not ended"
        );

        e.allow(escrow.amount, address(confidentialToken));
        e.allow(escrow.amount, escrow.buyer);
        e.allow(escrow.amount, escrow.seller);
        
        require(
            confidentialToken.transfer(escrow.seller, escrow.amount),
            "Transfer to seller failed"
        );

        escrow.isClaimed = true;
        emit FundsClaimed(escrowId, escrow.seller, 0); // Amount is encrypted
    }

    /**
     * @dev Cancel escrow and return funds to buyer (buyer's action before challenge period ends)
     * @param escrowId The ID of the escrow to cancel
     */
    function cancel(uint256 escrowId) external {
        Escrow storage escrow = escrows[escrowId];
        require(msg.sender == escrow.buyer, "Only buyer can cancel");
        require(!escrow.isDisputed, "Escrow is disputed");
        require(!escrow.isResolved, "Escrow is resolved");
        require(!escrow.isClaimed, "Escrow already claimed");
        require(!escrow.isCancelled, "Escrow is cancelled");
        require(
            block.timestamp < escrow.createdAt + escrow.challengePeriod,
            "Challenge period ended"
        );

        e.allow(escrow.amount, address(confidentialToken));
        e.allow(escrow.amount, escrow.buyer);
        e.allow(escrow.amount, escrow.seller);
        

        require(
            confidentialToken.transfer(escrow.buyer, escrow.amount),
            "Transfer to buyer failed"
        );

        escrow.isCancelled = true;
        emit EscrowCancelled(escrowId, escrow.buyer);
    }

    /**
     * @dev Get escrow details
     * @param escrowId The ID of the escrow
     * @return Escrow struct
     */
    function getEscrow(uint256 escrowId) external view returns (Escrow memory) {
        return escrows[escrowId];
    }

    /**
     * @dev Get escrow IDs for a buyer
     * @param buyer The buyer address
     * @return Array of escrow IDs
     */
    function getBuyerEscrows(address buyer) external view returns (uint256[] memory) {
        return buyerEscrows[buyer];
    }

    /**
     * @dev Get escrow IDs for a seller
     * @param seller The seller address
     * @return Array of escrow IDs
     */
    function getSellerEscrows(address seller) external view returns (uint256[] memory) {
        return sellerEscrows[seller];
    }

    /**
     * @dev Check if escrow can be claimed
     * @param escrowId The ID of the escrow
     * @return bool True if escrow can be claimed
     */
    function canClaim(uint256 escrowId) external view returns (bool) {
        Escrow storage escrow = escrows[escrowId];
        return !escrow.isDisputed &&
               !escrow.isResolved &&
               !escrow.isClaimed &&
               !escrow.isCancelled &&
               block.timestamp >= escrow.createdAt + escrow.challengePeriod;
    }

    /**
     * @dev Check if escrow can be cancelled
     * @param escrowId The ID of the escrow
     * @return bool True if escrow can be cancelled
     */
    function canCancel(uint256 escrowId) external view returns (bool) {
        Escrow storage escrow = escrows[escrowId];
        return !escrow.isDisputed &&
               !escrow.isResolved &&
               !escrow.isClaimed &&
               !escrow.isCancelled &&
               block.timestamp < escrow.createdAt + escrow.challengePeriod;
    }


}

