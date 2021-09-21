pragma solidity 0.6.12;


import "hardhat/console.sol";
import "./Modifiers/Ownable.sol";
import "./Modifiers/Trusted.sol";
import "./Libraries/SafeMath.sol";
import "./Tokens/IBEP20.sol";
import "./Libraries/SafeBEP20.sol";
import "./Tokens/NativeToken.sol";

contract Presale is Ownable, Trusted{

    using SafeBEP20 for uint16;
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    NativeToken public nativeToken;
    uint public whitelistBegins;
    uint public whitelistEnds;
    uint public publicBegins;
    uint public publicEnds;

    uint hardcap = 7850e18;
    uint public bnbacc = 0;

    mapping (address => uint) private quantityBought;

    event TokensBought(address buyer, uint256 amountBNB, uint256 globalAmount, uint256 bnb_Acc);
    event AdminTokenRecovery(address tokenRecovered, uint256 amount);

    constructor(NativeToken _token, uint _whitelistBegins, uint _publicBegins) public {
        nativeToken = _token;

        whitelistBegins = _whitelistBegins;
        whitelistEnds = whitelistBegins.add(2 days);

        publicBegins = _publicBegins;
        publicEnds = publicBegins.add(2 days);
    }

    function changeWhitelistBegins(uint _whitelistBegins) public onlyOwner{
        whitelistBegins = _whitelistBegins;
        whitelistEnds = whitelistBegins.add(2 days);
    }

    function changePublicBegins(uint _publicBegins) public onlyOwner{
        publicBegins = _publicBegins;
        publicEnds = publicBegins.add(2 days);
    }

    receive() external payable{
        buyTokens(msg.value, msg.sender);
    }

    function getStatus() public view returns(uint whitelistStep){
        if (block.timestamp < whitelistBegins) return 2;
        if (block.timestamp < whitelistEnds) return 0;
        if (block.timestamp < publicBegins) return 2;
        if (block.timestamp < publicEnds) return 1;
        return 2;
    }

    function buyTokens(uint256 quantity, address buyer) public onlyHuman{
        require((getStatus() == 0 && whitelist[buyer] && bnbacc < hardcap) || (getStatus() == 1 && bnbacc < hardcap) || (getStatus() == 1 && publicBegins.add(12 hours) > block.timestamp) , "NOT YOUR TIME BRODAH");

        console.log("[buyTokens]");
        console.log("   Buyer: ", buyer);
        console.log("   Quantity: ", quantity);
        uint globalToReceive = 0;

        if (getStatus() == 0 && whitelist[buyer] && bnbacc < hardcap){
            globalToReceive = quantity.mul(5300);
            nativeToken.transfer(buyer, globalToReceive);
            bnbacc = bnbacc.add(quantity);
            quantityBought[buyer] = quantityBought[buyer].add(quantity);
            emit TokensBought(buyer, quantity, globalToReceive, bnbacc);
        }
        else if(getStatus() == 1 && bnbacc < hardcap)
        {
            globalToReceive = quantity.mul(4400);
            nativeToken.transfer(buyer, globalToReceive);
            bnbacc = bnbacc.add(quantity);
            quantityBought[buyer] = quantityBought[buyer].add(quantity);
            emit TokensBought(buyer, quantity, globalToReceive, bnbacc);
        }
        else if(getStatus() == 1 && publicBegins.add(12 hours) > block.timestamp)
        {
            globalToReceive = quantity.mul(4100);
            nativeToken.transfer(buyer, globalToReceive);
            bnbacc = bnbacc.add(quantity);
            quantityBought[buyer] = quantityBought[buyer].add(quantity);
            emit TokensBought(buyer, quantity, globalToReceive, bnbacc);
        }
    }

    function transferTokenOwnership(address _masterchef) public onlyOwner{
        nativeToken.transferOwnership(_masterchef);
    }

    function transferBNBsAcc(uint amount) public onlyOwner{
        payable(address(msg.sender)).transfer(amount);
        bnbacc = bnbacc.sub(amount);
    }

    function recoverWrongTokens(address _tokenAddress, uint256 _tokenAmount) external onlyOwner {
        IBEP20(_tokenAddress).safeTransfer(address(msg.sender), _tokenAmount);
        emit AdminTokenRecovery(_tokenAddress, _tokenAmount);
    }
}
