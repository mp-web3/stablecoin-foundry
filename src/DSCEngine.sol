// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DSCEngine
 * @author Mattia Papa
 * @dev This contract implements the mechanisms to maintain a 1:1 peg with USD.
 * @dev The stablecoin is algoritmically stable, pegged to the dollar and overcollateralized by wBTC and wETH.
 * @notice This contract is the core of the DSC System. It handles all of the logic for:
 * @notice minting and redeeming DSC, as well as depositing and withdrawing collateral.
 */
contract DSCEngine is ReentrancyGuard {
    function depositCollateralAndMintDSC() external {}

    //// ERRORS ////
    error DSCEngine_NeedsMoreThanZero();
    error DSCEngine_NotAllowedToken();
    error DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine_TransferFailed();

    //// STATE VARIABLES ////

    /**
     * @dev Using the Chainlink Price Feeds to get the price of the collateral token
     * @dev instead of having a separate mapping(address => bool) to check if the token is supported
     * @dev we can use the priceFeed mapping to check if the token is supported
     */
    mapping(address token => address priceFeed) private s_priceFeeds;

    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;

    DecentralizedStableCoin private immutable i_dsc;

    //// EVENTS ////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    //// MODIFIERS ////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine_NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine_NotAllowedToken();
        }
        _;
    }

    //// CONSTRUCTOR ////

    /**
     * @dev The constructor sets the price feeds for the supported tokens
     * @param tokenAddresses The addresses of the supported tokens
     * @param priceFeedAddresses The addresses of the price feeds for the supported tokens
     * @param dscAddress The address of the DSC token
     * @notice The tokenAddresses and priceFeedAddresses arrays must be the same length
     * @notice The tokenAddresses and priceFeedAddresses arrays must be in the same order
     */
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine_TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    //// FUNCTIONS ////

    //// EXTERNAL FUNCTIONS ////
    /**
     * @notice Following CEI (Check Effects Interactions) pattern
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);

        if (!success) {
            revert DSCEngine_TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function mintDSC() external {}

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
