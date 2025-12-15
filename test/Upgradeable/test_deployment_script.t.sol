// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// Import the deployment script helper
import "../../script/DeployUpgradeable.s.sol";

/**
 * @dev Simple upgradeable contract for testing deployment
 */
contract SimpleUpgradeable is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    uint256 public value;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(uint256 _value) public initializer {
        __Ownable_init(msg.sender);
        value = _value;
    }

    function setValue(uint256 _value) external {
        value = _value;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}

/**
 * @dev Test deployment script that inherits from DeployUpgradeable
 */
contract TestDeployScript is DeployUpgradeable {
    function run() external returns (address proxy, address implementation) {
        vm.startBroadcast();

        // Deploy implementation
        implementation = address(new SimpleUpgradeable());
        console.log("Deploying SimpleUpgradeable...");

        // Deploy proxy with initialization
        proxy = deployProxy(
            implementation,
            abi.encodeCall(SimpleUpgradeable.initialize, (42))
        );

        logDeployment("SimpleUpgradeable", proxy, implementation);

        vm.stopBroadcast();
    }
}

/**
 * @dev Tests for the deployment script helpers
 */
contract DeploymentScriptTest is Test {
    TestDeployScript public deployScript;

    function setUp() public {
        deployScript = new TestDeployScript();
    }

    function test_DeploymentScriptWorks() public {
        // Run the deployment script
        (address proxy, address implementation) = deployScript.run();

        // Verify deployment
        assertTrue(proxy != address(0), "Proxy should be deployed");
        assertTrue(implementation != address(0), "Implementation should be deployed");

        // Verify initialization
        SimpleUpgradeable proxyContract = SimpleUpgradeable(proxy);
        assertEq(proxyContract.value(), 42, "Value should be initialized to 42");
        // Owner is the default broadcast sender, verify it's set (not zero)
        assertTrue(proxyContract.owner() != address(0), "Owner should be set");
    }

    function test_GetImplementationWorks() public {
        // Run deployment
        (address proxy, address implementation) = deployScript.run();

        // Get implementation address from storage slot
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 storedImpl = vm.load(proxy, slot);
        address readImpl = address(uint160(uint256(storedImpl)));

        assertEq(readImpl, implementation, "Implementation addresses should match");
    }
}
