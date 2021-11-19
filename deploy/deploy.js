const { ethers, run, network } = require("hardhat");
const { NomicLabsHardhatPluginError } = require("hardhat/plugins");
const { BigNumber } = ethers;
const { MaxUint256 } = ethers.constants;
const { parseEther, formatEther } = ethers.utils;
const { addresses } = require("../settings.js");

async function main() {
  if (network.name !== "testnet" && network.name !== "mainnet") return;

  console.log("Deploying IterableMapping contract...");

  const IterableMapping = await ethers.getContractFactory("IterableMapping");
  const iterableMapping = await IterableMapping.deploy();
  await iterableMapping.deployed();

  console.log("Deployed at:", iterableMapping.address)

  console.log("Deploying Arcade token contract...");

  const Arcade = await ethers.getContractFactory("Arcade", {
    libraries: {
      IterableMapping: iterableMapping.address,
    },
  });
  arcade = await Arcade.deploy(
    addresses[network.name].Router,
    addresses[network.name].BUSD
  );
  await arcade.deployed();

  console.log("Deployed at:", arcade.address);

  const totalSupply = await arcade.totalSupply();

  console.log("Arcade coin has total supply of", formatEther(totalSupply));

  try {
    // Verify
    console.log("Verifying Arcade: ", arcade.address);
    await run("verify:verify", {
      address: arcade.address,
      constructorArguments: [
        addresses[network.name].Router,
        addresses[network.name].BUSD
      ],
      libraries: {
        IterableMapping: iterableMapping.address
      }
    });
  } catch (error) {
    if (error instanceof NomicLabsHardhatPluginError) {
      console.log("Contract source code already verified");
    } else {
      console.error(error);
    }
  }

  console.log("Deploying DividenTracker contract...");
  const ARCDividendTracker = await ethers.getContractFactory("ARCDividendTracker", {
    libraries: {
      IterableMapping: iterableMapping.address,
    },
  });
  const dividenTracker = await ARCDividendTracker.deploy();
  await dividenTracker.deployed();

  console.log("Deployed at:", dividenTracker.address);

  try {
    console.log('Verifying DividendTracker', dividenTracker.address);

    await run("verify:verify", {
      address: dividenTracker.address,
    });
  } catch (error) {
    if (error instanceof NomicLabsHardhatPluginError) {
      console.log("Contract source code already verified");
    } else {
      console.error(error);
    }
  }

  console.log("Set new DividenTracker");
  await dividenTracker.transferOwnership(arcade.address);
  await arcade.updateDividendTracker(dividenTracker.address);
}


main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });