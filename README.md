# DeFi cookbook

- [Insurance](./src/insurance)
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
# Script
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

# Verify
CONTRACT_ADDR=
CONTRACT_PATH=
CONTRACT_NAME=
CONSTRUCTOR_ARGS=$(cast abi-encode "constructor(address,uint256)" 0xABC... 100)
CHAIN=

forge verify-contract \
  $CONTRACT_ADDR \
  $CONTRACT_PATH:$CONTRACT_NAME \
  --constructor-args $CONSTRUCTOR_ARGS \
  --chain $CHAIN \
  --etherscan-api-key $ETHERSCAN_API_KEY
```
