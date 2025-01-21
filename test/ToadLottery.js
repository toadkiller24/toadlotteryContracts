const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("toadLottery", function () {
    let lottery, devAddress, fundingAddresses, owner, player1, player2, player3, player4, player5, player6, player7, player8, player9, player10;

    const ENTRY_FEE = ethers.utils.parseEther("0.001");
    const MAX_PLAYERS = 4;

    beforeEach(async function () {
        [owner, player1, player2, player3, player4, devAddress, ...fundingAddresses] = await ethers.getSigners();

       
        const ToadLottery = await ethers.getContractFactory("toadLottery");
        lottery = await ToadLottery.deploy(1, devAddress.address); 
        await lottery.deployed();

        await owner.sendTransaction({
            to: lottery.address,
            value: ENTRY_FEE.mul(MAX_PLAYERS),  
        });
    });

    it("should allow players to enter the lottery", async function () {
        // Player 1 enters
        await expect(lottery.connect(player1).enter({ value: ENTRY_FEE }))
            .to.emit(lottery, "LotteryEnter")
            .withArgs(player1.address);

        // Player 2 enters
        await expect(lottery.connect(player2).enter({ value: ENTRY_FEE }))
            .to.emit(lottery, "LotteryEnter")
            .withArgs(player2.address);

        const players = await lottery.getPlayers();
        expect(players.length).to.equal(2);
    });

    it("should not allow more than MAX_PLAYERS to enter", async function () {
        await lottery.connect(player1).enter({ value: ENTRY_FEE });
        await lottery.connect(player2).enter({ value: ENTRY_FEE });
        await lottery.connect(player3).enter({ value: ENTRY_FEE });
        await lottery.connect(player4).enter({ value: ENTRY_FEE });
        await lottery.connect(player5).enter({ value: ENTRY_FEE });
        await lottery.connect(player6).enter({ value: ENTRY_FEE });
        await lottery.connect(player7).enter({ value: ENTRY_FEE });
        await lottery.connect(player8).enter({ value: ENTRY_FEE });
        await lottery.connect(player9).enter({ value: ENTRY_FEE });
        await lottery.connect(player10).enter({ value: ENTRY_FEE });

        await expect(lottery.connect(owner).enter({ value: ENTRY_FEE })).to.be.revertedWith(
            "Lottery__MaxPlayersReached"
        );
    });

    it("should request random words when MAX_PLAYERS enter", async function () {
        await lottery.connect(player1).enter({ value: ENTRY_FEE });
        await lottery.connect(player2).enter({ value: ENTRY_FEE });
        await lottery.connect(player3).enter({ value: ENTRY_FEE });
        await lottery.connect(player4).enter({ value: ENTRY_FEE });
        await lottery.connect(player5).enter({ value: ENTRY_FEE });
        await lottery.connect(player6).enter({ value: ENTRY_FEE });
        await lottery.connect(player7).enter({ value: ENTRY_FEE });
        await lottery.connect(player8).enter({ value: ENTRY_FEE });
        await lottery.connect(player9).enter({ value: ENTRY_FEE });
        await lottery.connect(player10).enter({ value: ENTRY_FEE });

        // Mock VRF request and fulfillment
        const requestId = await lottery.connect(owner).requestRandomWords();

        await expect(lottery.fulfillRandomWords(requestId, [123, 456, 789]))
            .to.emit(lottery, "RequestFulfilled")
            .withArgs(requestId, [123, 456, 789]);
    });

    it("should select winners once random numbers are fulfilled", async function () {
        // Simulate entering players
        await lottery.connect(player1).enter({ value: ENTRY_FEE });
        await lottery.connect(player2).enter({ value: ENTRY_FEE });
        await lottery.connect(player3).enter({ value: ENTRY_FEE });
        await lottery.connect(player4).enter({ value: ENTRY_FEE });
        await lottery.connect(player5).enter({ value: ENTRY_FEE });
        await lottery.connect(player6).enter({ value: ENTRY_FEE });
        await lottery.connect(player7).enter({ value: ENTRY_FEE });
        await lottery.connect(player8).enter({ value: ENTRY_FEE });
        await lottery.connect(player9).enter({ value: ENTRY_FEE });
        await lottery.connect(player10).enter({ value: ENTRY_FEE });

        // Request random words
        const requestId = await lottery.connect(owner).requestRandomWords();

        // Simulate VRF fulfilling with random words
        await lottery.fulfillRandomWords(requestId, [100, 200, 300]);

        const winners = await lottery.getRecentWinners();
        expect(winners.length).to.equal(3);
        expect(winners[0]).to.not.be.null;
    });

    it("should distribute prizes to winners correctly", async function () {
        // Simulate entering players
        await lottery.connect(player1).enter({ value: ENTRY_FEE });
        await lottery.connect(player2).enter({ value: ENTRY_FEE });
        await lottery.connect(player3).enter({ value: ENTRY_FEE });
        await lottery.connect(player4).enter({ value: ENTRY_FEE });
        await lottery.connect(player5).enter({ value: ENTRY_FEE });
        await lottery.connect(player6).enter({ value: ENTRY_FEE });
        await lottery.connect(player7).enter({ value: ENTRY_FEE });
        await lottery.connect(player8).enter({ value: ENTRY_FEE });
        await lottery.connect(player9).enter({ value: ENTRY_FEE });
        await lottery.connect(player10).enter({ value: ENTRY_FEE });

        // Request random words
        const requestId = await lottery.connect(owner).requestRandomWords();

        // Simulate VRF fulfilling with random words
        await lottery.fulfillRandomWords(requestId, [100, 200, 300]);

        // Distribute prizes
        await expect(lottery.connect(owner).distributePrizes())
            .to.emit(lottery, "WinnersSelected")
            .withArgs(
                [player1.address, player2.address, player3.address],
                [ethers.utils.parseEther("0.02"), ethers.utils.parseEther("0.02"), ethers.utils.parseEther("0.02")]
            );

        // Verify balances
        const player1Balance = await ethers.provider.getBalance(player1.address);
        expect(player1Balance).to.be.gt(ethers.utils.parseEther("10000"));

        const player2Balance = await ethers.provider.getBalance(player2.address);
        expect(player2Balance).to.be.gt(ethers.utils.parseEther("10000"));
    });

    it("should allow players to withdraw their winnings", async function () {
        // Simulate entering players
        await lottery.connect(player1).enter({ value: ENTRY_FEE });
        await lottery.connect(player2).enter({ value: ENTRY_FEE });
        await lottery.connect(player3).enter({ value: ENTRY_FEE });
        await lottery.connect(player4).enter({ value: ENTRY_FEE });
        await lottery.connect(player5).enter({ value: ENTRY_FEE });
        await lottery.connect(player6).enter({ value: ENTRY_FEE });
        await lottery.connect(player7).enter({ value: ENTRY_FEE });
        await lottery.connect(player8).enter({ value: ENTRY_FEE });
        await lottery.connect(player9).enter({ value: ENTRY_FEE });
        await lottery.connect(player10).enter({ value: ENTRY_FEE });

        // Request random words
        const requestId = await lottery.connect(owner).requestRandomWords();

        // Simulate VRF fulfilling with random words
        await lottery.fulfillRandomWords(requestId, [100, 200, 300]);

        // Distribute prizes
        await lottery.connect(owner).distributePrizes();

        // Player 1 withdraws
        await expect(lottery.connect(player1).withdraw())
            .to.emit(lottery, "WithdrawalMade")
            .withArgs(player1.address, ethers.utils.parseEther("0.02"));
        
        // Verify player1 balance is updated
        const player1BalanceAfter = await ethers.provider.getBalance(player1.address);
        expect(player1BalanceAfter).to.be.gt(ethers.utils.parseEther("10000"));
    });

    it("should not allow withdraw if there are no pending withdrawals", async function () {
        await expect(lottery.connect(player1).withdraw()).to.be.revertedWith(
            "Lottery__NoWithdrawalAvailable"
        );
    });
});