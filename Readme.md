# 🏆 RewardVerse - Interactive Testing Guide

This interactive guide walks you through testing the RewardVerse smart contract on the Aptos blockchain using the Command Line Interface (CLI).

> 👉 **TIP:** Copy and paste the commands directly from this guide to ensure accuracy.

## 📋 Before You Begin

You'll need:
- [Aptos CLI](https://aptos.dev/cli-tools/aptos-cli-tool/install-aptos-cli/) installed
- Testnet APT tokens ([Get from faucet](https://aptoslabs.com/testnet-faucet))
- Two admin accounts for multisig management

## 👤 Setting Up Your Profiles

Let's create the necessary account profiles:

```bash
# Create your first admin profile (primary multisig creator)
aptos init --network testnet --profile admin

# Create second admin profile (for approving transactions)
aptos init --network testnet --profile admin2
```

✅ **SUCCESS INDICATOR:** You should see address and public key confirmation for each profile.

## 🔧 Setting Your Environment Variables

Store your addresses for easy access:

```bash
# Set the admin address (copy from your profile output)
export admin=<admin_address_here>

# Set the additional admin address
export admin2=<admin2_address_here>
```

## 🔐 Creating Your Multisig Account

A multisig account provides shared control over your contract:

```bash
# Create a multisig with 2 required signatures
aptos multisig create --additional-owners $admin2 --num-signatures-required 2 --profile admin --assume-yes
```

You'll receive a response like this:

```json
{
  "Result": {
    "multisig_address": "0xf6bb03e4fbb2dc1ce47454f24bf696e8ad4e4279df6bc2e3aeda947e54822522",
    "transaction_hash": "0xb6ce6ad4405fdaeca4a6cdc33150c8dc7ac08b49287f3a63e6af95682a3bd664",
    "success": true,
    "vm_status": "Executed successfully"
  }
}
```

🔍 **ACTION REQUIRED:** Save your multisig address to an environment variable:
```bash
export multisig_addr=0xf6bb03e4fbb2dc1ce47454f24bf696e8ad4e4279df6bc2e3aeda947e54822522  # Replace with YOUR multisig address
```

## 📦 Deploying Your Contract

Now let's deploy the RewardVerse contract to your multisig address:

### Step 1: Generate the deployment payload
```bash
# Create the deployment package
aptos move build-publish-payload --named-addresses multisig=$multisig_addr --json-output-file publish.json
```

### Step 2: Propose the deployment as a multisig transaction
```bash
# Create the deployment transaction
aptos multisig create-transaction --multisig-address $multisig_addr --json-file ./publish.json --profile admin
```

> ⚠️ **NOTE:** If prompted, add `--max-gas <amount> --gas-unit-price <price>` parameters.

### Step 3: Check your pending transaction
```bash
# List all pending transactions
aptos move view --function-id 0x1::multisig_account::get_pending_transactions --args address:"$multisig_addr" --profile admin
```

### Step 4: Verify the proposal contents (optional but recommended)
```bash
# Verify sequence number 1 (your first transaction)
aptos multisig verify-proposal --multisig-address $multisig_addr --json-file ./publish.json --sequence-number 1 --profile admin
```

### Step 5: Get the second admin's approval
```bash
# Second admin approves the transaction
aptos multisig approve --multisig-address $multisig_addr --sequence-number 1 --profile admin2
```

### Step 6: Execute the approved transaction
```bash
# Execute after required approvals
aptos multisig execute --multisig-address $multisig_addr --sequence-number 1 --profile admin --assume-yes
```

🎉 **SUCCESS!** Your contract is now deployed on the multisig address. The `init_module` function has automatically been called.

### Step 7: Verify your multisig is configured correctly
```bash
# Check required signatures (should be 2)
aptos move view --function-id 0x1::multisig_account::num_signatures_required --args address:"$multisig_addr" --profile admin

# Check owner addresses (should include both admins)
aptos move view --function-id 0x1::multisig_account::owners --args address:"$multisig_addr" --profile admin
```

## 📝 Using Core RewardVerse Functions

Let's set up JSON payloads for each function to make multisig operations easier:

### Step 1: Create a directory for your payloads
```bash
mkdir -p ./payloads
```

### Step 2: Generate function payloads
```bash
# Create mint_coin.json
cat > ./payloads/mint_coin.json << EOL
{
  "function_id": "$multisig::RewardVerseV1::mint_coin",
  "type_args": [],
  "args": [
    { "type": "u64", "value": 10000 }
  ]
}
EOL

# Create add_user.json (replace with your user address)
cat > ./payloads/add_user.json << EOL
{
  "function_id": "$multisig::RewardVerseV1::add_user",
  "type_args": [],
  "args": [
    { "type": "address", "value": "0x82bb6290772ce549f0f250b2893c677baa0d1e93cd6706b6f90b55aa843c713f" }
  ]
}
EOL

# Create propose_reward.json (replace with recipient address)
cat > ./payloads/propose_reward.json << EOL
{
  "function_id": "$multisig::RewardVerseV1::propose_reward",
  "type_args": [],
  "args": [
    { "type": "address", "value": "0x82bb6290772ce549f0f250b2893c677baa0d1e93cd6706b6f90b55aa843c713f" },
    { "type": "u64", "value": 1747144781 },
    { "type": "u64", "value": 1000 }
  ]
}
EOL

# Create withdraw_unclaimed_coin.json
cat > ./payloads/withdraw_unclaimed_coin.json << EOL
{
  "function_id": "$multisig::RewardVerseV1::withdraw_unclaimed_coin",
  "type_args": [],
  "args": []
}
EOL

# Create remove_user.json (replace with user address)
cat > ./payloads/remove_user.json << EOL
{
  "function_id": "$multisig::RewardVerseV1::remove_user",
  "type_args": [],
  "args": [
    { "type": "address", "value": "0x36891e4a7f49c21b1fa4644112c1cdadf6a88c490e4b6d847d85bf6a24af3be2" }
  ]
}
EOL
```

### Step 3: Execute a function (example: mint coins)

1. **Create the transaction proposal**:
```bash
aptos multisig create-transaction --multisig-address $multisig_addr --json-file ./payloads/mint_coin.json --profile admin
```

2. **Approve with second admin**:
```bash
aptos multisig approve --multisig-address $multisig_addr --sequence-number 2 --profile admin2
```

3. **Execute the transaction**:
```bash
aptos multisig execute --multisig-address $multisig_addr --sequence-number 2 --profile admin --assume-yes
```

> 💡 **TIP:** Follow the same process for other functions by changing the payload file!

## 🔎 Checking Balances and Rewards

### Viewing Coin Balance

Check how many tokens are in an account:

```bash
# View your multisig account balance
aptos move view --function-id $multisig_addr::RewardVerseV1::get_balance --args address:"$multisig_addr" --profile admin
```

### For Users: Claiming Rewards

If you're a user who has been awarded tokens:

```bash
# First, register a recipient profile (if needed)
aptos init --network testnet --profile recipient

# Then claim your reward (replace 1 with your reward ID)
aptos move run --function-id $multisig_addr::RewardVerseV1::claim_reward --args u64:1 --profile recipient
```

## 🧪 Testing Sequence Quick Guide

For testing the complete workflow, follow this sequence:

1. **Admin Setup**
   - ✅ Create admin profiles
   - ✅ Set environment variables
   - ✅ Create multisig account

2. **Contract Deployment**
   - ✅ Generate deployment payload
   - ✅ Propose deployment transaction
   - ✅ Second admin approves
   - ✅ Execute deployment

3. **Core Operations**
   - ✅ Mint coins
   - ✅ Add users to whitelist
   - ✅ Propose rewards
   - ✅ Users claim rewards
   - ✅ Withdraw unclaimed coins (after expiry)
   - ✅ Remove users from whitelist

## 🛠️ Troubleshooting Common Issues

| Problem | Solution |
|---------|----------|
| **Transaction failed** | Check explorer: `https://explorer.aptoslabs.com/txn/<HASH>?network=testnet` |
| **Insufficient gas** | Add `--max-gas 20000 --gas-unit-price 100` to your command |
| **Invalid sequence number** | Run `aptos move view --function-id 0x1::multisig_account::next_sequence_number --args address:"$multisig_addr" --profile admin` to check the correct number |
| **Approval failures** | Verify both admins are in the multisig owners list |

> 🔍 **DEBUGGING TIP**: Add `--verbose` to any command to see detailed error messages.

## 🚀 Next Development Steps

- [ ] **Build a UI**: Create a web interface for non-technical users
- [ ] **Add Monitoring**: Set up alerts for contract activities
- [ ] **Implement Event Tracking**: Add event logging for better transparency
- [ ] **Security Audit**: Have the contract audited before mainnet deployment

*This guide is continuously updated. Last revised: May 15, 2025*
