module rewardverse::RewardVerse {
    use std::signer::address_of;
    use aptos_std::table::{Self,Table};

    use aptos_framework::account::{create_resource_account, create_resource_address, SignerCapability,
        create_signer_with_capability
    };
    use aptos_framework::coin;
    use aptos_framework::managed_coin;
    use aptos_framework::timestamp;

    /// Constants
    const REWARD_VERSE_RESOURCE_ACCOUNT_SEED: vector<u8> = b"REWARD_VERSE_RESOURCE";
    const DEFAULT_MINT: u64 = 10000;

    /// Error codes
    const E_REGISTRY_NOT_INITIALIZED:u64 = 0;
    const E_NOT_DEPLOYER:u64 = 1;
    const E_REGISTRY_ALREADY_EXIST: u64 = 2;
    const E_NOT_MINTED_PROPERLY:u64 = 3;
    const E_USER_NOT_EXIST: u64 = 4;
    const E_USER_ALREADY_EXIST: u64 = 5;
    const E_INSUFFICIENT_BALANCE: u64 = 6;
    const E_REWARD_NOT_EXIST: u64 = 7;
    const E_REWARD_IS_EXPIRED: u64 = 8;


    /// Define coin struct
    struct Coin<phantom CoinType> has store {
        /// Amount of coin this address has.
        value: u64,
    }

    /// Define coin registry
    struct RewardVerseRegistry has key {
        whitelisted_user: Table<address, bool>,
        resource_signer_cap: SignerCapability
    }

    struct Reward has key, store, drop {
        recipient_addr: address,
        amount: u64,
        expired_time: u64,
        is_claimed: bool,
    }

    struct RewardRegistry has key, store {
        counter: u64,
        total_reward_amount: u64,
        rewards: table::Table<u64, Reward>
    }

    /// Create token
    fun init_module<CoinType>(deployer: &signer){
        let multisig_addr= address_of(deployer);

        managed_coin::initialize<CoinType>(
            deployer,
            b"Reward Verse Coin",
            b"RVC",
            9,
            false
        );

        let (res_signer, res_signer_cap) = create_multisig_resource_account(deployer);

        move_to(
            &res_signer,
            RewardVerseRegistry {
                whitelisted_user: table::new(),
                resource_signer_cap: res_signer_cap
            }
        );

        move_to(&res_signer, RewardRegistry{
            counter:0,
            total_reward_amount:0,
            rewards: table::new(),
        });

        register_coin<CoinType>(&res_signer);
    }

    /// Register the custom coin
    public entry fun register_coin<CoinType>(user: &signer){
        managed_coin::register<CoinType>(user);
    }

    public entry fun mint_coin<CoinType>(deployer: &signer, amount: u64) {
        let multisig_addr = address_of(deployer);

        let resource_addr = get_resource_address();
        managed_coin::mint<CoinType>(deployer, resource_addr, amount);
    }

    public entry fun add_user(admin:&signer, recipient_addr: address) acquires RewardVerseRegistry {
        let multisig_addr = address_of(admin);

        let resource_addr = get_resource_address();
        let registry = borrow_global_mut<RewardVerseRegistry>(resource_addr);

        let found = registry.whitelisted_user.contains(recipient_addr);
        assert_user_exist(found);

        registry.whitelisted_user.upsert(recipient_addr, true);
    }

    public entry fun remove_user(admin:&signer, recipient_addr: address) acquires RewardVerseRegistry {
        let multisig_addr = address_of(admin);

        let resource_addr = get_resource_address();

        let registry = borrow_global_mut<RewardVerseRegistry>(resource_addr);
        let found = registry.whitelisted_user.contains(recipient_addr);
        assert_user_not_exist(found);

        registry.whitelisted_user.remove(recipient_addr);
    }

    public entry fun propose_reward<CoinType>(admin: &signer, recipient_addr:address, expired_time: u64, amount: u64) acquires RewardVerseRegistry, RewardRegistry {
        let multisig_addr = address_of(admin);

        let resource_addr = get_resource_address();
        assert_sufficient_balance<CoinType>(resource_addr, amount);

        let registry = borrow_global_mut<RewardVerseRegistry>(resource_addr);
        let found = registry.whitelisted_user.contains(recipient_addr);
        assert_user_not_exist(found);

        assert_reward_registry_not_exists(resource_addr);
        let reward_registry = borrow_global_mut<RewardRegistry>(resource_addr);
        let reward= Reward{
            recipient_addr,
            expired_time,
            amount,
            is_claimed: false,
        };
        let new_counter = reward_registry.counter + 1;

        reward_registry.total_reward_amount += amount;
        reward_registry.counter = new_counter;
        reward_registry.rewards.upsert(new_counter, reward);
    }

