// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "./ARCDividendTracker.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router.sol";

contract Arcade is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public uniswapV2Router;
    address public immutable uniswapV2Pair;

    bool private swapping;

    ARCDividendTracker public dividendTracker;

    address public liquidityWallet;

    bool public maxSellTxEnabled = true;
    uint256 public maxSellTransactionAmount = (10**9) * (10**18);

    // Percentages for buyback, marketing, reflection, charity and dev
    uint256 public _burnFee = 100; // 1%
    uint256 public _farmingFee = 0; // 0%
    
    uint256 public _reflectionFee = 0; // 0%
    uint256 public _buyBackFee = 500; // 5%, burn per
    uint256 public _charityFee = 0; // 0%
    uint256 public _devFee = 200; // 2%
    uint256 public _marketingFee = 200; // 2%

    uint256 public _totalFees = _buyBackFee + _reflectionFee + _charityFee + _devFee + _marketingFee;

    // false means don't take transfer fee between wallets
    bool public _walletToWalletTax = false;

    /**
     * BUSD on Mainnet: 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56
     */
    address public immutable BUSD;
    address public DEAD = 0x000000000000000000000000000000000000dEaD;

    address public buyBackAddress;
    address public marketingAddress;
    address public charityAddress;
    address public devAddress;
    address public farmingAddress;

    mapping (address => uint256[]) private _transactTime; // last transaction time(block.timestamp)
    mapping (address => bool) private _isExcludedFromAntiBot;
    mapping(address => bool) public _isBlackListed;
    bool public _antiBotEnabled = true;
    uint256 public _botLimitTimestamp;  // timestamp when set variable
    uint256 public _botTransLimitTime = 600; // transaction limit time in second
    uint256 public _botTransLimitCount = 4; // transaction limit count within _botExpiration(second)

    // use by default 150,000 gas to process auto-claiming dividends
    uint256 public gasForProcessing = 150000;

    // liquidate tokens for ETH when the contract reaches 100k tokens by default
    uint256 public liquidateTokensAtAmount = 100000 * (10**18);

    // whether the token can already be traded
    bool public tradingEnabled = true; // remove true condition

    // exclude from fees and max transaction amount
    mapping (address => bool) private _isExcludedFromFees;

    // addresses that can make transfers before presale is over
    mapping (address => bool) public canTransferBeforeTradingIsEnabled;

    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping (address => bool) public automatedMarketMakerPairs;

    event AntiBotEnabledUpdated(bool enabled);

    event OnBlackList(address account);

    event SetBlackListUser(address indexed account, bool enabled);

    event MaxSellTransactionAmountEnabled(bool enabled);

    event MaxSellTransactionAmountUpdated(uint256 indexed _maxSellTransactionAmount);

    event SetWalletToWalletTax(bool enabled);

    event UpdatedDividendTracker(address indexed newAddress, address indexed oldAddress);

    event UpdatedUniswapV2Router(address indexed newAddress, address indexed oldAddress);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event LiquidityWalletUpdated(address indexed newLiquidityWallet, address indexed oldLiquidityWallet);

    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event LiquidationThresholdUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event Liquified(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    event SentDividends(
        uint256 tokensSwapped,
        uint256 amount
    );

    event ProcessedDividendTracker(
        uint256 iterations,
        uint256 claims,
        uint256 lastProcessedIndex,
        bool indexed automatic,
        uint256 gas,
        address indexed processor
    );

    modifier antiBots(address from, address to) {
        require(
            !_isBlackListed[from] && !_isBlackListed[to],
            "BlackListed account"
        );
        _;
    }

    constructor(address _router, address _busd) ERC20("ARCADE", "ARC") {
        dividendTracker = new ARCDividendTracker();
        liquidityWallet = owner();

        BUSD = _busd;

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(_router);
        // Create a uniswap pair for this new token
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        buyBackAddress = 0x14719e7e6bEEDFf6f768307A223FEFBe6669b923;
        marketingAddress = 0x99Cc9963CcBED099900988bc9E2aacc66A7B724f;
        charityAddress = 0x5eb7C4114525b597833022E21F9d6865a1476a59;
        devAddress = 0x79b0b5aDEF94d3768D40e19d9D53406A8933c025;
        farmingAddress = 0xEcC15277b86964db2454cc44CeB1cC90957402E6;

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);

        // exclude from receiving dividends
        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(address(this));
        dividendTracker.excludeFromDividends(owner());
        dividendTracker.excludeFromDividends(address(_uniswapV2Router));

        // exclude from paying fees or having max transaction amount
        excludeFromFees(liquidityWallet);
        excludeFromFees(address(this));
        // excludeFromFees(buyBackAddress);
        excludeFromFees(marketingAddress);
        // excludeFromFees(charityAddress);
        excludeFromFees(devAddress);
        // excludeFromFees(farmingAddress);
        excludeFromFees(DEAD);

        // enable owner wallet to send tokens before presales are over.
        canTransferBeforeTradingIsEnabled[owner()] = true;

        /*
            _mint is an internal function in ERC20.sol that is only called here,
            and CANNOT be called ever again
        */
        _mint(owner(), 1 * (10**9) * (10**18));
    }

    receive() external payable {

    }

    function activate() external onlyOwner {
        require(!tradingEnabled, "Arcade: Trading is already enabled");
        tradingEnabled = true;
    }

    function updateDividendTracker(address newAddress) external onlyOwner {
        require(newAddress != address(dividendTracker), "Arcade: The dividend tracker already has that address");
        require(newAddress != address(0), "Arcade: newAddress is a zero address");

        ARCDividendTracker newDividendTracker = ARCDividendTracker(payable(newAddress));

        require(newDividendTracker.owner() == address(this), "Arcade: The new dividend tracker must be owned by the ARC token contract");

        newDividendTracker.excludeFromDividends(address(newDividendTracker));
        newDividendTracker.excludeFromDividends(address(this));
        newDividendTracker.excludeFromDividends(owner());
        newDividendTracker.excludeFromDividends(address(uniswapV2Router));

        emit UpdatedDividendTracker(newAddress, address(dividendTracker));

        dividendTracker = newDividendTracker;
    }

    function updateUniswapV2Router(address newAddress) external onlyOwner {
        require(newAddress != address(uniswapV2Router), "Arcade: The router already has that address");
        require(newAddress != address(0), "Arcade: newAddress is a zero address");

        emit UpdatedUniswapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newAddress);
    }

    function excludeFromFees(address account) public onlyOwner {
        require(!_isExcludedFromFees[account], "Arcade: Account is already excluded from fees");
        _isExcludedFromFees[account] = true;
    }

    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        require(pair != uniswapV2Pair, "Arcade: The Uniswap pair cannot be removed from automatedMarketMakerPairs");
        require(pair != address(0), "Arcade: pair is a zero address");

        _setAutomatedMarketMakerPair(pair, value);
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, "Arcade: Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[pair] = value;

        if (value) {
            dividendTracker.excludeFromDividends(pair);
        }

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function allowTransferBeforeTradingIsEnabled(address account) external onlyOwner {
        require(!canTransferBeforeTradingIsEnabled[account], "Arcade: Account is already allowed to transfer before trading is enabled");
        canTransferBeforeTradingIsEnabled[account] = true;
    }

    function updateLiquidityWallet(address newLiquidityWallet) external onlyOwner {
        require(newLiquidityWallet != liquidityWallet, "Arcade: The liquidity wallet is already this address");
        require(newLiquidityWallet != address(0), "Arcade: newLiquidityWallet is a zero address");
        excludeFromFees(newLiquidityWallet);
        emit LiquidityWalletUpdated(newLiquidityWallet, liquidityWallet);
        liquidityWallet = newLiquidityWallet;
    }

    function setMaxSellTxEnabled(bool enabled) external onlyOwner() {
        maxSellTxEnabled = enabled;
        emit MaxSellTransactionAmountEnabled(maxSellTxEnabled);
    }

    function updateMaxSellTransactionAmount(uint256 _maxSellTransactionAmount) external onlyOwner {
        require(maxSellTransactionAmount >= 0, "Arcade: invalid maximum transaction amount");
        maxSellTransactionAmount = _maxSellTransactionAmount;
        emit MaxSellTransactionAmountUpdated(maxSellTransactionAmount);
    }

    function setWalletToWalletTax(bool enabled) external onlyOwner {
        _walletToWalletTax = enabled;
        emit SetWalletToWalletTax(enabled);
    }

    function setFeeReceivers(
        address _marketingFeeReceiver,
        address _charityFeeReceiver,
        address _devFeeReceiver,
        address _buybackReceiver,
        address _farmingReceiver
    )
        external onlyOwner 
    {
        marketingAddress = _marketingFeeReceiver;
        charityAddress = _charityFeeReceiver;
        devAddress = _devFeeReceiver;
        buyBackAddress = _buybackReceiver;
        farmingAddress = _farmingReceiver;
    }

    function setFees(
        uint256 reflectionFee,
        uint256 buybackFee,
        uint256 charityFee,
        uint256 marketingFee,
        uint256 devFee,
        uint256 burnFee,
        uint256 farmingFee
    )
        external onlyOwner
    {
        _reflectionFee = reflectionFee;
        _buyBackFee = buybackFee;
        _charityFee = charityFee;
        _marketingFee = marketingFee;
        _devFee = devFee;
        _burnFee = burnFee;
        _farmingFee = farmingFee;
        _totalFees = reflectionFee + buybackFee + charityFee + marketingFee + devFee;
    }

    function setAntiBotEnabled(bool enabled) external onlyOwner() {
        _antiBotEnabled = enabled;
        _botLimitTimestamp = block.timestamp;
        emit AntiBotEnabledUpdated(enabled);
    }

    function setBotTransLimit(uint256 transTime, uint256 transCount) external onlyOwner() {
        _botTransLimitTime = transTime;
        _botTransLimitCount = transCount;
        _botLimitTimestamp = block.timestamp;
    }

    function setBlackListUser(address user, bool enabled) external onlyOwner {
        _isBlackListed[user] = enabled;
        emit SetBlackListUser(user, enabled);
    }

    function updateGasForProcessing(uint256 newValue) external onlyOwner {
        // Need to make gas fee customizable to future-proof against Ethereum network upgrades.
        require(newValue != gasForProcessing, "Arcade: Cannot update gasForProcessing to same value");
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function updateLiquidationThreshold(uint256 newValue) external onlyOwner {
        require(newValue <= (10**9) * (10 ** 18), "Arcade: liquidateTokensAtAmount must be less than 10**9");
        require(newValue != liquidateTokensAtAmount, "Arcade: Cannot update gasForProcessing to same value");
        emit LiquidationThresholdUpdated(newValue, liquidateTokensAtAmount);
        liquidateTokensAtAmount = newValue * (10 ** 18);
    }

    function updateGasForTransfer(uint256 gasForTransfer) external onlyOwner {
        dividendTracker.updateGasForTransfer(gasForTransfer);
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getGasForTransfer() external view returns(uint256) {
        return dividendTracker.gasForTransfer();
    }

    function getClaimWait() external view returns(uint256) {
        return dividendTracker.claimWait();
    }

    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    function isExcludedFromFees(address account) external view returns(bool) {
        return _isExcludedFromFees[account];
    }

    function withdrawableDividendOf(address account) external view returns(uint256) {
        return dividendTracker.withdrawableDividendOf(account);
    }

    function dividendTokenBalanceOf(address account) external view returns (uint256) {
        return dividendTracker.balanceOf(account);
    }

    function getAccountDividendsInfo(address account)
    external view returns (
        address,
        int256,
        int256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256) {
        return dividendTracker.getAccount(account);
    }

    function getAccountDividendsInfoAtIndex(uint256 index)
    external view returns (
        address,
        int256,
        int256,
        uint256,
        uint256,
        uint256,
        uint256,
        uint256) {
        return dividendTracker.getAccountAtIndex(index);
    }

    function processDividendTracker(uint256 gas) external {
        (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = dividendTracker.process(gas);
        emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, tx.origin);
    }

    function claim() external {
        dividendTracker.processAccount(payable(msg.sender), false);
    }

    function getLastProcessedIndex() external view returns(uint256) {
        return dividendTracker.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders() external view returns(uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        bool tradingIsEnabled = tradingEnabled;

        // only whitelisted addresses can make transfers before the public presale is over.
        if (!tradingIsEnabled) {
            require(canTransferBeforeTradingIsEnabled[from], "Arcade: This account cannot send tokens until trading is enabled");
        }

        if (amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        if (!swapping &&
            tradingIsEnabled &&
            automatedMarketMakerPairs[to] && // sells only by detecting transfer to automated market maker pair
            from != address(uniswapV2Router) && //router -> pair is removing liquidity which shouldn't have max
            !_isExcludedFromFees[to] && //no max for those excluded from fees
            maxSellTxEnabled
        ) {
            require(amount <= maxSellTransactionAmount, "Sell transfer amount exceeds the maxSellTransactionAmount.");
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= liquidateTokensAtAmount;

        if (tradingIsEnabled &&
            canSwap &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            from != liquidityWallet &&
            to != liquidityWallet
        ) {
            swapping = true;

            uint256 sellTokens = balanceOf(address(this));
            swapTokensForBusd(sellTokens);
            uint256 dividends = IERC20(BUSD).balanceOf(address(this));
            swapAndSendDividends(dividends);

            swapping = false;
        }

        bool takeFee = tradingIsEnabled && !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        if (!_walletToWalletTax) {
            if (from != uniswapV2Pair && to != uniswapV2Pair &&
                from != address(uniswapV2Router) && to != address(uniswapV2Router)) {
                takeFee = false;
            }
        }

        if (takeFee) {
            uint256 fees = amount.mul(_totalFees).div(10000);
            super._transfer(from, address(this), fees);

            uint256 farmingFees = amount.mul(_farmingFee).div(10000);
            super._transfer(from, farmingAddress, farmingFees);

            uint256 burnTokens = amount.mul(_burnFee).div(10000);
            amount = amount.sub(fees).sub(farmingFees).sub(burnTokens);
            super._burn(from, burnTokens);
        }

        super._transfer(from, to, amount);

        try dividendTracker.setBalance(payable(from), balanceOf(from)) {} catch {}
        try dividendTracker.setBalance(payable(to), balanceOf(to)) {} catch {}

        if (!swapping) {
            uint256 gas = gasForProcessing;

            try dividendTracker.process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
                emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
            } catch {}
        }

        if (_antiBotEnabled && !_isExcludedFromAntiBot[from]) {
            if (_transactTime[from].length < _botTransLimitCount) {
                _transactTime[from].push(block.timestamp);
                return;
            }
            // push array left
            for (uint256 i = 1; i < _botTransLimitCount; i++) {
                _transactTime[from][i - 1] = _transactTime[from][i];
            }
            _transactTime[from][_botTransLimitCount - 1] = block.timestamp;
            if (_transactTime[from][0] > _botLimitTimestamp &&
                _transactTime[from][_botTransLimitCount - 1] - _transactTime[from][0] < _botTransLimitTime) {
                _isBlackListed[from] = true;
                emit OnBlackList(from);
            }
        }
    }
    
    function swapAndLiquify(uint256 tokens) private {
        // split the contract balance into halves
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);

        emit Liquified(half, newBalance, otherHalf);
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            liquidityWallet,
            block.timestamp
        );
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function swapTokensForBusd(uint256 tokenAmount) private {
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        path[2] = BUSD;

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function swapAndSendToFee(uint256 newBalance) private  {
        uint256 buyBackCharityDevMarketingFee = _buyBackFee.add(_charityFee).add(_devFee).add(_marketingFee);

        uint256 newBalanceBuyBack = newBalance.mul(_buyBackFee).div(buyBackCharityDevMarketingFee);
        uint256 newBalanceDev = newBalance.mul(_devFee).div(buyBackCharityDevMarketingFee);
        uint256 newBalanceMarketing = newBalance.mul(_marketingFee).div(buyBackCharityDevMarketingFee);
        uint256 newBalanceCharity = newBalance.sub(newBalanceBuyBack).sub(newBalanceDev).sub(newBalanceMarketing);

        if (newBalanceBuyBack > 0) {
            IERC20(BUSD).transfer(buyBackAddress, newBalanceBuyBack);
        }
        if (newBalanceDev > 0) {
            IERC20(BUSD).transfer(devAddress, newBalanceDev);
        }
        if (newBalanceMarketing > 0) {
            IERC20(BUSD).transfer(marketingAddress, newBalanceMarketing);
        }
        if (newBalanceCharity > 0) {
            IERC20(BUSD).transfer(charityAddress, newBalanceCharity);
        }
    }

    function swapAndSendDividends(uint256 dividends) private {
        uint256 feeTokens = dividends.mul(_totalFees.sub(_reflectionFee)).div(_totalFees);
        swapAndSendToFee(feeTokens);

        dividends = dividends.sub(feeTokens);
        if (dividends < 1) return;
        bool success = IERC20(BUSD).transfer(address(dividendTracker), dividends);

        if (success) {
            try dividendTracker.distributeBUSDDividends(dividends) {
                emit SentDividends(feeTokens, dividends);
            } catch {}
        }
    }

    function burn(address account, uint256 amount) external onlyOwner {
        _burn(account, amount);
    }
}
