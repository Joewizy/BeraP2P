// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title BeraP2P
 * @author Joseph Gimba
 * @notice A decentralized peer-to-peer exchange escrow contract built on Berachain
 * @dev Facilitates secure P2P trading with escrow protection and dispute resolution
 */
contract BeraP2P is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/
    error BeraP2P__InvalidAmount();
    error BeraP2P__InvalidAddress();
    error BeraP2P__Unauthorized();
    error BeraP2P__InvalidState();
    error BeraP2P__ProfileRequired();
    error BeraP2P__ProfileAlreadyExists();
    error BeraP2P__OfferNotFound();
    error BeraP2P__OfferInactive();
    error BeraP2P__EscrowNotFound();
    error BeraP2P__TradeAmountTooLow();
    error BeraP2P__TradeAmountTooHigh();
    error BeraP2P__CannotTradeWithSelf();
    error BeraP2P__InsufficientBalance();
    error BeraP2P__ActiveEscrowsExist();
    error BeraP2P__InvalidPriceParameters();
    error BeraP2P__EscrowTimeout();

    /*//////////////////////////////////////////////////////////////
                              CONSTANTS
    //////////////////////////////////////////////////////////////*/
    IERC20 public immutable honey;
    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant MAX_ACTIVE_ESCROWS = 100;
    uint256 public constant ESCROW_TIMEOUT = 48 hours;

    /*//////////////////////////////////////////////////////////////
                                ENUMS
    //////////////////////////////////////////////////////////////*/
    enum EscrowStatus {
        PENDING,
        COMPLETED,
        CANCELLED,
        DISPUTED
    }

    /*//////////////////////////////////////////////////////////////
                               STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct UserProfile {
        string username;
        string email;
        string contact;
        uint256 joinedDate;
        uint256 totalTrades;
        uint256 completedTrades;
        uint256 disputedTrades;
        uint256 averageSettlementTime;
        bool exists;
    }

    struct Offer {
        address seller;
        uint256 maxTradeAmount;
        uint256 minTradeAmount;
        uint256 pricePerToken;
        string currencyCode;
        string paymentMethod;
        uint256 activeEscrowCount;
        bool isActive;
        uint256 createdAt;
    }

    struct Escrow {
        address buyer;
        address seller;
        uint256 honeyAmount;
        uint256 fiatAmount;
        uint256 createdAt;
        uint256 offerId;
        EscrowStatus status;
    }

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 private nextOfferId = 1;
    uint256 private nextEscrowId = 1;

    mapping(uint256 => Offer) private offers;
    mapping(uint256 => Escrow) private escrows;
    mapping(address => UserProfile) private userProfiles;
    mapping(address => uint256[]) private userOffers;
    mapping(address => uint256[]) private userEscrows;
    mapping(address => uint256) private sellerDeposits;
    mapping(address => uint256) private totalLocked;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    event UserProfileCreated(address indexed user, string username, uint256 timestamp);
    event UserProfileUpdated(address indexed user, string email, string contact, uint256 timestamp);
    event OfferCreated(
        uint256 offerId,
        address indexed seller,
        uint256 maxAmount,
        uint256 minAmount,
        uint256 pricePerToken,
        string currencyCode
    );
    event OfferDeactivated(uint256 offerId, address indexed seller);
    event EscrowCreated(
        uint256 escrowId,
        uint256 offerId,
        address indexed buyer,
        address seller,
        uint256 honeyAmount,
        uint256 fiatAmount
    );
    event PaymentConfirmed(uint256 escrowId, address indexed seller, uint256 settlementTime);
    event EscrowCancelled(uint256 escrowId, address indexed buyer);
    event DisputeRaised(uint256 escrowId, address indexed disputant);
    event DisputeResolved(uint256 escrowId, address indexed winner, bool favoredBuyer);
    event WithdrawFunds(address indexed user, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks that the caller has a profile created
    modifier profileExists() {
        if (!userProfiles[msg.sender].exists) revert BeraP2P__ProfileRequired();
        _;
    }

    /// @notice Checks offer existence and active status
    modifier validActiveOffer(uint256 offerId) {
        if (offerId == 0 || offerId >= nextOfferId) revert BeraP2P__OfferNotFound();
        Offer storage offer = offers[offerId];
        if (!offer.isActive) revert BeraP2P__OfferInactive();
        _;
    }

    /// @notice Checks escrow existence and PENDING status
    modifier validPendingEscrow(uint256 escrowId) {
        if (escrowId == 0 || escrowId >= nextEscrowId) {
            revert BeraP2P__EscrowNotFound();
        }
        Escrow storage escrow = escrows[escrowId];
        if (escrow.status != EscrowStatus.PENDING) {
            revert BeraP2P__InvalidState();
        }
        _;
    }

    constructor(address _honey) Ownable(msg.sender) {
        if (_honey == address(0)) revert BeraP2P__InvalidAddress();
        honey = IERC20(_honey);
    }

    /**
     * @notice Creates a user profile required for trading
     */
    function createUserProfile(string calldata username, string calldata email, string calldata contact) external {
        if (userProfiles[msg.sender].exists) {
            revert BeraP2P__ProfileAlreadyExists();
        }
        if (bytes(username).length == 0 || bytes(email).length == 0 || bytes(contact).length == 0) {
            revert BeraP2P__InvalidAmount();
        }

        userProfiles[msg.sender] = UserProfile({
            username: username,
            email: email,
            contact: contact,
            joinedDate: block.timestamp,
            totalTrades: 0,
            completedTrades: 0,
            disputedTrades: 0,
            averageSettlementTime: 0,
            exists: true
        });

        emit UserProfileCreated(msg.sender, username, block.timestamp);
    }

    /**
     * @notice Updates the user profile's contact information
     */
    function updateUserProfile(string calldata email, string calldata contact) external profileExists {
        if (bytes(email).length == 0 || bytes(contact).length == 0) {
            revert BeraP2P__InvalidAmount();
        }
        UserProfile storage profile = userProfiles[msg.sender];
        profile.email = email;
        profile.contact = contact;

        emit UserProfileUpdated(msg.sender, email, contact, block.timestamp);
    }

    /**
     * @notice A seller deposit funds into the escrow contract
     */
    function depositToken(address token, uint256 amount) external {
        if (amount == 0) {
            revert BeraP2P__InvalidAmount();
        }
        if (token == address(0)) {
            revert BeraP2P__InvalidAddress();
        }

        honey.safeTransferFrom(msg.sender, address(this), amount);
        sellerDeposits[msg.sender] += amount;
    }

    /**
     * @notice Creates a new trading offer
     */
    function createOffer(
        uint256 maxTradeAmount,
        uint256 minTradeAmount,
        uint256 pricePerToken,
        string calldata currencyCode,
        string calldata paymentMethod
    ) external profileExists nonReentrant {
        if (maxTradeAmount == 0 || minTradeAmount == 0) {
            revert BeraP2P__InvalidAmount();
        }
        if (maxTradeAmount < minTradeAmount) {
            revert BeraP2P__InvalidPriceParameters();
        }
        if (pricePerToken == 0) {
            revert BeraP2P__InvalidPriceParameters();
        }
        if (bytes(currencyCode).length == 0 || bytes(paymentMethod).length == 0) {
            revert BeraP2P__InvalidAmount();
        }
        if (sellerDeposits[msg.sender] < maxTradeAmount) {
            revert BeraP2P__InsufficientBalance();
        }

        uint256 offerId = nextOfferId++;
        offers[offerId] = Offer({
            seller: msg.sender,
            maxTradeAmount: maxTradeAmount,
            minTradeAmount: minTradeAmount,
            pricePerToken: pricePerToken,
            currencyCode: currencyCode,
            paymentMethod: paymentMethod,
            activeEscrowCount: 0,
            isActive: true,
            createdAt: block.timestamp
        });

        userOffers[msg.sender].push(offerId);

        emit OfferCreated(offerId, msg.sender, maxTradeAmount, minTradeAmount, pricePerToken, currencyCode);
    }

    /**
     * @notice Deactivates an offer if no active escrows exist
     */
    function deactivateOffer(uint256 offerId) external {
        if (offerId == 0 || offerId >= nextOfferId) {
            revert BeraP2P__OfferNotFound();
        }
        Offer storage offer = offers[offerId];

        if (!offer.isActive) {
            revert BeraP2P__OfferInactive();
        }
        if (offer.seller != msg.sender) {
            revert BeraP2P__Unauthorized();
        }
        if (offer.activeEscrowCount > 0) {
            revert BeraP2P__ActiveEscrowsExist();
        }

        offer.isActive = false;
        emit OfferDeactivated(offerId, msg.sender);
    }

    /**
     * @notice Creates an escrow from an existing offer
     */
    function createEscrow(uint256 offerId, uint256 honeyAmount)
        external
        profileExists
        nonReentrant
        validActiveOffer(offerId)
    {
        Offer storage offer = offers[offerId];
        // Check if seller has enough unlocked funds for this escrow
        if (sellerDeposits[offer.seller] - totalLocked[offer.seller] < honeyAmount) {
            revert BeraP2P__InsufficientBalance();
        }
        if (offer.seller == msg.sender) {
            revert BeraP2P__CannotTradeWithSelf();
        }
        if (honeyAmount < offer.minTradeAmount) {
            revert BeraP2P__TradeAmountTooLow();
        }
        if (honeyAmount > offer.maxTradeAmount) {
            revert BeraP2P__TradeAmountTooHigh();
        }
        if (offer.activeEscrowCount >= MAX_ACTIVE_ESCROWS) {
            revert BeraP2P__InvalidState();
        }

        uint256 fiatAmount = (honeyAmount * offer.pricePerToken) / PRICE_PRECISION;

        offer.activeEscrowCount++;
        totalLocked[offer.seller] += honeyAmount; // Lock the funds for this escrow

        uint256 escrowId = nextEscrowId++;
        escrows[escrowId] = Escrow({
            buyer: msg.sender,
            seller: offer.seller,
            honeyAmount: honeyAmount,
            fiatAmount: fiatAmount,
            createdAt: block.timestamp,
            offerId: offerId,
            status: EscrowStatus.PENDING
        });

        userEscrows[msg.sender].push(escrowId);
        userEscrows[offer.seller].push(escrowId);

        userProfiles[msg.sender].totalTrades++;
        userProfiles[offer.seller].totalTrades++;

        emit EscrowCreated(escrowId, offerId, msg.sender, offer.seller, honeyAmount, fiatAmount);
    }

    /**
     * @notice Seller confirms payment and releases HONEY to buyer
     * @dev Includes timeout check to prevent indefinite locking of funds
     */
    function confirmPayment(uint256 escrowId) external nonReentrant validPendingEscrow(escrowId) {
        Escrow storage escrow = escrows[escrowId];

        if (escrow.seller != msg.sender) {
            revert BeraP2P__Unauthorized();
        }
        if (block.timestamp > escrow.createdAt + ESCROW_TIMEOUT) {
            revert BeraP2P__EscrowTimeout();
        }

        escrow.status = EscrowStatus.COMPLETED;
        offers[escrow.offerId].activeEscrowCount--;
        sellerDeposits[escrow.seller] -= escrow.honeyAmount;
        totalLocked[escrow.seller] -= escrow.honeyAmount;

        UserProfile storage sellerProfile = userProfiles[escrow.seller];
        sellerProfile.completedTrades++;

        uint256 settlementTime = block.timestamp - escrow.createdAt;
        if (sellerProfile.completedTrades == 1) {
            sellerProfile.averageSettlementTime = settlementTime;
        } else {
            uint256 totalTime = sellerProfile.averageSettlementTime * (sellerProfile.completedTrades - 1);
            sellerProfile.averageSettlementTime = (totalTime + settlementTime) / sellerProfile.completedTrades;
        }

        honey.safeTransfer(escrow.buyer, escrow.honeyAmount);

        emit PaymentConfirmed(escrowId, msg.sender, settlementTime);
    }

    /**
     * @notice Buyer cancels escrow before payment is confirmed
     */
    function cancelEscrow(uint256 escrowId) external nonReentrant validPendingEscrow(escrowId) {
        Escrow storage escrow = escrows[escrowId];
        if (escrow.buyer != msg.sender) {
            revert BeraP2P__Unauthorized();
        }

        escrow.status = EscrowStatus.CANCELLED;
        offers[escrow.offerId].activeEscrowCount--;
        totalLocked[escrow.seller] -= escrow.honeyAmount;

        emit EscrowCancelled(escrowId, msg.sender);
    }

    /**
     * @notice Raise a dispute for an escrow in PENDING state
     */
    function raiseDispute(uint256 escrowId) external validPendingEscrow(escrowId) {
        Escrow storage escrow = escrows[escrowId];
        if (msg.sender != escrow.buyer && msg.sender != escrow.seller) {
            revert BeraP2P__Unauthorized();
        }
        escrow.status = EscrowStatus.DISPUTED;

        emit DisputeRaised(escrowId, msg.sender);
    }

    /**
     * @notice Resolve dispute in favor of buyer or seller
     * @dev Only owner or dispute arbitrator can call this
     */
    function resolveDispute(uint256 escrowId, bool favorBuyer) external onlyOwner {
        Escrow storage escrow = escrows[escrowId];
        if (escrow.status != EscrowStatus.DISPUTED) {
            revert BeraP2P__InvalidState();
        }

        escrow.status = EscrowStatus.COMPLETED;
        offers[escrow.offerId].activeEscrowCount--;
        totalLocked[escrow.seller] -= escrow.honeyAmount;

        UserProfile storage buyerProfile = userProfiles[escrow.buyer];
        UserProfile storage sellerProfile = userProfiles[escrow.seller];

        if (favorBuyer) {
            buyerProfile.completedTrades++;
            sellerProfile.disputedTrades++;
            honey.safeTransfer(escrow.buyer, escrow.honeyAmount);
        } else {
            sellerProfile.completedTrades++;
            buyerProfile.disputedTrades++;
        }

        emit DisputeResolved(escrowId, favorBuyer ? escrow.buyer : escrow.seller, favorBuyer);
    }

    /**
     * @notice Allows sellers to withdraw unallocated HONEY tokens
     */
    function withdrawDeposit(uint256 amount) external nonReentrant {
        if (amount == 0) {
            revert BeraP2P__InvalidAmount();
        }
        uint256 available = sellerDeposits[msg.sender] - totalLocked[msg.sender];
        if (amount > available) {
            revert BeraP2P__InsufficientBalance();
        }
        sellerDeposits[msg.sender] -= amount;
        honey.safeTransfer(msg.sender, amount);
        emit WithdrawFunds(msg.sender, amount);
    }

    /*//////////////////////////////////////////////////////////////
                         VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getOffer(uint256 offerId) external view returns (Offer memory) {
        return offers[offerId];
    }

    function getEscrow(uint256 escrowId) external view returns (Escrow memory) {
        return escrows[escrowId];
    }

    function getUserProfile(address user) external view returns (UserProfile memory) {
        return userProfiles[user];
    }

    function getUserOffers(address user) external view returns (uint256[] memory) {
        return userOffers[user];
    }

    function getUserEscrows(address user) external view returns (uint256[] memory) {
        return userEscrows[user];
    }

    function getSellerDeposit(address seller) external view returns (uint256) {
        return sellerDeposits[seller];
    }
}
