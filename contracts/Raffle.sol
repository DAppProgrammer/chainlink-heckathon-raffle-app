//SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "hardhat/console.sol";
import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

error Raffle__SendMoreToEnterRaffle();
error Raffle__RaffleNotOpen();
error Raffle_UpkeepNotNeeded();
error Raffle__TransferFailed();

contract Raffle is VRFConsumerBaseV2 {

    enum RaffleState { 
        Open,
        Calculating
    }
    
    RaffleState public s_raffleState;
    //immutable means can be initialized only once in constructor 
    // and its way too inexpensive 
    uint256 public immutable i_entranceFee;
    uint256 public immutable i_interval;
    address payable[] public s_players;
    uint256 public s_lastTimeStamp;
    VRFCoordinatorV2Interface public immutable i_vrfCoordinator;
    bytes32 public i_gasLane;
    uint64 public i_subscriptionId;
    uint32 public i_callbackGasLimit;
    address public s_recentWinner;

    uint16 public constant REQUEST_CONFIRMATIONS = 3;
    uint32 public constant NUM_WORDS = 1;

    event RaffleEnter(address indexed player);
    event RequestedRaffleWinner(uint256 indexed player);
    event WinnerPicked(address indexed winner);

    constructor(uint256 _enteranceFee, uint256 _interval, address _vrfCoordinatorV2, bytes32 _gasLane /*keyhash*/, uint64 _subscriptionId, uint32 _callbackGasLimit) 
    VRFConsumerBaseV2(_vrfCoordinatorV2) 
    {
        i_entranceFee = _enteranceFee;
        i_interval = _interval;
        s_lastTimeStamp = block.timestamp;
        i_vrfCoordinator = VRFCoordinatorV2Interface(_vrfCoordinatorV2);
        i_gasLane=_gasLane;
        i_subscriptionId=_subscriptionId;
        i_callbackGasLimit=_callbackGasLimit;
    }

    function enterRaffle() external payable {
        //require(msg.value >= i_entranceFee,"Not enought money sent!");
        //custom errors are gas efficient than strings provided in required
        if(msg.value < i_entranceFee) {
            revert Raffle__SendMoreToEnterRaffle();
        }

        // Open, Calculating a winner
        if(s_raffleState != RaffleState.Open) {
            revert Raffle__RaffleNotOpen();
        }

        // enter the raffle
        s_players.push(payable(msg.sender));
        emit RaffleEnter(msg.sender);
    }

    // 1 we want this done automatically
    // 2 we want a real random winner

    // 1. Be true after some time interval
    // 2. The lottery to be open
    // 3. The contract has ETH
    // 4. Keepers has LINK
    function Checkupkeep(
        bytes memory /* checkData */
    ) public view returns(bool upkeepneeded, bytes memory /* performData */) {
        bool isOpen = RaffleState.Open == s_raffleState;
        bool timePassed = ((block.timestamp - s_lastTimeStamp) > i_interval);  //keep track of timepass
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepneeded = (timePassed && isOpen && hasBalance && hasPlayers);
        return (upkeepneeded,"0x0");

    }

    function performUpkeep(bytes calldata /* perform data */) external {
        (bool upkeepNeeded, ) = Checkupkeep("");
        if(!upkeepNeeded){
            revert Raffle_UpkeepNotNeeded();
        }
        s_raffleState = RaffleState.Calculating;

        uint256 requestId = i_vrfCoordinator.requestRandomWords(i_gasLane,i_subscriptionId,REQUEST_CONFIRMATIONS,i_callbackGasLimit,NUM_WORDS);
        emit RequestedRaffleWinner(requestId);
    }

    function fulfillRandomWords(uint256 /**requestId */, uint256[] memory randomWords) internal override {
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_players = new address payable[](0);
        s_raffleState = RaffleState.Open;
        s_lastTimeStamp = block.timestamp;
        /** "call" is the best way to send money from contract rather than using 'send' or 'transfer'  */
        (bool success, )= recentWinner.call{value: address(this).balance}("");
        if(!success) {
            revert Raffle__TransferFailed();
        }
        emit WinnerPicked(recentWinner);
    }
}