    public entry fun claim_reward<CoinType>(recipient: &signer, reward_id: u64) acquires RewardVerseRegistry, RewardRegistry {
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
        assert_sufficient_balance<CoinType>(resource_addr, amount);

        let resource_signer = create_signer_with_capability(&registry.resource_signer_cap);
        coin::transfer<CoinType>(&resource_signer, recipient_addr, amount);

        reward.is_claimed = true;
        reward_registry.total_reward_amount -=amount;
    }

    public entry fun withdraw_unclaimed_coin<CoinType>(admin: &signer) acquires RewardRegistry, RewardVerseRegistry {
        let multisig_addr = address_of(admin);

        let resource_addr = get_resource_address();
        assert_registry_not_exists(resource_addr);
        assert_reward_registry_not_exists(resource_addr);

        let registry = borrow_global_mut<RewardVerseRegistry>(resource_addr);
        let reward_registry = borrow_global_mut<RewardRegistry>(resource_addr);

        let resource_signer = create_signer_with_capability(&registry.resource_signer_cap);

        let total_rewards = reward_registry.counter;
        let i= 0;

        while(i <= total_rewards){
            if(reward_registry.rewards.contains(i)){
                let reward = reward_registry.rewards.borrow_mut(i);
                if (reward.expired_time < timestamp::now_seconds() && !reward.is_claimed) {
                    let amount = reward.amount;
                    coin::transfer<CoinType>(&resource_signer, multisig_addr, amount);
                    reward_registry.total_reward_amount -= amount;
                    reward.amount = 0;
                }
            };

            i += 1;
        }
    }

    // View

    #[view]
    public fun get_balance<CoinType>(addr: address) :u64 {
        coin::balance<CoinType>(addr)
    }

    #[view]
    public fun get_resource_address(): address {
        let addr = create_resource_address(&@rewardverse, REWARD_VERSE_RESOURCE_ACCOUNT_SEED);
        assert_registry_not_exists(addr);
        addr
    }

    // Helpers

    public fun create_multisig_resource_account(multisig: &signer): (signer, SignerCapability) {
        create_resource_account(multisig, REWARD_VERSE_RESOURCE_ACCOUNT_SEED)
    }

    public fun assert_is_deployer(addr: address) {
        assert!(addr == @rewardverse, E_NOT_DEPLOYER);
    }

    public fun assert_sufficient_balance<CoinInfo>(addr: address, amount: u64) {
        assert!(get_balance<CoinInfo>(addr) >= amount, E_INSUFFICIENT_BALANCE);
    }

    public fun assert_registry_not_exists(addr: address)  {
        assert!(exists<RewardVerseRegistry>(addr), E_REGISTRY_NOT_INITIALIZED);
    }

