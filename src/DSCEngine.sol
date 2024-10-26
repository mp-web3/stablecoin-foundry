// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
     * @dev FEED_PRECISION is used to convert the price from the Chainlink Price Feeds to the desired precision
     * @dev PRECISION is used to convert the price from the Chainlink Price Feeds to the desired precision
     * @dev LIQUIDATION_THRESHOLD is the overcollateralization ratio
     * @dev LIQUIDATION_PRECISION is used to convert the liquidation threshold to the desired precision
     * @dev Since the price of ETH/USD and BTC/USD returned by Chainlink Price Feed is expressed with 8 decimals
     * @dev and we use as standard ETH decimals (1e18), we need to multiply the price returned by Chainlink for 1e10 (FEED_PRECISION)
     * @dev to get the price in the desired precision (1e18).
     */
    uint256 private constant FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralization
    uint256 private constant LIQUIDATION_PRECISION = 100;

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
            s_collateralTokens.push(tokenAddresses[i]);
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

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    /**
     * @notice Mint DSC. Not all the deposited collateral has to be used to mint DSC.
     * @param amountToMintDSC The amount of DSC to mint
     */
    function mintDSC(uint256 amountToMintDSC) external moreThanZero(amountToMintDSC) nonReentrant {
        s_mintedDSC[msg.sender] += amountToMintDSC;

        _revertIfHealthFactorBelowThreshold(msg.sender);
    }

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    //// PRIVATE & INTERNAL FUNCTIONS ////

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
     * @notice If the uuser health factor goes below the treshold(1), the position can be liquidated.
     * @param user The address of the user
     * @dev Health factor example:
     * @dev User has 10 ETH, assuming 1 ETH = 1000 USD, collateralValueInUSD = 10,000 * 1e18
     * @dev User totalMintedDSC = 2,000
     * @dev LIQUIDATION_TRESHOLD = 50 (200% overcollateralization ratio).
     * @dev LIQUIDATION_PRECISION = 100
     * @dev collateralAdjustedForTreshold = 10,000 * 1e18 (collateralValueInUSD) * 50 (LIQUIDATION_TRESHOLD) / 100 (LIQUIDATION_PRECISION) = (500,000 * 1e18) / 100 = 5,000 * 1e18
     * @dev healthFactor = (5,000 * 1e18) / 2,000 = 2,500 * 1e18
     * @dev Finally the health factor =
     * @return The health factor of the user
     */
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 totalMintedDSC, uint256 collateralValueInUSD) = _getAccountInformation(user);
        uint256 collateralAdjustedForTreshold = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForTreshold * PRECISION) / totalMintedDSC;
    }

    function _revertIfHealthFactorBelowThreshold(address user) internal view {}

    //// PUBLIC & EXTERNAL VIEW FUNCTIONS ////
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
