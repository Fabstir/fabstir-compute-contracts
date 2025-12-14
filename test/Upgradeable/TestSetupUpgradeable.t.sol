// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title TestSetupUpgradeable
 * @dev Base test contract with helpers for deploying and testing upgradeable contracts
 */
contract TestSetupUpgradeable is Test {
    // Common test addresses
    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public treasury = address(0x4);

    function setUp() public virtual {
        // Fund test accounts
        vm.deal(owner, 100 ether);
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(treasury, 100 ether);
    }

    /**
     * @dev Deploy an implementation contract behind an ERC1967 proxy
     * @param implementation The implementation contract address
     * @param data The initialization calldata (abi.encodeCall of initialize function)
     * @return proxy The deployed proxy address
     */
    function deployProxy(
        address implementation,
        bytes memory data
    ) internal returns (address proxy) {
        proxy = address(new ERC1967Proxy(implementation, data));
    }

    /**
     * @dev Upgrade an existing proxy to a new implementation
     * @param proxy The proxy contract address (must be UUPSUpgradeable)
     * @param newImplementation The new implementation address
     * @param caller The address to call upgradeToAndCall from
     */
    function upgradeProxy(
        address proxy,
        address newImplementation,
        address caller
    ) internal {
        vm.prank(caller);
        UUPSUpgradeable(proxy).upgradeToAndCall(newImplementation, "");
    }

    /**
     * @dev Upgrade an existing proxy to a new implementation with initialization data
     * @param proxy The proxy contract address (must be UUPSUpgradeable)
     * @param newImplementation The new implementation address
     * @param data The initialization calldata for the new implementation
     * @param caller The address to call upgradeToAndCall from
     */
    function upgradeProxyWithData(
        address proxy,
        address newImplementation,
        bytes memory data,
        address caller
    ) internal {
        vm.prank(caller);
        UUPSUpgradeable(proxy).upgradeToAndCall(newImplementation, data);
    }

    /**
     * @dev Get the implementation address of a proxy
     * @param proxy The proxy contract address
     * @return The implementation address
     */
    function getImplementation(address proxy) internal view returns (address) {
        // ERC1967 implementation slot
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        return address(uint160(uint256(vm.load(proxy, slot))));
    }
}

// ============================================================
// Mock Upgradeable Contract for Testing the Test Setup
// ============================================================

/**
 * @dev Simple upgradeable contract for testing proxy deployment and upgrades
 */
contract MockUpgradeableV1 is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    uint256 public value;
    string public name;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(uint256 _value, string memory _name) public initializer {
        __Ownable_init(msg.sender);
        // Note: UUPSUpgradeable in OZ 5.x doesn't require initialization
        value = _value;
        name = _name;
    }

    function setValue(uint256 _value) external {
        value = _value;
    }

    function version() external pure virtual returns (string memory) {
        return "v1";
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

/**
 * @dev V2 of the mock contract with additional functionality
 */
contract MockUpgradeableV2 is MockUpgradeableV1 {
    uint256 public extraValue;

    function initializeV2(uint256 _extraValue) external reinitializer(2) {
        extraValue = _extraValue;
    }

    function version() external pure virtual override returns (string memory) {
        return "v2";
    }

    function getSum() external view returns (uint256) {
        return value + extraValue;
    }
}

// ============================================================
// Tests for TestSetupUpgradeable Helpers
// ============================================================

contract TestSetupUpgradeableTest is TestSetupUpgradeable {
    MockUpgradeableV1 public implementation;
    MockUpgradeableV1 public proxy;

    function setUp() public override {
        super.setUp();
        // Deploy implementation
        implementation = new MockUpgradeableV1();
    }

    function test_DeployProxy() public {
        // Deploy proxy with initialization
        vm.prank(owner);
        address proxyAddr = deployProxy(
            address(implementation),
            abi.encodeCall(MockUpgradeableV1.initialize, (42, "test"))
        );

        proxy = MockUpgradeableV1(proxyAddr);

        // Verify initialization
        assertEq(proxy.value(), 42);
        assertEq(proxy.name(), "test");
        assertEq(proxy.owner(), owner);
        assertEq(proxy.version(), "v1");
    }

    function test_GetImplementation() public {
        vm.prank(owner);
        address proxyAddr = deployProxy(
            address(implementation),
            abi.encodeCall(MockUpgradeableV1.initialize, (42, "test"))
        );

        // Verify implementation address
        assertEq(getImplementation(proxyAddr), address(implementation));
    }

    function test_UpgradeProxy() public {
        // Deploy V1
        vm.prank(owner);
        address proxyAddr = deployProxy(
            address(implementation),
            abi.encodeCall(MockUpgradeableV1.initialize, (42, "test"))
        );
        proxy = MockUpgradeableV1(proxyAddr);

        // Deploy V2 implementation
        MockUpgradeableV2 implementationV2 = new MockUpgradeableV2();

        // Upgrade to V2
        upgradeProxy(proxyAddr, address(implementationV2), owner);

        // Verify upgrade
        MockUpgradeableV2 proxyV2 = MockUpgradeableV2(proxyAddr);
        assertEq(proxyV2.version(), "v2");

        // Verify state preserved
        assertEq(proxyV2.value(), 42);
        assertEq(proxyV2.name(), "test");
        assertEq(proxyV2.owner(), owner);
    }

    function test_UpgradeProxyWithData() public {
        // Deploy V1
        vm.prank(owner);
        address proxyAddr = deployProxy(
            address(implementation),
            abi.encodeCall(MockUpgradeableV1.initialize, (42, "test"))
        );

        // Deploy V2 implementation
        MockUpgradeableV2 implementationV2 = new MockUpgradeableV2();

        // Upgrade to V2 with initialization
        upgradeProxyWithData(
            proxyAddr,
            address(implementationV2),
            abi.encodeCall(MockUpgradeableV2.initializeV2, (100)),
            owner
        );

        // Verify V2 initialization
        MockUpgradeableV2 proxyV2 = MockUpgradeableV2(proxyAddr);
        assertEq(proxyV2.extraValue(), 100);
        assertEq(proxyV2.getSum(), 142); // 42 + 100
    }

    function test_OnlyOwnerCanUpgrade() public {
        // Deploy V1
        vm.prank(owner);
        address proxyAddr = deployProxy(
            address(implementation),
            abi.encodeCall(MockUpgradeableV1.initialize, (42, "test"))
        );

        // Deploy V2 implementation
        MockUpgradeableV2 implementationV2 = new MockUpgradeableV2();

        // Try to upgrade as non-owner (should revert)
        vm.prank(user1);
        vm.expectRevert();
        UUPSUpgradeable(proxyAddr).upgradeToAndCall(address(implementationV2), "");
    }

    function test_CannotInitializeTwice() public {
        // Deploy proxy
        vm.prank(owner);
        address proxyAddr = deployProxy(
            address(implementation),
            abi.encodeCall(MockUpgradeableV1.initialize, (42, "test"))
        );

        // Try to initialize again (should revert)
        vm.expectRevert();
        MockUpgradeableV1(proxyAddr).initialize(100, "hack");
    }

    function test_ImplementationCannotBeInitialized() public {
        // Try to initialize implementation directly (should revert)
        vm.expectRevert();
        implementation.initialize(42, "test");
    }
}
