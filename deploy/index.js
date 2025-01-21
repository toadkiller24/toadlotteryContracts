const { ethers, network } = require("hardhat");

async function main() {
  
  const [deployer] = await ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const subscriptionId = 1; 
  
  const devAddress = ""; 

  const ToadLottery = await ethers.getContractFactory("toadLottery");
  const lottery = await ToadLottery.deploy(subscriptionId, devAddress);

  console.log("toadLottery contract deployed to:", lottery.address);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });