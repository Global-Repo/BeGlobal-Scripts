// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import '../Modifiers/Ownable.sol';

interface IPathFinder {
    function addRouteInfoDirect(address _token) external;
    function addRouteInfoRoute(address _token, address _tokenRoute) external;
    function addRouteInfo(address _token, address _tokenRoute, bool _directBNB) external;
    function removeRouteInfo(address _token) external;
    function isTokenConnected(address _token) external view returns (bool);
    function getRouteInfoTokenRoute(address _token) external view returns (address);
    function getRouteInfoDirectBNB(address _token) external view returns (bool);

    function findPath(address _tokenFrom, address _tokenTo) external view returns (address[] memory);
}