// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../Tokens/IPair.sol";
import "./IPathFinder.sol";
import '../Modifiers/Ownable.sol';
import './TokenAddresses.sol';
import 'hardhat/console.sol';

contract PathFinder is IPathFinder, Ownable {
    TokenAddresses public tokenAddresses;

    mapping (address => RouteInfo) public routeInfos;

    struct RouteInfo {
        bool directBNB;
        address tokenRoute;
    }

    constructor(
        address _tokenAddresses
    ) public {
        tokenAddresses = TokenAddresses(_tokenAddresses);
    }

    function addRouteInfoDirect(address _token) external onlyOwner override {
        routeInfos[_token].directBNB=true;
    }

    function addRouteInfoRoute(address _token, address _tokenRoute) external onlyOwner override {
        require(_tokenRoute!=address(0), 'PathFinder: you must define either a direct path to BNB or a routeToken to BNB');
        routeInfos[_token].tokenRoute=_tokenRoute;
    }

    function addRouteInfo(address _token, address _tokenRoute, bool _directBNB) external onlyOwner override {
        require(_tokenRoute!=address(0) || _directBNB, 'PathFinder: you must define either a direct path to BNB or a routeToken to BNB');

        routeInfos[_token].tokenRoute=_tokenRoute;
        routeInfos[_token].directBNB=_directBNB;
    }

    function removeRouteInfo(address _token) external onlyOwner override {
        delete routeInfos[_token];
    }

    function isTokenConnected(address _token) external view override returns (bool) {
        return routeInfos[_token].tokenRoute != address(0) || routeInfos[_token].directBNB;
    }

    function getRouteInfoTokenRoute(address _token) external view override returns (address) {
        return routeInfos[_token].tokenRoute;
    }

    function getRouteInfoDirectBNB(address _token) external view override returns (bool) {
        return routeInfos[_token].directBNB;
    }

    function getRouteInfo(address _token) internal view returns (RouteInfo memory) {
        return routeInfos[_token];
    }

    function findPath(address _tokenFrom, address _tokenTo) external view override returns (address[] memory)
    {
        RouteInfo memory infoFrom = getRouteInfo(_tokenFrom);
        RouteInfo memory infoTo = getRouteInfo(_tokenTo);
        address WBNB = tokenAddresses.findByName(tokenAddresses.BNB());

        address[] memory path;
        if ((_tokenFrom == WBNB && infoTo.directBNB) || (_tokenTo == WBNB && infoFrom.directBNB)) {
            path = new address[](2);
            path[0] = _tokenFrom;
            path[1] = _tokenTo;
        }
        else if ((infoFrom.tokenRoute != address(0)&&_tokenTo == WBNB)||(infoTo.tokenRoute != address(0) && _tokenFrom == WBNB)) {
            path = new address[](3);
            path[0] = _tokenFrom;
            path[1] = infoFrom.tokenRoute != address(0)?infoFrom.tokenRoute:infoTo.tokenRoute;
            path[2] = _tokenTo;
        } else if (_tokenFrom == infoTo.tokenRoute || _tokenTo == infoFrom.tokenRoute) {
            path = new address[](2);
            path[0] = _tokenFrom;
            path[1] = _tokenTo;
        } else if (infoFrom.tokenRoute != address(0) && infoFrom.tokenRoute == infoTo.tokenRoute) {
            path = new address[](3);
            path[0] = _tokenFrom;
            path[1] = infoFrom.tokenRoute;
            path[2] = _tokenTo;
        } else if (infoFrom.directBNB && infoTo.directBNB) {
            path = new address[](3);
            path[0] = _tokenFrom;
            path[1] = WBNB;
            path[2] = _tokenTo;
        } else if (infoFrom.tokenRoute != address(0) && infoTo.directBNB) {
            path = new address[](4);
            path[0] = _tokenFrom;
            path[1] = infoFrom.tokenRoute;
            path[2] = WBNB;
            path[3] = _tokenTo;
        } else if (infoTo.tokenRoute != address(0) && infoFrom.directBNB) {
            path = new address[](4);
            path[0] = _tokenFrom;
            path[1] = WBNB;
            path[2] = infoTo.tokenRoute;
            path[3] = _tokenTo;
        }  else if (infoFrom.tokenRoute != address(0) && infoTo.tokenRoute != address(0)) {
            path = new address[](5);
            path[0] = _tokenFrom;
            path[1] = infoFrom.tokenRoute;
            path[2] = WBNB;
            path[3] = infoTo.tokenRoute;
            path[4] = _tokenTo;
        }
        else
        {
            path = new address[](0);
        }
        return path;
    }
}