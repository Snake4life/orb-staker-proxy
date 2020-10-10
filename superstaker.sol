pragma solidity =0.6.6;
//Import router interface
import "https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";
//Import SafeMath
import "https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/libraries/SafeMath.sol";
//Import IERC20
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.2.0/contracts/token/ERC20/IERC20.sol";

library UniswapV2Library {
    using SafeMath for uint;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'UniswapV2Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'UniswapV2Library: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f' // init code hash
            ))));
    }
}


interface OrbStakeContract {
  function FACTORY (  ) external view returns ( address );
  function INF (  ) external view returns ( uint256 );
  function UNIROUTER (  ) external view returns ( address );
  function WETHAddress (  ) external view returns ( address );
  function capPrice ( bool input ) external;
  function creationTime (  ) external view returns ( uint256 );
  function earnCalc ( uint256 LPTime ) external view returns ( uint256 );
  function ethEarnCalc ( uint256 eth, uint256 time ) external view returns ( uint256 );
  function makeUnchangeable (  ) external;
  function orbAddress (  ) external view returns ( address );
  function price (  ) external view returns ( uint256 );
  function priceCapped (  ) external view returns ( bool );
  function rewardValue (  ) external view returns ( uint256 );
  function setTokenAddress ( address input ) external;
  function sqrt ( uint256 y ) external pure returns ( uint256 z );
  function stake (  ) external;
  function timePooled ( address ) external view returns ( uint256 );
  function unchangeable (  ) external view returns ( bool );
  function updateRewardValue ( uint256 input ) external;
  function viewLPTokenAmount ( address who ) external view returns ( uint256 );
  function viewPooledEthAmount ( address who ) external view returns ( uint256 );
  function viewPooledTokenAmount ( address who ) external view returns ( uint256 );
  function viewRewardTokenAmount ( address who ) external view returns ( uint256 );
  function withdrawLPTokens ( uint256 amount ) external;
  function withdrawRewardTokens ( uint256 amount ) external;
}

