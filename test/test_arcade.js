const { ethers } = require("hardhat");
const { describe } = require("mocha");
let chai = require("chai");
chai.use(require("chai-as-promised"));
const { assert, expect } = chai;
const { BigNumber } = ethers;
const { MaxUint256 } = ethers.constants;
const { parseEther } = ethers.utils;
const { addresses } = require("../settings.js");

const ETH_BALANCE_THRESHOLD = parseEther("0.001");
const INITIAL_ARC_RESERVES = parseEther("500000000");
const INITIAL_ETH_RESERVES = parseEther("100");

let arcade;
let owner;
let rewardAcct1;
let rewardAcct2;
let liqAcct;
let noFeesAcct;

async function setUp() {
  const IterableMapping = await ethers.getContractFactory("IterableMapping");
  const iterableMapping = await IterableMapping.deploy();
  await iterableMapping.deployed();

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

  [owner, rewardAcct1, rewardAcct2, liqAcct, noFeesAcct] =
    await ethers.getSigners();

  // Add initial liquidity.
  const routerAddress = addresses[network.name].Router;
  let router = await ethers.getContractAt("IUniswapV2Router02", routerAddress);

  await expect(arcade.approve(routerAddress, MaxUint256)).to.eventually.be
    .fulfilled;
  await expect(
    router.addLiquidityETH(
      arcade.address,
      INITIAL_ARC_RESERVES,
      parseEther("0"), // slippage is unavoidable
      parseEther("0"), // slippage is unavoidable
      liqAcct.address,
      MaxUint256,
      { value: INITIAL_ETH_RESERVES }
    )
  ).to.eventually.be.fulfilled;
}

describe("Arcade", function () {
  before(setUp);

  // it("should return correct name", async function () {
  //   await expect(arcade.name()).to.eventually.equal("ARCADE");
  // });

  // it("should return correct symbol", async function () {
  //   await expect(arcade.symbol()).to.eventually.equal("ARC");
  // });

  // it("should have the 50B supply", async function () {
  //   await expect(arcade.totalSupply()).to.eventually.equal(
  //     parseEther("1000000000000000000000000000") // 1 * (10**9) * (10**18)
  //   );
  // });


  it("should allow accounts to transfer before go-live", async function () {
    await expect(arcade.canTransferBeforeTradingIsEnabled(noFeesAcct.address)).to
      .eventually.be.false;
    await expect(arcade.allowTransferBeforeTradingIsEnabled(noFeesAcct.address))
      .to.be.fulfilled;
    await expect(arcade.canTransferBeforeTradingIsEnabled(noFeesAcct.address)).to
      .eventually.be.true;
  });

  it("should exclude account from fees", async function () {
    await expect(arcade.isExcludedFromFees(noFeesAcct.address)).to.eventually.be
      .false;
    await expect(arcade.excludeFromFees(noFeesAcct.address)).to.eventually.be
      .fulfilled;
    await expect(arcade.isExcludedFromFees(noFeesAcct.address)).to.eventually.be
      .true;
  });

  it("should use 18 decimals", async function () {
    await expect(arcade.decimals()).to.eventually.equal(BigNumber.from(18));
  });

  it("should return the max sell token amount", async function () {
    await expect(arcade.MAX_SELL_TRANSACTION_AMOUNT()).to.eventually.equal(
      parseEther("1000000")
    );
  });

  it("should return the liquidation amount threshold", async function () {
    await expect(arcade.liquidateTokensAtAmount()).to.eventually.equal(
      parseEther("100000")
    );
  });

  it("should update the liquidation amount threshold", async function () {
    await expect(arcade.updateLiquidationThreshold(parseEther("200001"))).to
      .eventually.be.rejected;

    const tx = expect(arcade.updateLiquidationThreshold(parseEther("80000")));
    await tx.to
      .emit(arcade, "LiquidationThresholdUpdated")
      .withArgs(parseEther("80000"), parseEther("100000"));
    await tx.to.eventually.be.fulfilled;
  });

  it("should have the correct owner", async function () {
    await expect(arcade.owner()).to.eventually.equal(owner.address);
  });

  it("should enforce the onlyOwner modifier", async function () {
    await expect(
      arcade.connect(noFeesAcct).excludeFromFees(noFeesAcct.address, true)
    ).to.eventually.be.rejected;
  });

  it("should have the correct liquidityWallet", async function () {
    await expect(arcade.liquidityWallet()).to.eventually.equal(owner.address);
  });

  it("should allow owner to update the liquidityWallet", async function () {
    await expect(arcade.updateLiquidityWallet(liqAcct.address)).to.eventually.be
      .fulfilled;
    await expect(arcade.liquidityWallet()).to.eventually.equal(liqAcct.address);
  });

  it("should update the gas for processing dividends", async function () {
    await expect(arcade.updateGasForProcessing(400000)).to.eventually.be
      .fulfilled;
  });

  it("should have the correct ETH rewards fee", async function () {
    await expect(arcade.ETH_REWARDS_FEE()).to.eventually.equal(BigNumber.from(4));
  });

  it("should have the correct liquidity fee", async function () {
    await expect(arcade.LIQUIDITY_FEE()).to.eventually.equal(BigNumber.from(2));
  });

  it("should have the correct total fee", async function () {
    await expect(arcade.TOTAL_FEES()).to.eventually.equal(BigNumber.from(6));
  });

  it("should have claim wait set to 1 hour by default", async function () {
    await expect(arcade.getClaimWait()).to.eventually.equal(BigNumber.from(3600));
  });

  it("should return whether account is excluded from fees", async function () {
    await expect(arcade.isExcludedFromFees(owner.address)).to.eventually.be.true;
    await expect(arcade.isExcludedFromFees(liqAcct.address)).to.eventually.be
      .true;
    await expect(arcade.isExcludedFromFees(noFeesAcct.address)).to.eventually.be
      .true;
    await expect(arcade.isExcludedFromFees(rewardAcct1.address)).to.eventually.be
      .false;
  });

  it("should always have the uniswap pair in the AMM pairs", async function () {
    const uniPairAddress = await arcade.uniswapV2Pair();
    await expect(arcade.automatedMarketMakerPairs(uniPairAddress)).to.eventually
      .be.true;
  });

  it("should only allow owner to transfer prior to go-live", async function () {
    await expect(arcade.tradingEnabled()).to.eventually.be.false;

    await expect(arcade.approve(owner.address, parseEther("10000"))).to.eventually
      .be.fulfilled;
    await expect(
      arcade.transferFrom(owner.address, rewardAcct1.address, parseEther("10000"))
    ).to.eventually.be.fulfilled;

    await expect(
      arcade.connect(rewardAcct1).approve(owner.address, parseEther("1"))
    ).to.eventually.be.fulfilled;
    await expect(
      arcade.transferFrom(
        rewardAcct1.address,
        noFeesAcct.address,
        parseEther("1")
      )
    ).to.eventually.be.rejected;
  });
  
});
