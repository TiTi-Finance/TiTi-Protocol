// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import '../libraries/FixedPoint.sol';
import '../interfaces/IMAMMSwapPair.sol';

/**
 * @dev Fixed window oracle that recomputes the average price for the entire period once every period.
 * Note that the price average is only guaranteed to be over at least 1 period, but may be over a longer period.
 */
contract TiTiOracles {
    using FixedPoint for *;

    /// @notice The TWAP's calculation period.
    uint public period = 1 hours;

    /// @notice Sum of cumulative prices denominated in USDC.
    uint public price0CumulativeLast;

    /// @notice Sum of cumulative prices denominated in TiUSD.
    uint public price1CumulativeLast;

    /// @notice Last recorded cumulative prices denominated in USDC.
    uint public priorCumulative;

    /// @notice TiUSD's average price denominated in USDC.
    FixedPoint.uq112x112 public priceAverage;

    /// @notice Last update timestamp.
    uint32 public lastOracleUpdateTime;

    /// @notice Precision conversion to normalize USDC and TiUSD units.
    uint256 private constant BASE_TOKEN_DECIMALS_MULTIPLIER = 1e12;

    function _updatePrice(uint32 blockTimestamp) internal {
        if (lastOracleUpdateTime == 0) {
            lastOracleUpdateTime = blockTimestamp;
        } else {
            uint32 timeElapsed;
            
            unchecked {
                timeElapsed = blockTimestamp - lastOracleUpdateTime; // overflow is desired
            }

            // ensure that at least one full period has passed since the last update
            if (timeElapsed >= period) {
                uint256 currentCumulative = price0CumulativeLast;
            
                unchecked {
                    // overflow is desired, casting never truncates
                    // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
                    priceAverage = FixedPoint.uq112x112(uint224((currentCumulative - priorCumulative) / timeElapsed));
                }

                priorCumulative = currentCumulative;
                lastOracleUpdateTime = blockTimestamp;
            }            
        }
    }

    function _resetPrice() internal {
        // reset twap to $1
        priceAverage = FixedPoint.uq112x112(uint224(2**112) / uint224(1e12));
    }

    /// @notice Get TiUSD's average price denominated in USDC.
    /// @return tiusdPriceMantissa TiUSD price with 18-bit precision.
    /// @return isValid Whether the return TiUSD price is valid.
    function _getTiUSDPrice() internal view returns (uint256 tiusdPriceMantissa, bool isValid) {
        tiusdPriceMantissa = priceAverage.decode112with18() * BASE_TOKEN_DECIMALS_MULTIPLIER;
        isValid = tiusdPriceMantissa > 0;
    }
}
