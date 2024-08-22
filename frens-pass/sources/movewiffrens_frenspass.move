module movewiffrens::frens_pass {
    use std::signer;
    use std::error;
    use std::bcs;
    use aptos_framework::event;
    use aptos_framework::table;
    use aptos_framework::coin::{ Self, transfer };
    use aptos_framework::aptos_coin::{AptosCoin };
    use aptos_framework::account;
    use aptos_framework::timestamp;

    struct BaseConfig has key {
      admin_address: address,
      initialized: bool,
      paused: bool,
      protocol_fee_destination: address,
      protocol_fee_percent: u64,
      subject_fee_percent: u64,
      resource_cap: account::SignerCapability
    }

    struct Shares has key {
      shares_balance: table::Table<address, u64>,
      shares_supply: u64,
      holders: table::Table<address, bool>
    }

    #[event]
    struct TradeEvent has drop, store {
      trader: address,
      subject: address,
      is_buy: bool,
      share_amount: u64,
      move_amount: u64,
      protocol_move_amount: u64,
      subject_move_amount: u64,
      supply: u64,
    }

    const RESOURCE_ADDRESS: address = @movewiffrens;

    /// Error
    const E_NOT_OWNER: u64 = 1;
    const E_INSUFFICIENT_PAYMENT: u64 = 2;
    const E_INSUFFICIENT_SHARES: u64 = 3;
    const E_CAN_BUY_ONLY_ONCE_IN_FIRST_TIME: u64 = 4;
    const E_ALREADY_PAUSED: u64 = 5;
    const E_INITIALIZED: u64 = 6;
    const E_OWNER_NOT_UNLOCKING: u64 = 7;
    
    fun init_module(caller: &signer) {
      if (!exists<BaseConfig>(RESOURCE_ADDRESS)) {
        let seed_vec = bcs::to_bytes(&timestamp::now_seconds());
        let (_resource, resource_cap) = account::create_resource_account(caller, seed_vec);
        coin::register<AptosCoin>(&_resource);
        move_to(caller, BaseConfig {
          admin_address: signer::address_of(caller),
          protocol_fee_destination: signer::address_of(caller),
          protocol_fee_percent: 500000,
          subject_fee_percent: 500000,
          initialized: true,
          paused: false,
          resource_cap: resource_cap
        });
      };
    }

    fun assert_owner(caller: &signer) acquires BaseConfig {
      let caller_address = signer::address_of(caller);
      let base_config = borrow_global_mut<BaseConfig>(RESOURCE_ADDRESS);
      assert!(caller_address == base_config.admin_address, error::permission_denied(E_NOT_OWNER));
    }

    fun assert_initialized() acquires BaseConfig {
      let base_config = borrow_global_mut<BaseConfig>(RESOURCE_ADDRESS);
      assert!(base_config.initialized, error::permission_denied(E_INITIALIZED));
    }

    fun assert_pause() acquires BaseConfig {
      let base_config = borrow_global_mut<BaseConfig>(RESOURCE_ADDRESS);
      assert!(!base_config.paused, error::permission_denied(E_ALREADY_PAUSED));
    }

    fun assert_unpause() acquires BaseConfig {
      let base_config = borrow_global_mut<BaseConfig>(RESOURCE_ADDRESS);
      assert!(base_config.paused, error::permission_denied(E_ALREADY_PAUSED));
    }

    public entry fun transfer_owner(caller: &signer, new_owner: address) acquires BaseConfig {
      assert_owner(caller);
      let base_config = borrow_global_mut<BaseConfig>(RESOURCE_ADDRESS);
      base_config.admin_address = new_owner;
    }

    public entry fun set_pause(caller: &signer, paused: bool) acquires BaseConfig {
      assert_owner(caller);
      let base_config = borrow_global_mut<BaseConfig>(RESOURCE_ADDRESS);
      base_config.paused = paused;
    }

    public entry fun set_fee_destination(caller: &signer, destination: address) acquires BaseConfig {
      assert_owner(caller);
      let base_config = borrow_global_mut<BaseConfig>(RESOURCE_ADDRESS);
      base_config.protocol_fee_destination = destination;
    }

    public entry fun set_protocol_fee_percent(caller: &signer, percent: u64) acquires BaseConfig {
      assert_owner(caller);
      let base_config = borrow_global_mut<BaseConfig>(RESOURCE_ADDRESS);
      base_config.protocol_fee_percent = percent;
    }

    public entry fun set_subject_fee_percent(caller: &signer, percent: u64) acquires BaseConfig {
      assert_owner(caller);
      let base_config = borrow_global_mut<BaseConfig>(RESOURCE_ADDRESS);
      base_config.subject_fee_percent = percent;
    }

    fun get_price(supply: u64, amount: u64): u64 {
      let sum1 = if (supply == 0) { 0 } else { (supply - 1) * supply * (2 * (supply - 1) + 1) / 6 };
      let sum2 = if (supply == 0 && amount == 1) { 0 } else { (supply - 1 + amount) * (supply + amount) * (2 * (supply - 1 + amount) + 1) / 6 };
      let summation = sum2 - sum1;
      summation * 10_000_000 / 16000
    }

    #[view]
    public fun get_buy_price(shares_subject: address, amount: u64): u64 acquires Shares {
        let shares = borrow_global_mut<Shares>(shares_subject);
        get_price(shares.shares_supply, amount)
    }

    #[view]
    public fun get_sell_price(shares_subject: address, amount: u64): u64 acquires Shares{
        let shares = borrow_global_mut<Shares>(shares_subject);
        get_price(shares.shares_supply - amount, amount)
    }

    #[view]
    public fun get_buy_price_after_fee(shares_subject: address, amount: u64): u64 acquires Shares, BaseConfig {
        let price = get_buy_price(shares_subject, amount);
        let base_config = borrow_global_mut<BaseConfig>(RESOURCE_ADDRESS);
        let protocol_fee = price * base_config.protocol_fee_percent / 10_000_000;
        let subject_fee = price * base_config.subject_fee_percent / 10_000_000;
        price + protocol_fee + subject_fee
    }

    #[view]
    public fun get_sell_price_after_fee(shares_subject: address, amount: u64): u64 acquires Shares, BaseConfig {
        let price = get_sell_price(shares_subject, amount);
        let base_config = borrow_global_mut<BaseConfig>(RESOURCE_ADDRESS);
        let protocol_fee = price * base_config.protocol_fee_percent / 10_000_000;
        let subject_fee = price * base_config.subject_fee_percent / 10_000_000;
        price - protocol_fee - subject_fee
    }

    public entry fun buy_shares(caller: &signer, shares_subject: address, amount: u64) acquires Shares, BaseConfig {
      assert_pause();
      let caller_address = signer::address_of(caller);
      if (!exists<Shares>(caller_address)) {
        move_to(caller, Shares {
            shares_balance: table::new(),
            shares_supply: 0,
        });
      };

      assert!(exists<Shares>(shares_subject), error::permission_denied(E_OWNER_NOT_UNLOCKING));

      let shares = borrow_global_mut<Shares>(shares_subject);
      let supply = shares.shares_supply;
      if (supply == 0) {
        assert!(amount == 1, error::invalid_argument(E_CAN_BUY_ONLY_ONCE_IN_FIRST_TIME));
      };

      let base_config = borrow_global_mut<BaseConfig>(RESOURCE_ADDRESS);
      let price = get_price(supply, amount);
      let protocol_fee = price * base_config.protocol_fee_percent / 10_000_000;
      let subject_fee = price * base_config.subject_fee_percent / 10_000_000;
      let balance_wallet: u64 = coin::balance<AptosCoin>(caller_address);
      assert!(balance_wallet >= price + protocol_fee + subject_fee, error::invalid_argument(E_INSUFFICIENT_PAYMENT));
      let current_balance = if (table::contains(&shares.shares_balance, caller_address)) {
          *table::borrow(&shares.shares_balance, caller_address)
      } else {
          0
      };
      let new_balance = current_balance + amount;
      table::upsert(&mut shares.shares_balance, caller_address, new_balance);
      shares.shares_supply = supply + amount;

      let signer_resource = account::create_signer_with_capability(&base_config.resource_cap);
      transfer<AptosCoin>(caller, signer::address_of(&signer_resource), price + protocol_fee + subject_fee);
      transfer<AptosCoin>(&signer_resource, base_config.protocol_fee_destination, protocol_fee);
      transfer<AptosCoin>(&signer_resource, shares_subject, subject_fee);

      event::emit(TradeEvent {
        trader: caller_address,
        subject: shares_subject,
        is_buy: true,
        share_amount: amount,
        move_amount: price,
        protocol_move_amount: protocol_fee,
        subject_move_amount: subject_fee,
        supply: shares.shares_supply,
      });
    }

    public entry fun sell_shares(caller: &signer, shares_subject: address, amount: u64) acquires Shares, BaseConfig {
        assert_pause();
        let caller_address = signer::address_of(caller);
        let shares = borrow_global_mut<Shares>(shares_subject);
        let supply = shares.shares_supply;
        assert!(supply > amount, error::invalid_argument(E_INSUFFICIENT_SHARES));
        let base_config = borrow_global_mut<BaseConfig>(RESOURCE_ADDRESS);
        let price = get_price(supply - amount, amount);
        let protocol_fee = price * base_config.protocol_fee_percent / 10_000_000;
        let subject_fee = price * base_config.subject_fee_percent / 10_000_000;
        assert!(*table::borrow(&shares.shares_balance, caller_address) >= amount, error::invalid_argument(E_INSUFFICIENT_SHARES));
        let current_balance = if (table::contains(&shares.shares_balance, caller_address)) {
            *table::borrow(&shares.shares_balance, caller_address)
        } else {
            0
        };
        let new_balance = current_balance - amount;
        table::upsert(&mut shares.shares_balance, caller_address, new_balance);
        shares.shares_supply = supply - amount;

        let signer_resource = account::create_signer_with_capability(&base_config.resource_cap);
        transfer<AptosCoin>(&signer_resource, caller_address, price - protocol_fee - subject_fee);
        transfer<AptosCoin>(&signer_resource, base_config.protocol_fee_destination, protocol_fee);
        transfer<AptosCoin>(&signer_resource, shares_subject, subject_fee);

        event::emit(TradeEvent {
          trader: caller_address,
          subject: shares_subject,
          is_buy: false,
          share_amount: amount,
          move_amount: price,
          protocol_move_amount: protocol_fee,
          subject_move_amount: subject_fee,
          supply: shares.shares_supply,
        });
    }

    #[view]
    public fun get_pause_status(): bool acquires BaseConfig {
        let base_config = borrow_global_mut<BaseConfig>(RESOURCE_ADDRESS);
        base_config.paused
    }

    #[view]
    public fun get_protocol_fee_destination(): address acquires BaseConfig {
        let base_config = borrow_global_mut<BaseConfig>(RESOURCE_ADDRESS);
        base_config.protocol_fee_destination
    }

    #[view]
    public fun get_protocol_fee_percent(): u64 acquires BaseConfig {
        let base_config = borrow_global_mut<BaseConfig>(RESOURCE_ADDRESS);
        base_config.protocol_fee_percent
    }

    #[view]
    public fun get_subject_fee_percent(): u64 acquires BaseConfig {
        let base_config = borrow_global_mut<BaseConfig>(RESOURCE_ADDRESS);
        base_config.subject_fee_percent
    }

    #[view]
    public fun get_shares_balance(shares_subject: address): u64 acquires Shares {
      if (!exists<Shares>(shares_subject)) {
        0
      } else {
        let shares = borrow_global_mut<Shares>(shares_subject);
        shares.shares_supply
      }
    }

    #[view]
    public fun get_shares_balance_of(shares_subject: address, owner: address): u64 acquires Shares {
      if (!exists<Shares>(shares_subject)) {
        0
      } else {
        let shares = borrow_global_mut<Shares>(shares_subject);
        *table::borrow(&shares.shares_balance, owner)
      }
    }

    #[view]
    public fun get_admin_address(): address acquires BaseConfig {
        let base_config = borrow_global_mut<BaseConfig>(RESOURCE_ADDRESS);
        base_config.admin_address
    }
}