    public fun assert_reward_registry_not_exists(addr: address)  {
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
    struct FakeCoin {}

    #[test_only]
    public fun init_coin_registry<FakeCoin>(framework: &signer, multisig: &signer) {
        create_account_for_test(address_of(multisig));
        coin::create_coin_conversion_map(framework);
        timestamp::set_time_has_started_for_testing(framework);
        let current_time = 10000000; // starting timestamp in microseconds
        timestamp::update_global_time_for_test_secs(current_time);

        managed_coin::initialize<FakeCoin>(
            multisig,
            b"Fake Verse Coin",
            b"FVC",
            9,
            false
        );

        assert!(coin::is_coin_initialized<FakeCoin>(), 0);

        let (res_signer, res_signer_cap) = create_multisig_resource_account(multisig);

        move_to(
            &res_signer,
            RewardVerseRegistry {
                whitelisted_user: table::new(),
                resource_signer_cap: res_signer_cap
            }
        );

        move_to(&res_signer, RewardRegistry{
            counter:0,
            total_reward_amount:0,
            rewards: table::new(),
        });

        register_coin<FakeCoin>(&res_signer);
    }

    #[test(framework = @0x1, multisig= @rewardverse)]
    fun test_registry(framework: &signer, multisig: &signer) {
        init_coin_registry<FakeCoin>(framework, multisig);
    }

    #[test(framework = @0x1, multisig= @rewardverse)]
    fun test_mint_coin(framework: &signer, multisig: &signer) {
        init_coin_registry<FakeCoin>(framework, multisig);
        mint_coin<FakeCoin>(multisig, DEFAULT_MINT);

        assert!(get_balance<FakeCoin>(
            get_resource_address())
            == DEFAULT_MINT , E_NOT_MINTED_PROPERLY);
    }

    #[test(framework = @0x1, multisig= @rewardverse)]
    fun test_add_user(framework: &signer, multisig: &signer) acquires RewardVerseRegistry {
        init_coin_registry<FakeCoin>(framework, multisig);
        mint_coin<FakeCoin>(multisig, DEFAULT_MINT);

        let recipient_addr = @0x41;
        add_user(multisig, recipient_addr);
    }

    #[test(framework = @0x1, multisig= @rewardverse)]
    #[expected_failure(abort_code = E_NOT_DEPLOYER)]
    fun test_add_user_by_non_multisig(framework: &signer, multisig: &signer) acquires RewardVerseRegistry {
        init_coin_registry<FakeCoin>(framework, multisig);
        mint_coin<FakeCoin>(multisig, DEFAULT_MINT);

        let not_multisig = create_account_for_test(@0x40);
        let recipient_addr = @0x41;
        add_user(&not_multisig, recipient_addr);
    }

    #[test(framework = @0x1, multisig= @rewardverse)]
    #[expected_failure(abort_code = E_USER_ALREADY_EXIST)]
    fun test_add_duplicate_user(framework: &signer, multisig: &signer) acquires RewardVerseRegistry {
        init_coin_registry<FakeCoin>(framework, multisig);
        mint_coin<FakeCoin>(multisig, 100);

        let recipient_addr = @0x41;

        add_user(multisig, recipient_addr);
        add_user(multisig, recipient_addr);
    }

    #[test(framework = @0x1, multisig= @rewardverse)]
    fun test_remove_user(framework: &signer, multisig: &signer) acquires RewardVerseRegistry {
        init_coin_registry<FakeCoin>(framework, multisig);
        mint_coin<FakeCoin>(multisig, DEFAULT_MINT);

        let recipient_addr = @0x41;

        add_user(multisig, recipient_addr);
        remove_user(multisig, recipient_addr);
    }

    #[test(framework = @0x1, multisig= @rewardverse)]
    #[expected_failure(abort_code = E_USER_NOT_EXIST)]
    fun test_remove_non_exist_user(framework: &signer, multisig: &signer) acquires RewardVerseRegistry {
        init_coin_registry<FakeCoin>(framework, multisig);
        mint_coin<FakeCoin>(multisig, DEFAULT_MINT);

        let recipient_addr = @0x41;

        remove_user(multisig, recipient_addr);
    }

    #[test(framework = @0x1, multisig= @rewardverse)]
    fun test_propose_reward(framework: &signer, multisig: &signer) acquires RewardVerseRegistry, RewardRegistry {
        init_coin_registry<FakeCoin>(framework, multisig);
        mint_coin<FakeCoin>(multisig, DEFAULT_MINT);

        let recipient_addr = @0x41;

        add_user(multisig, recipient_addr);
        let expired_time = timestamp::now_seconds() + 30*60;
        let reward_amount = DEFAULT_MINT;

        propose_reward<FakeCoin>(multisig, recipient_addr, expired_time, reward_amount);
    }

    #[test(framework = @0x1, multisig= @rewardverse)]
    fun test_claim_reward(framework: &signer, multisig: &signer) acquires RewardVerseRegistry, RewardRegistry {
        init_coin_registry<FakeCoin>(framework, multisig);
        mint_coin<FakeCoin>(multisig, DEFAULT_MINT);

        let recipient_addr = @0x41;
        let recipient = create_account_for_test(recipient_addr);
        register_coin<FakeCoin>(&recipient);

        add_user(multisig, recipient_addr);
        let expired_time = timestamp::now_seconds() + 30*60;
        let reward_amount = 1000;

        propose_reward<FakeCoin>(multisig, recipient_addr, expired_time, reward_amount);
        claim_reward<FakeCoin>(&recipient, 1);
    }

    #[test(framework = @0x1, multisig= @rewardverse)]
    fun test_withdraw_unclaimed_reward(framework: &signer, multisig: &signer) acquires RewardVerseRegistry, RewardRegistry {
        init_coin_registry<FakeCoin>(framework, multisig);
        mint_coin<FakeCoin>(multisig, DEFAULT_MINT);
        register_coin<FakeCoin>(multisig);

        let recipient_addr = @0x41;
        let recipient = create_account_for_test(recipient_addr);
        register_coin<FakeCoin>(&recipient);

        add_user(multisig, recipient_addr);
        let expired_time = timestamp::now_seconds() + 30*60;
        let reward_amount = 1000;

        propose_reward<FakeCoin>(multisig, recipient_addr, expired_time, reward_amount);
        withdraw_unclaimed_coin<FakeCoin>(multisig);
    }
}