// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

interface IToadNFT {
    function mint1(address to) payable external;
}

contract toadLottery is VRFConsumerBaseV2Plus, ReentrancyGuard {
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);
    event RequestedRandomness(uint256 requestId);
    event LotteryEnter(address indexed player);
    event WinnersSelected(address payable[3] winners, uint256[] amounts);
    event WithdrawalMade(address indexed recipient, uint256 amount);

    address constant public TOAD_NFT = 0x1e0ecdc616C548413F67A61B1c448548Ed4E5CDe;
    address constant public TOAD_ADDRESS = 0x1e0ecdc616C548413F67A61B1c448548Ed4E5CDe; 
    address constant public SOUP_KITCHEN = 0x1e0ecdc616C548413F67A61B1c448548Ed4E5CDe; 

    struct RequestStatus {
        bool fulfilled;
        bool exists;
        uint256[] randomWords;
    }
    mapping(uint256 => RequestStatus) public s_requests;

    uint256 public s_subscriptionId;
    uint256[] public requestIds;
    uint256 public lastRequestId;
    bytes32 public keyHash = 0x8596b430971ac45bdf6088665b9ad8e8630c9d5049ab54b14dff711bee7c0e26;
    uint32 public callbackGasLimit = 2500000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 3;

    address payable[] public players;
    address payable[3] public recentWinners;
    address payable public immutable devAddress;
    address payable[2] public fundingAddresses;
    uint256[] public latestRandomWords;
    bool public winnersSelected;
    bool public prizesDistributed;
    
    uint256 public constant MAXIMUM_PLAYERS = 10;
    uint256 public constant ENTRY_FEE = 0.001 ether;
    uint256 public constant MINT_FEE = 0.00001 ether;
    uint256 public constant FINAL_PRIZE_POOL = ENTRY_FEE * MAXIMUM_PLAYERS;
    
    mapping(address => uint256) public pendingWithdrawals;
    mapping(address => bool) public isWinner;
    mapping(address => bool) public hasParticipated;
    
    enum LOTTERY_STATE {
        OPEN,
        CLOSED,
        CALCULATING_WINNER
    }
    LOTTERY_STATE public lottery_state;

    IUniswapV2Router02 public uniswapRouter;

    error Lottery__InvalidEntry();
    error Lottery__MaxPlayersReached();
    error Lottery__InvalidState();
    error Lottery__DuplicateEntry();
    error Lottery__NoWithdrawalAvailable();
    error Lottery__WithdrawalFailed();
    error Lottery__VRFRequestFailed();
    error Lottery__NoRandomWords();
    error Lottery__WinnersAlreadySelected();
    error Lottery__PrizesAlreadyDistributed();
    error Lottery__WinnersNotSelected();

    constructor(
        uint256 subscriptionId,
        address payable _devAddress,
        address _uniswapRouter
    ) VRFConsumerBaseV2Plus(0xDA3b641D438362C440Ac5458c57e00a712b66700) {
        require(_devAddress != address(0), "Invalid dev address");
        require(_uniswapRouter != address(0), "Invalid router address");
        
        fundingAddresses = [
            payable(0xcD71336769347f8A2B5db79d2606Bef6bf36Ee93),
            payable(0xadC5d469f631333BC3aF98776614aC9bEBD3FAf9)
        ];
        s_subscriptionId = subscriptionId;
        lottery_state = LOTTERY_STATE.OPEN;
        devAddress = _devAddress;
        uniswapRouter = IUniswapV2Router02(_uniswapRouter);
    }

    function enter() public payable nonReentrant {
        if (msg.value != ENTRY_FEE) revert Lottery__InvalidEntry();
        if (lottery_state != LOTTERY_STATE.OPEN) revert Lottery__InvalidState();
        if (players.length >= MAXIMUM_PLAYERS) revert Lottery__MaxPlayersReached();
        
        for (uint256 i = 0; i < players.length; i++) {
            if (players[i] == msg.sender) revert Lottery__DuplicateEntry();
        }
        
        IToadNFT(TOAD_NFT).mint1{value:MINT_FEE}(msg.sender);
        
        players.push(payable(msg.sender));
        hasParticipated[msg.sender] = true;
        
        emit LotteryEnter(msg.sender);

        if (players.length == MAXIMUM_PLAYERS) {
            lottery_state = LOTTERY_STATE.CALCULATING_WINNER;
            try this.requestRandomWords() {
                // Request successful
            } catch {
                lottery_state = LOTTERY_STATE.OPEN;
                revert Lottery__VRFRequestFailed();
            }
        }
    }

    function requestRandomWords() external returns (uint256 requestId) {
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({
                        nativePayment: false
                    })
                )
            })
        );
        s_requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false
        });
        requestIds.push(requestId);
        lastRequestId = requestId;
        emit RequestSent(requestId, numWords);
        return requestId;
    }

    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] calldata _randomWords
    ) internal override {
        require(s_requests[_requestId].exists, "request not found");
        
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
        
        delete latestRandomWords;
        for(uint i = 0; i < _randomWords.length; i++) {
            latestRandomWords.push(_randomWords[i]);
        }
        
        emit RequestFulfilled(_requestId, _randomWords);
        
        _selectWinners();
    }

    function _selectWinners() internal {
        if (latestRandomWords.length < numWords) revert Lottery__NoRandomWords();
        if (winnersSelected) revert Lottery__WinnersAlreadySelected();
        if (players.length != MAXIMUM_PLAYERS) revert Lottery__InvalidState();
        
        bool[] memory used = new bool[](MAXIMUM_PLAYERS);
        
        for (uint256 i = 0; i < 3; i++) {
            uint256 index = latestRandomWords[i] % MAXIMUM_PLAYERS;
            
            while (used[index]) {
                index = (index + 1) % MAXIMUM_PLAYERS;
            }
            used[index] = true;
            
            address payable winner = players[index];
            recentWinners[i] = winner;
            isWinner[winner] = true;
        }
        
        winnersSelected = true;
        emit WinnersSelected(recentWinners, new uint256[](3));
        
        _distributePrizes();
    }
    
    function _distributePrizes() internal {
        if (!winnersSelected) revert Lottery__WinnersNotSelected();
        if (prizesDistributed) revert Lottery__PrizesAlreadyDistributed();
        
        uint256 winnersShare = (FINAL_PRIZE_POOL * 60) / 100;
        uint256 singleWinnerShare = winnersShare / 3;
        uint256 devShare = (FINAL_PRIZE_POOL * 5) / 100;
        // uint256 contractRemainder = (FINAL_PRIZE_POOL * 5) / 100;
        uint256 fundingSharePerAddress = (FINAL_PRIZE_POOL * 10) / 100;
        
        for (uint256 i = 0; i < 3; i++) {
            pendingWithdrawals[recentWinners[i]] += singleWinnerShare;
        }
        
        pendingWithdrawals[devAddress] += devShare;
        pendingWithdrawals[fundingAddresses[0]] += fundingSharePerAddress;
        pendingWithdrawals[fundingAddresses[1]] += fundingSharePerAddress;
        
        uint256[] memory amounts = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            amounts[i] = singleWinnerShare;
        }
        
        emit WinnersSelected(recentWinners, amounts);
        
        delete players;
        prizesDistributed = true;
        lottery_state = LOTTERY_STATE.OPEN;
        
        _startNewRound();
    }
    
    function _startNewRound() internal {
        require(prizesDistributed, "Previous round not complete");
        winnersSelected = false;
        prizesDistributed = false;
    }

    function burnToads() external {
        uint256 weiAmount = address(this).balance;
        require(weiAmount > 0, "Contract has no Ether to swap");
        
        address[] memory path = new address[](2);
        path[0] = uniswapRouter.WETH();
        path[1] = TOAD_ADDRESS;
        
        uint256 deadline = block.timestamp + 180;
        
        uniswapRouter.swapExactETHForTokens{value: weiAmount}(
            0,
            path,
            SOUP_KITCHEN,
            deadline
        );
    }

    function selectWinners() external {
        _selectWinners();
    }
    
    function distributePrizes() external {
        _distributePrizes();
    }
    
    function startNewRound() external {
        _startNewRound();
    }

    function withdraw() public nonReentrant {
        uint256 amount = pendingWithdrawals[msg.sender];
        if (amount == 0) revert Lottery__NoWithdrawalAvailable();
        
        pendingWithdrawals[msg.sender] = 0;
        
        (bool success,) = msg.sender.call{value: amount}("");
        if (!success) revert Lottery__WithdrawalFailed();
        
        emit WithdrawalMade(msg.sender, amount);
    }

    function getRequestStatus(
        uint256 _requestId
    ) external view returns (bool fulfilled, uint256[] memory randomWords) {
        require(s_requests[_requestId].exists, "request not found");
        RequestStatus memory request = s_requests[_requestId];
        return (request.fulfilled, request.randomWords);
    }

    function getWinningNumbers() external view returns (uint[3] memory) {
        require(latestRandomWords.length >= numWords, "Random numbers not yet available");
        
        uint[3] memory finalNumbers;
        for(uint i = 0; i < 3 && i < latestRandomWords.length; i++) {
            finalNumbers[i] = latestRandomWords[i] % 20;
        }
        
        return finalNumbers;
    }

    function hasRandomNumbers() external view returns (bool) {
        return latestRandomWords.length >= numWords;
    }

    function getPlayers() public view returns (address payable[] memory) {
        return players;
    }

    function getPlayerStatus(
        address player
    ) public view returns (bool participated, bool won, uint256 pendingAmount) {
        return (hasParticipated[player], isWinner[player], pendingWithdrawals[player]);
    }

    function getRecentWinners() public view returns (address payable[3] memory) {
        return recentWinners;
    }
}
