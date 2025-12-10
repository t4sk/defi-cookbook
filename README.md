# DeFi cookbook

- [CSAMM](https://sepolia.etherscan.io/address/0x3911aaa51e43abddf0f25f8ebe7e12dab8945764)
- CPAMM
- CLAMM
- Stable coin
- price oracle
- lending
- auctions

### Forge wallet setup
```shell
# Account setup
PK=...
ACCOUNT=dev
cast wallet import --private-key $PK $ACCOUNT
```

### Forge script

```shell
FORK_URL=...
ETHERSCAN_API_KEY=...
SENDER=...

forge script script/csamm.s.sol:CSAMMScript \
--rpc-url $FORK_URL \
-vvv \
--keystore ~/.foundry/keystores/my_keystore.json \
--sender $SENDER \
--broadcast \
--verify \
--etherscan-api-key $ETHERSCAN_API_KEY
```
