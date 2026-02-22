// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {JobMarketplaceWithModelsUpgradeable} from "src/JobMarketplaceWithModelsUpgradeable.sol";

/// @notice F202615067: Verify contract size is under EVM limit
contract ContractSizeTest is Test {
    function test_ContractDeploysUnderSizeLimit() public {
        JobMarketplaceWithModelsUpgradeable impl = new JobMarketplaceWithModelsUpgradeable();
        uint256 size;
        assembly { size := extcodesize(impl) }
        assertLt(size, 24577, "Contract exceeds EVM size limit");
    }
}
