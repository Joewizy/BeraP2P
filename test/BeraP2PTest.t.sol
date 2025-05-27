// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol"; 
import {BeraP2P} from "../src/BeraP2P.sol";
import {Honey} from "../src/mocks/Honey.sol";

contract BeraP2PTest is Test {
    BeraP2P beraP2P;
    Honey honey;

    address owner = address(this);
    address seller = makeAddr("seller");
    address buyer = makeAddr("buyer");
    uint256 private constant STARTING_MINT = 10000 * 10 ** 18;

    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant MAX_ACTIVE_ESCROWS = 100;
    uint256 public constant ESCROW_TIMEOUT = 48 hours;

    function setUp() external {
        honey = new Honey();
        beraP2P = new BeraP2P(address(honey));

        honey.mint(seller, STARTING_MINT);
        honey.mint(buyer, STARTING_MINT);
    }

    modifier userProfile() {
        vm.startPrank(seller);
        string memory username = "Joe";
        string memory email = "bera@gmail.com";
        string memory contact = "911";

        beraP2P.createUserProfile(username, email, contact);
        _;
    }

    modifier offerCreated() {
        uint256 amount = 1000 * PRICE_PRECISION;
        honey.approve(address(beraP2P), amount);
        beraP2P.depositToken(address(honey), amount);
        uint256 maxTradeAmount = 1000 * PRICE_PRECISION;
        uint256 minTradeAmount = 10 * PRICE_PRECISION;
        uint256 pricePerToken = 8000;
        string memory currencyCode = "NGN";
        string memory paymentMethod = "paypal";
        beraP2P.createOffer(maxTradeAmount, minTradeAmount, pricePerToken, currencyCode, paymentMethod);
        _;
    }

    modifier escrowCreated() {
        uint256 amount = 1000 * PRICE_PRECISION;
        vm.startPrank(buyer);
        string memory username2 = "John";
        string memory email2 = "beranigeria@gmail.com";
        string memory contact2 = "234";
        beraP2P.createUserProfile(username2, email2, contact2);
        beraP2P.createEscrow(1, amount);
        
        _;
    }

    function testCreateProfile() external {
        vm.startPrank(seller);
        string memory username = "Joe";
        string memory email = "bera@gmail.com";
        string memory contact = "911";

        beraP2P.createUserProfile(username, email, contact);

        BeraP2P.UserProfile memory profile = beraP2P.getUserProfile(seller);

        assertTrue(profile.exists, "Profile should exist");
        assertEq(profile.username, username, "Username does not match");
        assertEq(profile.email, email, "Email does not match");
        assertEq(profile.contact, contact, "Contact does not match");
    }

    function testUpdateUserProfile() external {
        vm.startPrank(seller);
        string memory username = "Joe";
        string memory email = "bera@gmail.com";
        string memory contact = "911";

        beraP2P.createUserProfile(username, email, contact);
        string memory updatedEmail = "beradevs@gmail.com";
        string memory updatedContact = "419";
        beraP2P.updateUserProfile(updatedEmail, updatedContact);

        BeraP2P.UserProfile memory profile = beraP2P.getUserProfile(seller);
        assertEq(profile.email, updatedEmail, "Email does not match");
        assertEq(profile.contact, updatedContact, "Contact does not match");
    }

    function testDepositHoneyToken() external userProfile {
        uint256 amount = 1000 * PRICE_PRECISION; // 1,000 Honey tokens
        honey.approve(address(beraP2P), amount);
        beraP2P.depositToken(address(honey), amount);

        assertEq(honey.balanceOf(address(beraP2P)), amount);
    }  

    function testCreateOffer() external userProfile offerCreated {
        uint256 amount = 1000 * 10 ** 18;
        honey.approve(address(beraP2P), amount);
        beraP2P.depositToken(address(honey), amount);

        uint256 maxTradeAmount = 1000 * PRICE_PRECISION;
        uint256 minTradeAmount = 10 * PRICE_PRECISION;
        uint256 pricePerToken = 8000;
        string memory currencyCode = "NGN";
        string memory paymentMethod = "paypal";
        beraP2P.createOffer(maxTradeAmount, minTradeAmount, pricePerToken, currencyCode, paymentMethod);

        BeraP2P.Offer memory offers = beraP2P.getOffer(1); // since it is the first offer
        assertEq(offers.seller, seller);
        assertEq(offers.maxTradeAmount, maxTradeAmount);
        assertEq(offers.minTradeAmount, minTradeAmount);
        assertEq(offers.pricePerToken, pricePerToken);
        assertEq(offers.currencyCode, currencyCode);
        assertEq(offers.paymentMethod, paymentMethod);
        assertEq(offers.activeEscrowCount, 0);
    }

    function testDeactivateOffer() external userProfile offerCreated {
        beraP2P.deactivateOffer(1);
        BeraP2P.Offer memory offers = beraP2P.getOffer(1);
        assertFalse(offers.isActive);
    }

    function testCreateEscrow() external userProfile offerCreated {
        uint256 honeyAmount = 1000 * 10 ** 18;
        uint256 amount = 1000 * PRICE_PRECISION;
        vm.startPrank(buyer);
        string memory username = "Joe";
        string memory email = "bera@gmail.com";
        string memory contact = "911";
        beraP2P.createUserProfile(username, email, contact);
        beraP2P.createEscrow(1, amount);

        BeraP2P.Offer memory offers = beraP2P.getOffer(1);
        BeraP2P.Escrow memory escrow  = beraP2P.getEscrow(1);
        uint256 expectedFiatAmount = (offers.pricePerToken * amount) / PRICE_PRECISION;

        assertEq(escrow.seller, seller);
        assertEq(escrow.buyer, buyer);
        assertEq(escrow.honeyAmount, amount);
        assertEq(escrow.offerId, 1);
        assert(escrow.status == BeraP2P.EscrowStatus.PENDING);
        assertEq(escrow.fiatAmount, expectedFiatAmount);
    }

    function testConfirmPayment() external userProfile offerCreated escrowCreated {
        vm.startPrank(seller);
        beraP2P.confirmPayment(1);
        BeraP2P.Offer memory offers = beraP2P.getOffer(1);
        BeraP2P.Escrow memory escrows = beraP2P.getEscrow(1);
        BeraP2P.UserProfile memory sellerProfile = beraP2P.getUserProfile(seller);
        BeraP2P.UserProfile memory buyerProfile = beraP2P.getUserProfile(buyer);
        uint256 expectedBuyerBalance = honey.balanceOf(buyer) - STARTING_MINT;

        assert(escrows.status == BeraP2P.EscrowStatus.COMPLETED);
        assertEq(offers.activeEscrowCount, 0);
        assertEq(sellerProfile.completedTrades, 1);
        assertEq(sellerProfile.totalTrades, 1);
        assertEq(expectedBuyerBalance, 1000 * PRICE_PRECISION);
    }
    
    function testRaiseDispute() external userProfile offerCreated escrowCreated {
        beraP2P.raiseDispute(1);
        BeraP2P.Escrow memory escrows = beraP2P.getEscrow(1);
        assert(escrows.status == BeraP2P.EscrowStatus.DISPUTED);
    }

    function testDisputeResolutionInFavorOfSeller() external userProfile offerCreated escrowCreated {
        beraP2P.raiseDispute(1);
        vm.startPrank(owner);
        bool favorBuyer = false;
        console.log("Seller balance(honey) before dispute", honey.balanceOf(seller));
        console.log("Buyer balance(honey) before dispute", honey.balanceOf(buyer));
        console.log("Bera contract balance(honey) before dispute", honey.balanceOf(address(beraP2P)));
        beraP2P.resolveDispute(1, favorBuyer);

        BeraP2P.Offer memory offers = beraP2P.getOffer(1);
        BeraP2P.Escrow memory escrows = beraP2P.getEscrow(1);
        BeraP2P.UserProfile memory sellerProfile = beraP2P.getUserProfile(seller);
        BeraP2P.UserProfile memory buyerProfile = beraP2P.getUserProfile(buyer);
        console.log("Seller balance(honey) after disputeResolved", honey.balanceOf(seller));
        console.log("Buyer balance(honey) after disputeResolved", honey.balanceOf(buyer));
        console.log("Bera contract balance(honey) before disputeResolved", honey.balanceOf(address(beraP2P)));
        uint256 amount = 1000 * PRICE_PRECISION;
        uint256 expectedBuyerBalance = honey.balanceOf(seller) - STARTING_MINT;

        assert(escrows.status == BeraP2P.EscrowStatus.COMPLETED);
        assertEq(offers.activeEscrowCount, 0);
        assertEq(sellerProfile.completedTrades, 1);
        assertEq(sellerProfile.totalTrades, 1);
        assertEq(sellerProfile.disputedTrades, 0);
        assertEq(expectedBuyerBalance, amount);
        // buyers profile
        assertEq(buyerProfile.completedTrades, 0);
        assertEq(buyerProfile.totalTrades, 1);
        assertEq(buyerProfile.disputedTrades, 1);
    }

    function testCancelEscrow() external userProfile offerCreated escrowCreated {
        beraP2P.cancelEscrow(1);
        BeraP2P.Escrow memory escrows = beraP2P.getEscrow(1);

        assert(escrows.status == BeraP2P.EscrowStatus.CANCELLED);
    }

    function testSellerCannotCreateOwnEscrow() external userProfile offerCreated {
        uint256 amount = 1000 * 10 ** 18;
        vm.expectRevert(BeraP2P.BeraP2P__CannotTradeWithSelf.selector);
        beraP2P.createEscrow(1, amount);
    }
}