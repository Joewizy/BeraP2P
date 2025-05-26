// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.19;

// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// /**
//  * @author Joseph Gimba
//  * @title BeraP2P
//  * @dev A decentralized P2P exchange escrow with multi-trade support and token swap capability.
//  */
// contract BeraP2P is Ownable {
//     using SafeERC20 for IERC20;

//     error InvalidAmount();
//     error InvalidAddress();
//     error NotSellerOrBuyer();
//     error AlreadyReleased();
//     error SwapFailed();

//     IERC20 public immutable honey;
//     uint256 public escrowCount;

//     struct Escrow {
//         address buyer;
//         address seller;
//         uint256 amount;
//         uint256 timeCreated;
//         bool isReleased;
//     }

//     struct UserProfile {
//         uint256 totalTrades;
//         uint256 completedTrades;
//         uint256 totalTime;      // sum of completion times
//         string metadataURI;     // off-chain JSON
//     }

//     mapping(uint256 => Escrow) public escrows;
//     mapping(address => UserProfile) public profiles;

//     // Example interface for a DEX router on Berachain
//     interface IRouter {
//         function swapExactTokensForTokens(
//             uint256 amountIn,
//             uint256 amountOutMin,
//             address[] calldata path,
//             address to,
//             uint256 deadline
//         ) external returns (uint256[] memory amounts);
//     }

//     IRouter public immutable dexRouter;

//     event Deposited(uint256 indexed id, address indexed buyer, address indexed seller, uint256 amount);
//     event Released(uint256 indexed id, address indexed seller, uint256 timeTaken);
//     event Refunded(uint256 indexed id, address indexed buyer);
//     event Swapped(address indexed fromToken, uint256 amountIn, uint256 amountOut);

//     constructor(address _honey, address _router) Ownable() {
//         if (_honey == address(0) || _router == address(0)) revert InvalidAddress();
//         honey = IERC20(_honey);
//         dexRouter = IRouter(_router);
//     }

//     /**
//      * @notice Buyer deposits tokens into escrow for a given seller.
//      * @param amount The amount of honey tokens to escrow.
//      * @param seller The seller address.
//      */
//     function deposit(uint256 amount, address seller) external {
//         if (amount == 0) revert InvalidAmount();
//         if (seller == address(0) || seller == msg.sender) revert InvalidAddress();

//         honey.safeTransferFrom(msg.sender, address(this), amount);
//         escrowCount++;
//         uint256 id = escrowCount;

//         escrows[id] = Escrow({
//             buyer: msg.sender,
//             seller: seller,
//             amount: amount,
//             timeCreated: block.timestamp,
//             isReleased: false
//         });

//         profiles[msg.sender].totalTrades++;
//         profiles[seller].totalTrades++;

//         emit Deposited(id, msg.sender, seller, amount);
//     }

//     /**
//      * @notice Seller releases escrowed funds after trade completion.
//      * @param id The escrow ID.
//      */
//     function release(uint256 id) external {
//         Escrow storage e = escrows[id];
//         if (msg.sender != e.seller) revert NotSellerOrBuyer();
//         if (e.isReleased) revert AlreadyReleased();

//         e.isReleased = true;
//         honey.safeTransfer(e.seller, e.amount);

//         uint256 timeTaken = block.timestamp - e.timeCreated;
//         profiles[e.buyer].completedTrades++;
//         profiles[e.seller].completedTrades++;
//         profiles[e.buyer].totalTime += timeTaken;
//         profiles[e.seller].totalTime += timeTaken;

//         emit Released(id, e.seller, timeTaken);
//     }

//     /**
//      * @notice Owner refunds escrow to buyer (emergency).
//      * @param id The escrow ID.
//      */
//     function refund(uint256 id) external onlyOwner {
//         Escrow storage e = escrows[id];
//         if (e.isReleased) revert AlreadyReleased();

//         e.isReleased = true;
//         honey.safeTransfer(e.buyer, e.amount);

//         emit Refunded(id, e.buyer);
//     }

//     /**
//      * @notice Update user metadata URI.
//      * @param user The user address.
//      * @param metadataURI The new metadata URI.
//      */
//     function setMetaData(address user, string calldata metadataURI) external onlyOwner {
//         if (user == address(0)) revert InvalidAddress();
//         profiles[user].metadataURI = metadataURI;
//     }

//     /**
//      * @notice Swaps an arbitrary ERC20 token into honey using the configured DEX.
//      * @param tokenIn The address of the input token.
//      * @param amountIn The amount of input tokens.
//      * @param amountOutMin The minimum amount of honey tokens expected.
//      * @param deadline Unix timestamp after which the swap reverts.
//      */
//     function swapToHoney(
//         address tokenIn,
//         uint256 amountIn,
//         uint256 amountOutMin,
//         uint256 deadline
//     ) external {
//         if (tokenIn == address(0) || amountIn == 0) revert InvalidAddress();

//         IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
//         IERC20(tokenIn).safeApprove(address(dexRouter), amountIn);

//         address[] memory path = new address[](2);
//         path[0] = tokenIn;
//         path[1] = address(honey);

//         uint256[] memory amounts = dexRouter.swapExactTokensForTokens(
//             amountIn,
//             amountOutMin,
//             path,
//             msg.sender,
//             deadline
//         );

//         if (amounts[1] < amountOutMin) revert SwapFailed();
//         emit Swapped(tokenIn, amountIn, amounts[1]);
//     }

//     /**
//      * @notice Returns a user's average completion time (in seconds).
//      */
//     function getAverageTime(address user) external view returns (uint256) {
//         UserProfile storage p = profiles[user];
//         if (p.completedTrades == 0) return 0;
//         return p.totalTime / p.completedTrades;
//     }
// }
