// SPDX-License-Identifier: Unlicensed
pragma solidity >= 0.6.12;

import "./IFactory.sol";
import "./Tokens/Pair.sol";
import 'hardhat/console.sol';

contract Factory is IFactory {
    address public override feeTo;
    address public override feeSetter;
    // bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(Pair).creationCode));

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeSetter) public {
        feeSetter = _feeSetter;
    }

    function INIT_CODE_PAIR_HASH() external override view returns (bytes32) {
        return keccak256(abi.encodePacked(type(Pair).creationCode));
    }

    function allPairsLength() external override view returns (uint) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        require(tokenA != tokenB, 'IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'PAIR_EXISTS');
        bytes memory bytecode = type(Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        IPair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    function setFeeTo(address _feeTo) external override {
        require(msg.sender == feeSetter, 'GlobalFactory: FORBIDDEN');
        feeTo = _feeTo;
    }

    function setFeeSetter(address _feeSetter) external override {
        require(msg.sender == feeSetter, 'GlobalFactory: FORBIDDEN');
        feeSetter = _feeSetter;
    }

    function setDevFee(address _pair, uint8 _devFee) external {
        require(msg.sender == feeSetter, 'GlobalFactory: FORBIDDEN');
        IPair(_pair).setDevFee(_devFee);
    }

    function setSwapFee(address _pair, uint32 _swapFee) external {
        require(msg.sender == feeSetter, 'GlobalFactory: FORBIDDEN');
        IPair(_pair).setSwapFee(_swapFee);
    }
}