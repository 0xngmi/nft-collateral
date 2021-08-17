# NFT Collateral

## Concept
Lending protocol for NFTs with fixed expiry and fixed interest that places credit risk evaluation on the lender.

## Mechanism
1. NFT owner locks their NFT and sets an expiry date, a debt ceiling and an interest to be paid to lenders
2. Lenders evaluate the offer and, if convinced, lend money to owner
3. Owner can repay lent money + interest at any time to get back their NFT
4. If owner hasn't repaid credit by expiry, the NFT is fractionalized using fractional.art and distributed among all the lenders. If the debt ceiling has not been reached, the owner will receive the missing portion in fractionalized tokens.

## Lending pools
These are a set of pools that act as guaranteed lenders as long as certain conditions are met, for example the PUNK pool will always lend money with cryptopunk offers as long as duration is lower than a week, interest is higher than 5% and debt ceiling is lower than 10k USD.

The parameters for these pools will need to be continuosly kept up to date, it's unclear what the process will be for this, but initially these will be managed by a multisig along with someone that can create a risk model for it.

If any loan defaults, the NFT will be auctioned through fractional.art. If the proceeds exceed the lent amount, the extra money will be sent to the treasury, which will store these as an insurance fund againt bad debt.

All the pools will be isolated, but there will also be an omnipool that will feed into all of these smaller ones, thus taking all the risk.

## Sweeping tokens
In order to be able to unwrap the NFT on fractional.art, the unwrapper needs to have all the ERC20 tokens for it. However, there are small precision errors on the calculations in our contract (these errors are <0.00000000000000001%), so it's likely that some tokens might end up getting stuck in the contract, thus making it impossible to do a full redemption. This is a problem, since it will mean that redeeming the NFT will be impossible and owners will be forced to do a public auction.

To solve this we've introduced a new mechanism that makes it possible for anyone who already owns some shares to get the remaining shares in the contract if there's less than 0.01% left there. The downside of this is that it makes it possible to steal the share of some really small players that are late to withdraw, however the amount is so small that this is very unlikely to happen on Ethereum mainnet due to gas costs.

For example let's assume that an NFT is valued at 300ETH and the owner sets the debt ceiling at 100ETH, for this mechanism to enable stealing it must mean that someone has lent 0.01ETH, which would be lower than the gas cost required to interact with the contract, therefore not economically rational.

## Comparison against "bids as collateral" idea
The only other protocol idea I've seen for NFT lending has been the one from Mark Beylin and Anish Agnihotri https://mobile.twitter.com/MarkBeylin/status/1416959609143808003. That protocol is based around the concept of an auction with locked top bids, which are loaned as credit to the NFT owner.

The main difference against that protocol is that this one is centered around collectivization and the debt ceiling is set by the owner instead of the market.

This has the effect of favoring the NFT owner over the lenders, as, if an owner can't repay or forgets to, the other protocol just makes you lose the NFT at the price of the highest bid, whereas in my protocol the debt ceiling set by the owner is enforced.

Both protocols allow for partial fills, but the nature of these are different. In this protocol partial fills are users lending you money at your valuation but only part of the money you requested. On the other protocol partial fills are users lending you money at their valuation.

Another benefit is that this protocol is much less gas and attention intensive once you have lent money, since there are no auctions happening.

Some downsides are that this protocol requires a much more precise valuation of an NFT, as otherwise you might get a loan that's too small or not get any fills. Furthermore, the lender is not guaranteed to receive the full NFT.

In summary, the protocol optimizes for the small guy (removes costly auctions that require multiple txs, amounts lent don't need to cover the whole loan and contract has heavy gas optimizations) and gives higher guarantees to lenders, at the cost of the downsides mentioned before.

## Future improvements
One of the main problems of this protocol is that it requires a lot of work on the lender's side, they can't just park their funds the way you would on compound, instead they need to evaluate each deal and make a decision on it.

I think eventually we'll see better protocols that solve this but until then a good solution is curation. People knowledgeable on NFTs could curate the offers and mark those that are likely to not default. In any case, curation is needed to prevent counterfeits from opensea/rarible's collections.

Another solution involves the usage of interest curves. When the amount lent is low the interest would be higher, which provides an incentive for people to search for good offers early. Afterwards other people can use this as a signal to lend more money.

## Unclear design decisions
- How to pick fractional.art parameters?
    - Should name and symbol be set by the one who calls rug()?
    - Should the listing price equal the debt ceiling?
- Is it ok to call the liquidation function rug()?
- Should we allow repayment after expiration?
- Should we use a curve for interest rates instead of fixed interest?
- Should we allow partial repays and lowering of the debt ceiling?
- Should the owner be allowed to increase interest rates?