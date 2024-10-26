// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

/**
 * @title DSCEngine
 * @author Mattia Papa
 * @dev This contract implements the mechanisms to maintain a 1:1 peg with USD.
 * @dev The stablecoin is algoritmically stable, pegged to the dollar and overcollateralized by wBTC and wETH.
 * @notice This contract is the core of the DSC System. It handles all of the logic for:
 * @notice minting and redeeming DSC, as well as depositing and withdrawing collateral.
 */
contract DSCEngine {
    function depositCollateralAndMintDSC() external {}

    function depositCollateral() external {}

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    function mintDSC() external {}

    function burnDSC() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}
}
