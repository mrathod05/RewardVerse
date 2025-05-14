module multisig::RewardVerseV1 {
    use std::signer::address_of;
    use aptos_std::table::{Self, Table};

    use aptos_framework::account::{
        create_resource_account,
        create_resource_address,
        SignerCapability,
        create_signer_with_capability
    };
    use aptos_framework::coin;
    use aptos_framework::managed_coin;
    use aptos_framework::timestamp;

    /// Constants
    const REWARD_VERSE_RESOURCE_ACCOUNT_SEED: vector<u8> = b"REWARD_VERSE_RESOURCE";
    const DEFAULT_MINT: u64 = 10000;

    // Error codes

    /// Registry is not initialized
    const E_REGISTRY_NOT_INITIALIZED: u64 = 0;
    /// Signer is not multisig
    const E_NOT_MULTISG: u64 = 1;
    /// Registry is already initialized
    const E_REGISTRY_ALREADY_EXIST: u64 = 2;
    /// Failed to mint coins
    const E_NOT_MINTED_PROPERLY: u64 = 3;
    /// User is not exists
    const E_USER_NOT_EXIST: u64 = 4;
    /// User is already exists
    const E_USER_ALREADY_EXIST: u64 = 5;
    /// Insufficient coin balance
    const E_INSUFFICIENT_BALANCE: u64 = 6;
    /// Requested reward is not exist
    const E_REWARD_NOT_EXIST: u64 = 7;
    /// Requested reward is expired
    const E_REWARD_IS_EXPIRED: u64 = 8;
    /// Unauthorized to perform action
    const E_UNAUTHORIZED: u64 = 9;

    /// Define coin struct
    struct RVC has store {}

    /// Define coin registry
    struct RewardVerseRegistry has key {
        whitelisted_user: Table<address, bool>,
        resource_signer_cap: SignerCapability
    }

    /// Define reward struct
    struct Reward has key, store, drop {
        recipient_addr: address,
        amount: u64,
        expired_time: u64,
        is_claimed: bool
    }

    /// Define reward registry struct
    struct RewardRegistry has key, store {
        counter: u64,
        total_reward_amount: u64,
        rewards: table::Table<u64, Reward>
    }

    /// Create token
    fun init_module(multisig: &signer) {
        let multisig_addr = address_of(multisig);
        assert_is_multisig(multisig_addr);

        managed_coin::initialize<RVC>(multisig, b"Reward Verse Coin", b"RVC", 9, false);

        let (res_signer, res_signer_cap) = create_multisig_resource_account(multisig);

        move_to(
            &res_signer,
            RewardVerseRegistry {
                whitelisted_user: table::new(),
                resource_signer_cap: res_signer_cap
            }
        );

        move_to(
            &res_signer,
            RewardRegistry { counter: 0, total_reward_amount: 0, rewards: table::new() }
        );

        register_coin(&res_signer);
    }

    /// Register user with coin
    public entry fun register_coin(user: &signer) {
        managed_coin::register<RVC>(user);
    }

    /// Mint the coin by multisig
    public entry fun mint_coin(multisig: &signer, amount: u64) {
        let multisig_addr = address_of(multisig);
        assert_is_multisig(multisig_addr);

        let resource_addr = get_resource_address();
        managed_coin::mint<RVC>(multisig, resource_addr, amount);
    }

    /// Add the whitelisted user for reward
    public entry fun add_user(multisig: &signer, recipient_addr: address) acquires RewardVerseRegistry {
        let multisig_addr = address_of(multisig);
        assert_is_unauthorized(multisig_addr);

        let resource_addr = get_resource_address();
        let registry = borrow_global_mut<RewardVerseRegistry>(resource_addr);

        let found = registry.whitelisted_user.contains(recipient_addr);
        assert_user_exist(found);

        registry.whitelisted_user.upsert(recipient_addr, true);
    }

    /// Remove user from the whitelisted users list
    public entry fun remove_user(multisig: &signer, recipient_addr: address) acquires RewardVerseRegistry {
        let multisig_addr = address_of(multisig);
        assert_is_unauthorized(multisig_addr);

        let resource_addr = get_resource_address();

        let registry = borrow_global_mut<RewardVerseRegistry>(resource_addr);
        let found = registry.whitelisted_user.contains(recipient_addr);
        assert_user_not_exist(found);

        registry.whitelisted_user.remove(recipient_addr);
    }

    /// Propose the reward with multisig
    public entry fun propose_reward(
        multisig: &signer,
        recipient_addr: address,
        expired_time: u64,
        amount: u64
    ) acquires RewardVerseRegistry, RewardRegistry {
        let multisig_addr = address_of(multisig);
        assert_is_unauthorized(multisig_addr);

        let resource_addr = get_resource_address();
        assert_sufficient_balance(resource_addr, amount);

        let registry = borrow_global_mut<RewardVerseRegistry>(resource_addr);
        let found = registry.whitelisted_user.contains(recipient_addr);
        assert_user_not_exist(found);

        assert_reward_registry_not_exists(resource_addr);
        let reward_registry = borrow_global_mut<RewardRegistry>(resource_addr);
        let reward = Reward { recipient_addr, expired_time, amount, is_claimed: false };
        let new_counter = reward_registry.counter + 1;

        reward_registry.total_reward_amount += amount;
        reward_registry.counter = new_counter;
        reward_registry.rewards.upsert(new_counter, reward);
    }

    /// Claim the reward by user
    public entry fun claim_reward(
        recipient: &signer, reward_id: u64
    ) acquires RewardVerseRegistry, RewardRegistry {
        let recipient_addr = address_of(recipient);
        let resource_addr = get_resource_address();

        let registry = borrow_global_mut<RewardVerseRegistry>(resource_addr);
        let found = registry.whitelisted_user.contains(recipient_addr);
        assert_user_not_exist(found);

        assert_reward_registry_not_exists(resource_addr);
        let reward_registry = borrow_global_mut<RewardRegistry>(resource_addr);
        let found = reward_registry.rewards.contains(reward_id);
        assert_reward_not_exist(found);

        let reward = reward_registry.rewards.borrow_mut(reward_id);
        assert_reward_not_exist(reward.recipient_addr == recipient_addr);
        assert_expired_reward(reward.expired_time);

        let amount = reward.amount;
        assert_sufficient_balance(resource_addr, amount);

        let resource_signer =
            create_signer_with_capability(&registry.resource_signer_cap);
        coin::transfer<RVC>(&resource_signer, recipient_addr, amount);

        reward.is_claimed = true;
        reward_registry.total_reward_amount -= amount;
    }

    /// Withdraw unclaimed or expired coin by deployer only
    public entry fun withdraw_unclaimed_coin(
        deployer: &signer
    ) acquires RewardRegistry, RewardVerseRegistry {
        let deployer_addr = address_of(deployer);
        assert_is_multisig(deployer_addr);

        let resource_addr = get_resource_address();
        assert_registry_not_exists(resource_addr);
        assert_reward_registry_not_exists(resource_addr);

        let registry = borrow_global_mut<RewardVerseRegistry>(resource_addr);
        let reward_registry = borrow_global_mut<RewardRegistry>(resource_addr);

        let resource_signer =
            create_signer_with_capability(&registry.resource_signer_cap);

        let total_rewards = reward_registry.counter;
        let i = 0;

        while (i <= total_rewards) {
            if (reward_registry.rewards.contains(i)) {
                let reward = reward_registry.rewards.borrow_mut(i);
                if (reward.expired_time < timestamp::now_seconds()
                    && !reward.is_claimed) {
                    let amount = reward.amount;
                    coin::transfer<RVC>(&resource_signer, deployer_addr, amount);
                    reward_registry.total_reward_amount -= amount;
                    reward.amount = 0;
                }
            };

            i += 1;
        }
    }

    // View

    #[view]
    public fun get_balance(addr: address): u64 {
        coin::balance<RVC>(addr)
    }

    #[view]
    public fun get_resource_address(): address {
        let addr =
            create_resource_address(&@multisig, REWARD_VERSE_RESOURCE_ACCOUNT_SEED);
        assert_registry_not_exists(addr);
        addr
    }

    // Helpers

    public fun create_multisig_resource_account(multisig: &signer): (signer, SignerCapability) {
        create_resource_account(multisig, REWARD_VERSE_RESOURCE_ACCOUNT_SEED)
    }

    public fun assert_is_multisig(addr: address) {
        assert!(addr == @multisig, E_NOT_MULTISG);
    }

    public fun assert_is_unauthorized(addr: address) {
        assert!(
            addr == @multisig || addr == @multisig,
            E_UNAUTHORIZED
        );
    }

    public fun assert_sufficient_balance(addr: address, amount: u64) {
        assert!(get_balance(addr) >= amount, E_INSUFFICIENT_BALANCE);
    }

    public fun assert_registry_not_exists(addr: address) {
        assert!(exists<RewardVerseRegistry>(addr), E_REGISTRY_NOT_INITIALIZED);
    }

    public fun assert_reward_registry_not_exists(addr: address) {
        assert!(exists<RewardRegistry>(addr), E_REGISTRY_NOT_INITIALIZED);
    }

    public fun assert_user_exist(found: bool) {
        assert!(!found, E_USER_ALREADY_EXIST);
    }

    public fun assert_user_not_exist(found: bool) {
        assert!(found, E_USER_NOT_EXIST);
    }

    public fun assert_reward_not_exist(found: bool) {
        assert!(found, E_REWARD_NOT_EXIST);
    }

    public fun assert_expired_reward(exp_time: u64) {
        assert!(exp_time >= timestamp::now_seconds(), E_REWARD_IS_EXPIRED);
    }

    // Unit Tests
    #[test_only]
    use aptos_framework::account::create_account_for_test;

    #[test_only]
    public fun init_coin_registry(framework: &signer, multisig: &signer) {
        create_account_for_test(address_of(multisig));
        coin::create_coin_conversion_map(framework);
        timestamp::set_time_has_started_for_testing(framework);
        let current_time = 10000000; // starting timestamp in microseconds
        timestamp::update_global_time_for_test_secs(current_time);

        init_module(multisig);
    }

    #[test(framework = @0x1, multisig = @multisig)]
    fun test_registry(framework: &signer, multisig: &signer) {
        init_coin_registry(framework, multisig);
    }

    #[test(framework = @0x1, multisig = @multisig)]
    fun test_mint_coin(framework: &signer, multisig: &signer) {
        init_coin_registry(framework, multisig);
        mint_coin(multisig, DEFAULT_MINT);

        assert!(
            get_balance(get_resource_address()) == DEFAULT_MINT, E_NOT_MINTED_PROPERLY
        );
    }

    #[test(framework = @0x1, multisig = @multisig)]
    fun test_add_user(framework: &signer, multisig: &signer) acquires RewardVerseRegistry {
        init_coin_registry(framework, multisig);
        mint_coin(multisig, DEFAULT_MINT);

        let recipient_addr = @0x41;
        add_user(multisig, recipient_addr);
    }

    #[test(framework = @0x1, multisig = @multisig)]
    #[expected_failure(abort_code = E_UNAUTHORIZED)]
    fun test_add_user_by_non_multisig(
        framework: &signer, multisig: &signer
    ) acquires RewardVerseRegistry {
        init_coin_registry(framework, multisig);
        mint_coin(multisig, DEFAULT_MINT);

        let not_multisig = create_account_for_test(@0x40);
        let recipient_addr = @0x41;
        add_user(&not_multisig, recipient_addr);
    }

    #[test(framework = @0x1, multisig = @multisig)]
    #[expected_failure(abort_code = E_USER_ALREADY_EXIST)]
    fun test_add_duplicate_user(framework: &signer, multisig: &signer) acquires RewardVerseRegistry {
        init_coin_registry(framework, multisig);
        mint_coin(multisig, 100);

        let recipient_addr = @0x41;

        add_user(multisig, recipient_addr);
        add_user(multisig, recipient_addr);
    }

    #[test(framework = @0x1, multisig = @multisig)]
    fun test_remove_user(framework: &signer, multisig: &signer) acquires RewardVerseRegistry {
        init_coin_registry(framework, multisig);
        mint_coin(multisig, DEFAULT_MINT);

        let recipient_addr = @0x41;

        add_user(multisig, recipient_addr);
        remove_user(multisig, recipient_addr);
    }

    #[test(framework = @0x1, multisig = @multisig)]
    #[expected_failure(abort_code = E_USER_NOT_EXIST)]
    fun test_remove_non_exist_user(
        framework: &signer, multisig: &signer
    ) acquires RewardVerseRegistry {
        init_coin_registry(framework, multisig);
        mint_coin(multisig, DEFAULT_MINT);

        let recipient_addr = @0x41;

        remove_user(multisig, recipient_addr);
    }

    #[test(framework = @0x1, multisig = @multisig)]
    fun test_propose_reward(
        framework: &signer, multisig: &signer
    ) acquires RewardVerseRegistry, RewardRegistry {
        init_coin_registry(framework, multisig);
        mint_coin(multisig, DEFAULT_MINT);

        let recipient_addr = @0x41;

        add_user(multisig, recipient_addr);
        let expired_time = timestamp::now_seconds() + 30 * 60;
        let reward_amount = DEFAULT_MINT;

        propose_reward(
            multisig,
            recipient_addr,
            expired_time,
            reward_amount
        );
    }

    #[test(framework = @0x1, multisig = @multisig)]
    fun test_claim_reward(
        framework: &signer, multisig: &signer
    ) acquires RewardVerseRegistry, RewardRegistry {
        init_coin_registry(framework, multisig);
        mint_coin(multisig, DEFAULT_MINT);

        let recipient_addr = @0x41;
        let recipient = create_account_for_test(recipient_addr);
        register_coin(&recipient);

        add_user(multisig, recipient_addr);
        let expired_time = timestamp::now_seconds() + 30 * 60;
        let reward_amount = 1000;

        propose_reward(
            multisig,
            recipient_addr,
            expired_time,
            reward_amount
        );
        claim_reward(&recipient, 1);
    }

    #[test(framework = @0x1, multisig = @multisig)]
    fun test_withdraw_unclaimed_reward(
        framework: &signer, multisig: &signer
    ) acquires RewardVerseRegistry, RewardRegistry {
        init_coin_registry(framework, multisig);
        mint_coin(multisig, DEFAULT_MINT);
        register_coin(multisig);

        let recipient_addr = @0x41;
        let recipient = create_account_for_test(recipient_addr);
        register_coin(&recipient);

        add_user(multisig, recipient_addr);
        let expired_time = timestamp::now_seconds() + 30 * 60;
        let reward_amount = 1000;

        propose_reward(
            multisig,
            recipient_addr,
            expired_time,
            reward_amount
        );
        withdraw_unclaimed_coin(multisig);
    }
}
