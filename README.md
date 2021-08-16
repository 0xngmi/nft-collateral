# nft-collateral

## Sweeping tokens
If less than 0.01% of the fractionalized tokens are in the contract, anyone with some coins can take them all.

## Unclear design decisions
- How to pick fractional parameters?
    - Should name and symbol be set by the one who calls rug?
    - Should the listing price equal the debt ceiling?
- Is it ok to call the liquidation function rug()?
- Allow repayment after expiration?
- Should we allow sweeping the remaining <0.01% after a long time has gone? This could prevent issues where some tokens are left and you are forced to 