// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;

    address ethUsdPriceFeed;
    address weth;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed,, weth,,) = helperConfig.activeNetworkConfig();
    }

    // PRICE TEST //
    function testGetTokenValueInUSD() public {
        uint256 ethAmount = 10 ether;
        // 10e18 * 2000/ETH = 20,000e18
        uint256 expectedValueInUSD = 20_000e18;
        uint256 actualValueInUSD = dscEngine.getTokenValueInUSD(weth, ethAmount);
        assertEq(expectedValueInUSD, actualValueInUSD);
    }
}