contract SuperSiriusStaker {
    modifier onlyMaster() {
        require(msg.sender == Master);
        _;
    }
    // using SafeMath for uint;
    // using SafeMath for uint256;

    //Address to pay to,and can stake
    address payable public Master;
    address payable public stakeContractAddr = 0x838684591Ae08Ff099a9A8ccdE514f72f7187851;
    uint256 public unstakeDelay = 3 days;
    uint256 public stakeDelay = 24 hours;
    uint constant public INF = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
    bool ApprovalsDone = false;

    OrbStakeContract  public IOrb = OrbStakeContract(stakeContractAddr);

    /*Uniswap stuff*/

    //initialize router
    IUniswapV2Router02  public  IUniswapV2Router = IUniswapV2Router02(IOrb.UNIROUTER());

    //initialize factory address
    address public uniswapFactory = IOrb.FACTORY();
        

    //Get ORBETHPair address from pairfor
    IERC20 public uniorbpair = IERC20(address(0));
    IERC20 public orbToken = IERC20(IOrb.orbAddress());
    
    uint256 timePooledx = 0;
    constructor() public {
      Master = msg.sender;
      //Get pair address
      (address token0, address token1) = UniswapV2Library.sortTokens(address(IOrb.orbAddress()), address(IOrb.WETHAddress()));
      uniorbpair = IERC20(UniswapV2Library.pairFor(uniswapFactory, token0, token1));
    }
    /* End uniswap stuff */
    
    /* Getters start */
    function getTimePooled() public view returns (uint256){
        // IOrb.timePooled(address(this));
        return timePooledx;
    }
    
    function getStakeStartTime() public view returns (uint256){
        return  IOrb.creationTime() + stakeDelay;
    }

    function getTimeRemainingToStake() public view returns (uint256){
        if(getStakeStartTime() > now)
            return getStakeStartTime() - now;
        return 0;
    }

    function getUnstakeTime() public view returns (uint256){
        return getTimePooled() +  unstakeDelay;
    }

    function canUnstake() public view returns (bool){
        return now >= getUnstakeTime();
    }
    
    function canStake() public view returns (bool){
        return getTimeRemainingToStake() == 0;
    }
    
    function GetWithdrawableLP() public view returns (uint256){
        return IOrb.viewLPTokenAmount(address(this));
    }
    
    function GetWithdrawableRewards() public view returns (uint256){
        return IOrb.viewRewardTokenAmount(address(this));
    }
    
    function getPathForTokenToETH() private view returns (address[] memory) {
        address[] memory path = new address[](2);
        path[0] = IOrb.orbAddress();
        path[1] = IOrb.WETHAddress();
        
        return path;
    }
    
    function getOrbBalance() public view returns (uint256){
        return orbToken.balanceOf(address(this));
    }
      
    function getOrbLPBalance() public view returns (uint256){
        return uniorbpair.balanceOf(address(this));
    }

    function doApprovals() internal {
        // approve token
        orbToken.approve(IOrb.UNIROUTER(), INF);
        //Approve router to spend lp tokens
        uniorbpair.approve(IOrb.UNIROUTER(),INF);
        ApprovalsDone = true;
    }

    function removeETHLiquidityFromToken() internal {
        // remove liquidity
        address[] memory paths = getPathForTokenToETH();
        IUniswapV2Router.removeLiquidity(paths[0],paths[1], getOrbLPBalance(), 0, 0, address(this), now + 20);
    }
    
    function sellOrbToEth() internal {
        //We have removed liquidity ,now lets swap the orb shitcoin to ether
        uint256 orbBalance = getOrbBalance();
        if(orbBalance > 0 ){
            //We are selling,so set path accordingly
            address[] memory path = getPathForTokenToETH();
            uint[] memory minOuts = IUniswapV2Router.getAmountsOut(orbBalance, path);
            IUniswapV2Router.swapExactTokensForTokens(orbBalance,minOuts[1],path,address(this),now + 2 hours);
        }
    }

    function withdrawETH() public {
        //Try to withdraw eth
        //We have only eth now,send eth to master
        uint256 ETHBalance = address(this).balance;
        if(ETHBalance > 0){
            (bool success,  ) = Master.call{value:ETHBalance}("");
            require(success,"ETH Transfer failed to master");
        }
        
        //Try to withdraw WETH
        IERC20 WETH = IERC20(IOrb.WETHAddress());
        uint256 WETHBalance = WETH.balanceOf(address(this));
        if(WETHBalance > 0){
            WETH.transfer(Master,WETHBalance);
        }
    }

    //Stake on receiving eth
    receive() external payable onlyMaster {
        bool shouldStake = msg.sender != address(this);
        require(shouldStake,"Contract trying to restake gotten eth");
        if(shouldStake && canStake()){
            //This will stake for us
            (bool success,  ) = stakeContractAddr.call{value : address(this).balance}("");
            //For some reason we cant get timepooled from the staker contract,so we manage it here
            require(success,"Stake failed");
            timePooledx = now;
        }
        else{
            require(false,"Staking time isnt active yet");
        }
    }

    function unstake() public{
        //First withdraw lp tokens
        uint256 LPBalance = GetWithdrawableLP();
        if(LPBalance > 0)
            IOrb.withdrawLPTokens(LPBalance);

        //Then remove orb tokens
        uint256 RewardTokens = GetWithdrawableRewards();
        if(RewardTokens > 0)
            IOrb.withdrawRewardTokens(RewardTokens);
    }
    
    function unstakeAndSell() external {
        require(canUnstake(),"not time yet to unstake");
    
        //Call super unstake
        unstake();
    
        //Check if we did the approvals,if not approve 
        if(!ApprovalsDone){
            doApprovals();
        }

        if(getOrbLPBalance() > 0){
            removeETHLiquidityFromToken();
        }

        if(getOrbBalance() > 0){
            sellOrbToEth();
        }
        //Finally get All eth and weth in contract
        withdrawETH();
    }
}
