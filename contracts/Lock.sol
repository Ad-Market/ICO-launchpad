// SPDX-License-Identifier: MIT
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

pragma solidity ^0.8.0;

contract Lock is Ownable, ReentrancyGuard {
    IERC20 tokenAddress;
    // mainnet: 0x10ED43C718714eb63d5aA57B78B54704E256024E
    //testnet: 0xD99D1c33F9fC3444f8101754aBC46c52416550D1
    IUniswapV2Router02 routerAddress;

    address public idoAdmin;
    mapping (address => bool)subAdmins;
    address public lpTokenReceiver;
    address private burnAddress = 0x000000000000000000000000000000000000dEaD;
    mapping(address=>bool) isWhitelisted;

    // TODO: suggestion TokenPrice as it's similar to tokenPrice
    uint256 public TokenPrice; //How many tokens per base token e.g 1 BNB = n amount of tokens
    uint256 public _phase =0;
    uint256 public SOFTCAP;
    uint256 public HARDCAP;
    uint256 public minimumContribution = 1e16;
    uint256 public tokenPrice; // measured in tokenUnits,
    uint256 public paidSpots;
    uint256 public GweiCollected = 0; //Gwei or jager for ETH/BNB
    uint256 public maxAmount;
    uint256 public tokenDecimals;
    uint256 public liquidityToLock;
    uint256 private contributorNumber=0;
    uint256 currentWhitelistUsers;

    bool public isActive; // sets initial flag to false
    bool public marketOn;

    mapping(address => BuyersData) public Buyers;

    //depends on the decimals, e.g if token has 18 decimals the calculation can be done directly
    struct BuyersData {
        uint256 contribution;
        uint256 owedTokens;
    }

    constructor(
        IERC20 _tokenAddress,
        IUniswapV2Router02 _routerAddress,
        address payable _idoAdmin,
        address _lpTokenReceiver,
        uint256 _paidSpots,
        uint256 _maxAmount,
        uint256 _tokenDecimals,
        uint256 _softcap,
        uint256 _hardcap,
        uint256 _liquidityToLock,
        uint256 _tokenPrice
    )  {
        routerAddress = _routerAddress;
        lpTokenReceiver = _lpTokenReceiver;
        tokenAddress = _tokenAddress;
        tokenDecimals = _tokenDecimals;
        idoAdmin = _idoAdmin;
        paidSpots = _paidSpots;//whitelistSpots
        maxAmount = _maxAmount;
        SOFTCAP = _softcap;
        HARDCAP = _hardcap;
        liquidityToLock = _liquidityToLock;
        tokenPrice =_tokenPrice;
    }
       function addToAdmin(address newAddress)public onlyOwner{
        subAdmins[newAddress] = true;
    }

    

    function cancelSale() public onlyOwner {
        _phase = 4;
    }
    function cancelSaleAdmin()external {
        require(subAdmins[msg.sender],"Not an admin");
        _phase = 4;
    }
    function withdrawBaseToken() public{
        require(_phase == 4,"not a refund phase");
        address payable currentUser = payable(msg.sender);
        BuyersData storage _contributionInfo = Buyers[msg.sender];
        uint256 userContribution = _contributionInfo.contribution;
        require(userContribution>0,"Not contributed");
        currentUser.transfer(userContribution);
        _contributionInfo.contribution = 0;

        

    }
    function startWhitelistedPhase() external onlyOwner{
        _phase = 1;
    }
    function addToWhitelistOwner (address newUser)public onlyOwner{
        require(currentWhitelistUsers<=paidSpots,"No more whitelist spots");
        isWhitelisted[newUser]=true;
        currentWhitelistUsers+=1;
    }
       function addToWhitelistAdmin (address newUser) external{
        require(subAdmins[msg.sender],"Not an admin");
        require(currentWhitelistUsers<=paidSpots,"No more whitelist spots");
        isWhitelisted[newUser]=true;
        currentWhitelistUsers+=1;
    }
    function returnWhitelistUsers()public view returns(uint256){
        return currentWhitelistUsers;
    }
    function userDepositsWhitelist()public payable nonReentrant{//Phase =1 whitelist phase
    require(_phase == 1,"presale not open yet");
    require(isWhitelisted[msg.sender],"Not whitelisted");
    require(msg.value<=maxAmount,"Contribution needs to be in the minimum buy/max buy range");
    require(address(this).balance + msg.value<=HARDCAP);
    BuyersData storage _contributionInfo = Buyers[msg.sender];
    uint256 amount_in = msg.value;
    uint256 tokensSold = amount_in * tokenPrice;
    _contributionInfo.contribution += msg.value;
    require(_contributionInfo.contribution+msg.value<=maxAmount,"Cant contribute anymore");
    _contributionInfo.owedTokens += tokensSold;
    GweiCollected += amount_in;
    contributorNumber+=1;
}
 
    function _UserDepositPublicPhase() public payable nonReentrant {//Phase =2 public phase
        require(_phase==2,"Not on public _phase yet");
        //require(_phase == 1 && tokenAddress.balanceOf(msg.sender)>minimumHoldings, "This function is only callable in _phase 1");//only holders are able to participate in _phase 1
        //require(msg.value < maximumPurchase&& msg.value > minimumContribution,"One of the following parameters is incorrect:MinimumAmount/MaxAmount");
        BuyersData storage _contributionInfo = Buyers[msg.sender];
        uint256 amount_in = msg.value;
        uint256 tokensSold = amount_in * tokenPrice;
        _contributionInfo.contribution += msg.value;
        _contributionInfo.owedTokens += tokensSold;
        GweiCollected += amount_in;
        contributorNumber+=1;
    }

    
  function _returnContributors() public view returns(uint256){
      return contributorNumber;
  }
  function checkContribution(address contributor) public view returns(uint256){
      BuyersData storage _contributionInfo = Buyers[msg.sender];
      return _contributionInfo.contribution;
  }

    function _remainingContractTokens() public view returns (uint256) {
        return tokenAddress.balanceOf(address(this));
    }
    function returnTotalAmountFunded() public view returns (uint256){
        return GweiCollected;
    }

    function _returnPhase() public view returns (uint256) {
        return _phase;
    }
    function enablePublicPhase()public onlyOwner{
        require(marketOn==false,"cant change _phase market already started");
        _phase = 2;

    }
    function returnHardCap() public view returns(uint256){
        return HARDCAP;
    }
      function returnSoftCap() public view returns(uint256){
        return SOFTCAP;
    }
    function returnRemainingTokensInContract() public view returns(uint256){
        return tokenAddress.balanceOf(address(this));
    }

    function _startMarket() public onlyOwner {
    /*
    Approve balance required from this contract to pcs liquidity factory
    
    finishes ido status
    creates liquidity in pcs
    forwards funds to project creator
    forwards mcf fee to mcf wallet
    locks liquidity
    */
    require(address(this).balance >=SOFTCAP,"market cant start, softcap not reached");
    uint256 amountForLiquidity = (address(this).balance) *liquidityToLock/100;

    addLiquidity(amountForLiquidity);
    _phase = 3;
    marketOn = true;
    uint256 remainingBaseBalance = address(this).balance;
    payable(idoAdmin).transfer(remainingBaseBalance);


   
    }
      function transferUnsold() public onlyOwner{
        uint256 remainingCrowdsaleBalance = tokenAddress.balanceOf(address(this));
        tokenAddress.transfer(idoAdmin,remainingCrowdsaleBalance);
    }
  
    
    function burnUnsold() public onlyOwner{
        uint256 remainingCrowdsaleBalance = tokenAddress.balanceOf(address(this));
        tokenAddress.transfer(burnAddress,remainingCrowdsaleBalance);
    }

    //Contract shouldnt accept bnb/eth/etc thru fallback functions, pending implementation if its the opposite
    receive() external payable {
        //NA
    }

    function _lockLiquidity() internal {
        /*liquidity Forwarder
pairs reserved amount and bnb to create liquidity pool
*/
    }

    function withdrawTokens() public {
        uint256 currentTokenBalance = tokenAddress.balanceOf(address(this));
        BuyersData storage buyer = Buyers[msg.sender];
        require(_phase == 3 && marketOn == true, "not ready to claim");
        uint256 tokensOwed = buyer.owedTokens;
        require(
            tokensOwed > 0 && currentTokenBalance > 0,
            "No tokens to be transfered or contract empty"
        );
        tokenAddress.transfer(msg.sender, tokensOwed);
        buyer.owedTokens = 0;
    }

    function addLiquidity(uint256 bnbAmount) public onlyOwner {
        //uint256 amountOfBNB = address(this).balance;
        uint256 amountOFTokens = tokenAddress.balanceOf(address(this));

        IERC20(tokenAddress).approve(address(routerAddress), amountOFTokens);

        (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        ) = IUniswapV2Router02(routerAddress).addLiquidityETH{
                value: bnbAmount
            }(
                address(tokenAddress),
                amountOFTokens,
                0,
                0,
                lpTokenReceiver,
                block.timestamp + 1200
            );
    }

}