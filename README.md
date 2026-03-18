# DeFi cookbook

- [CSAMM](https://sepolia.etherscan.io/address/0x3911aaa51e43abddf0f25f8ebe7e12dab8945764)
- CPAMM
- CLAMM
- Stable coin
- price oracle
- lending
- auctions

```shell
# install
forge install a16z/halmos-cheatcodes
```

### Forge wallet setup

```shell
# Account setup
PK=...
ACCOUNT=dev
cast wallet import --private-key $PK $ACCOUNT
cast wallet list
cast wallet address --account $ACCOUNT
```

### Forge script

```shell
FORK_URL=
ETHERSCAN_API_KEY=
SENDER=
ACCOUNT=

forge script script/csamm.s.sol:CSAMMScript \
--rpc-url $FORK_URL \
-vvv \
--account $ACCOUNT \
--sender $SENDER \
--broadcast \
--verify \
--etherscan-api-key $ETHERSCAN_API_KEY
```
