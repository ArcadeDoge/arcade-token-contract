const { ethers, run, network } = require("hardhat");
const { NomicLabsHardhatPluginError } = require("hardhat/plugins");
const { BigNumber } = ethers;
const { MaxUint256 } = ethers.constants;
const { parseEther, formatEther } = ethers.utils;
const { addresses } = require("../settings.js");

let totalGas = 0;
const countTotalGas = async (tx) => {
  let res = tx;
  if (tx.deployTransaction) tx = tx.deployTransaction;
  if (tx.wait) res = await tx.wait();
  if (res.gasUsed) totalGas += parseInt(res.gasUsed);
  else console.log("no gas data", { res, tx });
};

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
  const arcade = await Arcade.deploy(
    addresses[network.name].Router,
    addresses[network.name].BUSD
  );
  await arcade.deployed();

  await countTotalGas(arcade);
  console.log("Deployed at:", arcade.address, { totalGas });

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

  try {
    // Verify
    console.log("Verifying IterableMapping: ", iterableMapping.address);
    await run("verify:verify", {
      address: iterableMapping.address
    });
  } catch (error) {
    if (error instanceof NomicLabsHardhatPluginError) {
      console.log("Contract source code already verified");
    } else {
      console.error(error);
    }
  }
  
  const dividenTracker = await arcade.dividendTracker();
  try {
    // Verify
    console.log("Verifying DividendTracker: ", dividenTracker);
    await run("verify:verify", {
      address: dividenTracker,
      constructorArguments: [
        addresses[network.name].BUSD
      ]
    });
  } catch (error) {
    if (error instanceof NomicLabsHardhatPluginError) {
      console.log("Contract source code already verified");
    } else {
      console.error(error);
    }
  }
}


main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });