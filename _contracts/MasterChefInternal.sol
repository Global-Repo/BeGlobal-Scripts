// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import './Tokens/IBEP20.sol';
import "./Helpers/TokenAddresses.sol";
import "./Helpers/IPathFinder.sol";
import './Tokens/IPair.sol';
import './Modifiers/Ownable.sol';

contract MasterChefInternal is Ownable {
    TokenAddresses public tokenAddresses;
    IPathFinder public pathFinder;

    constructor(address _tokenAddresses, address _pathFinder) public {
        tokenAddresses = TokenAddresses(_tokenAddresses);
        pathFinder = IPathFinder(_pathFinder);
    }

    function setInternalPathFinder(address _pathFinder) public onlyOwner {
        pathFinder = IPathFinder(_pathFinder);
    }

    function addRouteToPathFinder(
        address _token, address _tokenRoute, bool _directBNB
    ) public onlyOwner {
        pathFinder.addRouteInfo(_token,_tokenRoute, _directBNB);
    }

    function removeRouteToPathFinder(
        address _token
    ) public onlyOwner {
        pathFinder.removeRouteInfo(_token);
    }

    function checkTokensRoutes(IBEP20 _lpToken) public returns (bool bothConnected)
    {
        address WBNB = tokenAddresses.findByName(tokenAddresses.BNB());
        IPair pair = IPair(address(_lpToken));
        bothConnected = false;
        if(pair.token0()==WBNB)
        {
            pathFinder.addRouteInfoDirect(pair.token1());
            bothConnected = true;
        }
        else if(pair.token1()==WBNB)
        {
            pathFinder.addRouteInfoDirect(pair.token0());
            bothConnected = true;
        }
        else if(!pathFinder.isTokenConnected(pair.token0()) && pathFinder.getRouteInfoDirectBNB(pair.token1()))
        {
            pathFinder.addRouteInfoRoute(pair.token0(),pair.token1());
            bothConnected = true;
        }
        else if(!pathFinder.isTokenConnected(pair.token1()) && pathFinder.getRouteInfoDirectBNB(pair.token0()))
        {
            pathFinder.addRouteInfoRoute(pair.token1(),pair.token0());
            bothConnected = true;
        }
        else if(pathFinder.isTokenConnected(pair.token0()) && pathFinder.isTokenConnected(pair.token1()))
        {
            bothConnected = true;
        }
    }
}