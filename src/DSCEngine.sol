// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Mattia Papa
 * @notice This contract is the core of the DSC System. It handles all of the logic for:
 * @notice minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @dev This contract implements the mechanisms to maintain a 1:1 peg with USD.
 * @dev The stablecoin is algoritmically stable, pegged to the dollar and overcollateralized by wBTC and wETH.
 */
contract DSCEngine is ReentrancyGuard {
    //// ERRORS ////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine_NotAllowedToken();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TransferFailed();
    error DSCEngine__MintFailed();
    error DSCEngine__BelowThresholdHealthFactor(uint256 userHealthFactor);
    error DSCEngine__NotBelowThresholdHealthFactor();
    error DSCEngine__NotImprovedHelthFactor();

    //// STATE VARIABLES ////

    /**
     * @dev FEED_PRECISION is used to convert the price from the Chainlink Price Feeds to the desired precision
     * @dev PRECISION is used to convert the price from the Chainlink Price Feeds to the desired precision
     * @dev LIQUIDATION_THRESHOLD is the overcollateralization ratio
     * @dev LIQUIDATION_PRECISION is used to convert the liquidation threshold to the desired precision
     * @dev Since the price of ETH/USD and BTC/USD returned by Chainlink Price Feed is expressed with 8 decimals
     * @dev and we use as standard ETH decimals (1e18), we need to multiply the price returned by Chainlink for 1e10 (FEED_PRECISION)
     * @dev to get the price in the desired precision (1e18).
     */
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralization
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATOR_BONUS = 10; // This mean a 10% bonus for the liquidator

    /**
     * @dev Using the Chainlink Price Feeds to get the price of the collateral token
     * @dev instead of having a separate mapping(address => bool) to check if the token is supported
     * @dev we can use the priceFeed mapping to check if the token is supported
     */
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 mintedAmountDSC) private s_mintedDSC;

    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    //// EVENTS ////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    //// MODIFIERS ////

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
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
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    //// FUNCTIONS ////

    //// EXTERNAL FUNCTIONS ////

    /**
     * @notice Deposit collateral and mint DSC in one transaction
     * @param tokenCollateralAddress The addresses of the supported tokens
     * @param amountCollateral The amount of collateral to deposit
     * @param amountDSCToMint The amount of DSC to mint
     */
    function depositCollateralAndMintDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDSCToMint
    ) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDSC(amountDSCToMint);
    }

    /**
     * @notice Following CEI (Check Effects Interactions) pattern
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /**
     * @notice Burn DSC and redeem collateral in one transaction
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateralToRedeem The amount of collateral to redeem
     * @param amountDSCToBurn The amount of DSC to burn
     */
    function burnDSCAndRedeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateralToRedeem,
        uint256 amountDSCToBurn
    ) external {
        burnDSC(amountDSCToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateralToRedeem);
        // Check for helth factor is in redeemCollateral() so no need to add it again here
    }

    // 1. health factor must be above the threshold (1) after the collateral is redeemed
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        moreThanZero(amountCollateral)
        nonReentrant
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);

        _revertIfHealthFactorBelowThreshold(msg.sender);
    }

    /**
     * @notice Mint DSC. Not all the deposited collateral has to be used to mint DSC.
     * @param amountDSCToMint The amount of DSC to mint
     */
    function mintDSC(uint256 amountDSCToMint) public moreThanZero(amountDSCToMint) nonReentrant {
        s_mintedDSC[msg.sender] += amountDSCToMint;

        _revertIfHealthFactorBelowThreshold(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDSCToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDSC(uint256 amountDSCToBurn) public moreThanZero(amountDSCToBurn) {
        _burnDSC(amountDSCToBurn, msg.sender, msg.sender);
        _revertIfHealthFactorBelowThreshold(msg.sender);
    }

    // If someone is almost undercollateralized, anyone can liquidate the position
    // Example: 75$ worth of ETH, backing 100$ worth of DSC
    // Health factor = 75 / 100 = 0.75 !!!Below the threshold!!!
    // Liquidator burns 75$ worth of DSC and redeems 100$ worth of ETH
    /**
     * @notice Liquidate a position
     * @notice If the user health factor goes below the threshold(1), the position can be liquidated
     * @notice Partial liquidation is allowed
     * @param collateralAddress The address of the collateral token
     * @param user The address of the user
     * @param debtToCover The amount of DSC to burn
     */
    function liquidate(address collateralAddress, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__NotBelowThresholdHealthFactor();
        }
        // Now burn the DSC debt, and redeem the collateral
        // Example of a "bad position": as before, 75$ worth of ETH, backing 100$ worth of DSC, health factor = 0.75
        // debtToCover = 75$ worth of DSC
        // 75$ of DSC == ETH ??? -> How much ETH are we giving to liquidator? -> 0.0375 ETH (assuming 1 ETH = 2000$)
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUSD(collateralAddress, debtToCover);
        // Add a 10% bonus to the liquidator, the remaining collateral woill go to treasury (To implement)
        // 75$ (debtToCover) / 2000 (price of ETH in USD) = 0.0375 ETH (This is the corresponding amount of ETH to give to the liquidator for covering the debt)
        // Now we want to add a 10% bonus to the liquidator
        // bonusCollateral = 0.0375 * 10 / 100 = 0.00375 ETH
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATOR_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        // Now redeem the collateral and burn DSC
        _redeemCollateral(collateralAddress, totalCollateralToRedeem, user, msg.sender);
        // Burn DSC
        _burnDSC(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__NotImprovedHelthFactor();
        }

        // Revert if the liquidation breaks the health factor of the liquidator
        _revertIfHealthFactorBelowThreshold(msg.sender);
    }

    function getHealthFactor() external view {}

    //// PRIVATE & INTERNAL FUNCTIONS ////

    /**
     * @notice Burn DSC internal for burning dsc through liquidation
     * @param amountDSCToBurn The amount of DSC to burn
     * @param onBehalfOf The address of the user we want to burn the dsc
     * @param dscFrom The address of the liquidator
     * @dev Low-level internal function, do not call unless the calling function is checking for a belowtreshold health factor
     */
    function _burnDSC(uint256 amountDSCToBurn, address onBehalfOf, address dscFrom) private {
        s_mintedDSC[onBehalfOf] -= amountDSCToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDSCToBurn);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDSCToBurn);
    }

    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
    {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);

        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalMintedDSC, uint256 collateralValueInUSD)
    {
        totalMintedDSC = s_mintedDSC[user];
        collateralValueInUSD = getAccountCollateralValueInUSD(user);
    }

    /**
     * @notice Calculate the health factor of a user.
     * @notice If the user health factor goes below the treshold(1), the position can be liquidated.
     * @param user The address of the user
     * @return The health factor of the user
     * @dev Health factor example:
     * @dev User has 10 ETH, assuming 1 ETH = 1000 USD, collateralValueInUSD = 10,000 * 1e18
     * @dev User totalMintedDSC = 2,000
     * @dev LIQUIDATION_TRESHOLD = 50 (200% overcollateralization ratio).
     * @dev LIQUIDATION_PRECISION = 100
     * @dev collateralAdjustedForTreshold = 10,000 * 1e18 (collateralValueInUSD) * 50 (LIQUIDATION_TRESHOLD) / 100 (LIQUIDATION_PRECISION) = (500,000 * 1e18) / 100 = 5,000 * 1e18
     * @dev healthFactor = (5,000 * 1e18) / 2,000 = 2,500 * 1e18
     * @dev Finally the health factor =
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalMintedDSC, uint256 collateralValueInUSD) = _getAccountInformation(user);
        uint256 collateralAdjustedForTreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForTreshold * PRECISION) / totalMintedDSC;
    }

    function _revertIfHealthFactorBelowThreshold(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BelowThresholdHealthFactor(userHealthFactor);
        }
    }

    //// PUBLIC & EXTERNAL VIEW FUNCTIONS ////

    function getTokenAmountFromUSD(address token, uint256 amountUSDInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        // Example 10e18 (amountUSDInWei) * 1e18 (PRECISION) / 2000e8 (price of ETH in USD) * 1e10 (FEED_PRECISION)
        // 10e18 * 1e18 / 2000 * 1e18 = 10e18 / 2000 = 10e18 / 2e3 = 5e15 = 0.005 ETH

        return (amountUSDInWei * PRECISION) / (uint256(price) * FEED_PRECISION);
    }

    /**
     * @notice Get the total value of the collateral in USD
     * @dev This function loops through all the collateral tokens and maps it to the price
     * @dev from the Chainlink Price Feeds to get the total value of the collateral in USD
     * @param user The address of the user
     * @return totalCollateralValueInUSD The total value of the collateral in USD
     */
    function getAccountCollateralValueInUSD(address user) public view returns (uint256 totalCollateralValueInUSD) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUSD += getTokenValueInUSD(token, amount);
        }
        return totalCollateralValueInUSD;
    }

    /**
     * @notice Get the value of the token in USD
     * @param token The address of the token
     * @param amount The amount of the token
     * @dev price of ETH/USD and BTC/USD has 8 decimals
     * @dev assuming: token = ETH (1e18 decimals); 1 ETH = 1000 USD; FEED_PRECISION = 1e10; PRECISION = 1e18; amount = 10*1e18 (10 ETH)
     * @dev price = 1000 * 1e8 --> 100,000,000,000
     * @dev price * FEED_PRECISION = 100,000,000,000 * 1e10 = 1,000,000,000,000,000,000,000 = 1000 * 1e18
     * @dev tokenValueInUSD = [((1000 * 1e18) * (10 * 1e18) / 1e18 = (10,000 * 1e36) / 1e18 = 10,000 * 1e18
     * @dev tokenValueInUSD = 10,000 * 1e18 = 10,000 USD
     * @return tokenValueInUSD The value of the token in USD
     */
    function getTokenValueInUSD(address token, uint256 amount) public view returns (uint256 tokenValueInUSD) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        tokenValueInUSD = ((uint256(price) * FEED_PRECISION) * amount) / PRECISION;
        return tokenValueInUSD; // expressed in 1e18
    }
}
