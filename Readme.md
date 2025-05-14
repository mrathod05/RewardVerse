aptos move build-publish-payload   --named-addresses multisig=0x6533e2d10ea493c62432863cd179ae3373bdc0d39af226632d9bcc83164fca12   --json-output-file publish.

# 🏆 RewardVerse - Aptos Move Smart Contract Testing Guide

This document provides a comprehensive guide for testing the RewardVerse smart contract on the Aptos blockchain using the Command Line Interface (CLI).

## 📋 Prerequisites

- Aptos CLI installed
- At least two accounts configured in your CLI profiles:
  - `rewardverse` - The deployer account
  - `admin` - An administrative account

## 👤 Profile Setup

First, set up your profiles:

```bash
# Create the rewardverse(deployer)
aptos init --network testnet --profile rewardverse

# Create admin profile to approve multisig transaction
aptos init --network testnet --profile admin
```

## 🔧 Environment Setup

Second, set environment variables for important addresses:

```bash
# Set the deployer address
export rewardverse=<deployer_address_here>

# Set the additional admin address
export admin=<admin_address_here>

# If you need to store the multisig address after creation
export multisig_addr=<multisig_address_here>
```

## 📦 Contract Deployment

Deploy the RewardVerse smart contract:

```bash
# Deploy the contract
aptos move publish --profile rewardverse
```

**Note:** Add `--max-gas --gas-unit-price` if terminal asks for it

## 💰 Core Functions Testing

### Minting Coins

Mint the initial supply of coins to the resource account:

```bash
# Mint 10,000 coins
aptos move run --function-id $rewardverse::RewardVerseV1::mint_coin --args u64:10000 --profile rewardverse
```

## 🔐 Multisig Setup

Create a multisig account for shared contract administration:

```bash
# Create a multisig with 2 required signatures
aptos multisig create --additional-owners $admin --num-signatures-required 2 --profile rewardverse --assume-yes
```

### Verify Multisig Configuration

Check that the multisig was correctly configured:

```bash
# View required signatures
aptos move view --function-id 0x1::multisig_account::num_signatures_required --args address:"$multisig_addr" --profile rewardverse

# View owner addresses
aptos move view --function-id 0x1::multisig_account::owners --args address:"$multisig_addr" --profile rewardverse

# Check last resolved sequence number
aptos move view --function-id 0x1::multisig_account::last_resolved_sequence_number --args address:"$multisig_addr" --profile admin

# Check next sequence number
aptos move view --function-id 0x1::multisig_account::next_sequence_number --args address:"$multisig_addr" --profile admin
```

## 📝 Transaction Proposal and Execution

### Creating a Proposal

Create a new transaction proposal for proposing a reward:

```bash
# Create a transaction to propose a reward
aptos multisig create-transaction --multisig-address $multisig_addr --json-file ./payloads/propose_reward.json --profile admin
```

The `propose_reward.json` file might look like:

```json
{
  "function": "$rewardverse::RewardVerseV1::propose_reward",
  "arguments": [
    "0xRecipientAddress",
    "1716249600", 
    "1000"
  ]
}
```

### Checking Pending Transactions

View pending transactions in the multisig:

```bash
# List all pending transactions
aptos move view --function-id 0x1::multisig_account::get_pending_transactions --args address:"$multisig_addr" --profile admin

# Check if a specific transaction can be executed
aptos move view --function-id 0x1::multisig_account::can_be_executed --args address:"$multisig_addr" u64:1 --profile admin
```

### Verifying a Proposal

Verify the content of a proposal before approving:

```bash
# Verify proposal details
aptos multisig verify-proposal --multisig-address $multisig_addr --json-file ./payloads/propose_reward.json --sequence-number 1 --profile admin
```

### Approving a Transaction

Approve a pending transaction:

```bash
# Approve transaction with sequence number 1
aptos multisig approve --multisig-address $multisig_addr --sequence-number 1 --profile admin
```

### Executing a Transaction

Execute a transaction after required approvals:

```bash
# Execute the approved transaction
aptos multisig execute --multisig-address $multisig_addr --profile admin --assume-yes
```

### Verifying a Proposal

Verify the content of a proposal before approving:

```bash
# Verify proposal details
aptos multisig verify-proposal --multisig-address $multisig_addr --json-file ./payloads/propose.json --sequence-number 4 --profile admin
```

### Approving a Transaction

Approve a pending transaction:

```bash
# Approve transaction with sequence number 1
aptos multisig approve --multisig-address $multisig_addr --sequence-number 1 --profile admin
```

### Executing a Transaction

Execute a transaction after required approvals:

```bash
# Execute the approved transaction
aptos multisig execute --multisig-address $multisig_addr --profile admin --assume-yes
```

## Additional Commands

### Viewing Coin Balance

Check the balance of an account:

```bash
# View the balance of a specific address
aptos move view --function-id $rewardverse::RewardVerseV1::get_balance --type-args $rewardverse::MyCoin::MyCoin --args address:"$rewardverse" --profile rewardverse
```

### Adding/Removing Users

Add or remove users from the whitelist:

```bash
# Add a user to the whitelist
aptos move run --function-id $rewardverse::RewardVerseV1::add_user --args address:"0xUserAddress" --profile rewardverse

# Remove a user from the whitelist
aptos move run --function-id $rewardverse::RewardVerseV1::remove_user --args address:"0xUserAddress" --profile rewardverse
```

### Claiming Rewards

As a recipient, claim a reward:

```bash
# Claim reward with ID 1
aptos move run --function-id $rewardverse::RewardVerseV1::claim_reward --type-args $rewardverse::MyCoin::MyCoin --args u64:1 --profile recipient
```

### Withdrawing Unclaimed Coins

Withdraw unclaimed coins after they expire:

```bash
# Withdraw expired unclaimed coins
aptos move run --function-id $rewardverse::RewardVerseV1::withdraw_unclaimed_coin --type-args $rewardverse::MyCoin::MyCoin --profile rewardverse
```

## Troubleshooting

If you encounter errors:

1. Check that all addresses are correct
2. Verify that account profiles have sufficient funds for gas fees
3. Ensure all prerequisites (like user registration) are completed
4. Check sequence numbers for multisig transactions
5. Make sure type arguments match your deployed coin type

## Next Steps

1. Create a frontend UI to interact with your smart contract
2. Implement event logging for better tracking of activities
3. Consider adding additional safety features like pausing functionality
4. Create a proper documentation site for users