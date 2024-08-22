module movewiffrens::minting {
	use std::error;
	use std::signer;
	use std::string::{Self, String};
	use std::vector;
	use std::bcs;
	use aptos_framework::account;
	use aptos_framework::table::{Self, Table};
	use aptos_framework::event::{Self, EventHandle};
	use aptos_token::token::{Self, TokenDataId};
	use aptos_framework::timestamp;

	struct TokenMintingEvent has drop, store {
		token_receiver_address: address,
		token_data_id: TokenDataId,
	}

	struct ModuleData has key {
		counter: u64,
		signer_cap: account::SignerCapability,
		minting_enabled: bool,
		token_minting_events: EventHandle<TokenMintingEvent>,
	}

	struct ListAddress has key {
		white_list_addresses: Table<address, bool>,
		minted_addresses: Table<address, bool>,
	}

	const E_NOT_AUTHORIZED: u64 = 1;
	const E_MINTING_DISABLED: u64 = 2;
	const E_NOT_IN_WHITELIST: u64 = 3;
	const E_MINTED : u64 = 4;

	const COLLECTION_NAME: vector<u8> = b"Movewiffens Testnet Warrior";
	const TOKEN_NAME_PREFIX: vector<u8> = b"Movewiffrens Testnet Warrior";

	fun init_module(resource_account: &signer) {
		let seed_vec = bcs::to_bytes(&timestamp::now_seconds());
		let (_resource, resource_cap) = account::create_resource_account(resource_account, seed_vec);

		let collection = string::utf8(COLLECTION_NAME);
		let description = string::utf8(b"Evidence for the warriors who participated in Movewiffrens' first testnet campaign");
		let collection_uri = string::utf8(b"N/A");
		let maximum_supply = 0;
		let mutate_setting = vector<bool>[ false, false, false ];
		token::create_collection(&_resource, collection, description, collection_uri, maximum_supply, mutate_setting);

		move_to(resource_account, ModuleData {
			counter: 1,
			signer_cap: resource_cap,
			minting_enabled: true,
			token_minting_events: account::new_event_handle<TokenMintingEvent>(&_resource),
		});

		move_to(resource_account, ListAddress {
			white_list_addresses: table::new(),
			minted_addresses: table::new(),
		});
		
	}

	public entry fun set_minting_enabled(caller: &signer, minting_enabled: bool) acquires ModuleData {
		let caller_address = signer::address_of(caller);
		assert!(caller_address == @admin_addr, error::permission_denied(E_NOT_AUTHORIZED));
		let module_data = borrow_global_mut<ModuleData>(@movewiffrens);
		module_data.minting_enabled = minting_enabled;
	}

	public entry fun mint_nft(receiver: &signer) acquires ModuleData, ListAddress {
		let receiver_addr = signer::address_of(receiver);

		let module_data = borrow_global_mut<ModuleData>(@movewiffrens);
		assert!(module_data.minting_enabled, error::permission_denied(E_MINTING_DISABLED));

		let list_address = borrow_global_mut<ListAddress>(@movewiffrens);
		assert!(table::contains(&list_address.white_list_addresses, receiver_addr), error::permission_denied(E_NOT_IN_WHITELIST));
		assert!(!table::contains(&list_address.minted_addresses, receiver_addr), error::permission_denied(E_MINTED));

		let collection = string::utf8(COLLECTION_NAME);
		let token_name = string::utf8(TOKEN_NAME_PREFIX);
		string::append_utf8(&mut token_name, b": ");
		let num = u64_to_string(module_data.counter);
		string::append(&mut token_name, num);

		let resource_signer = account::create_signer_with_capability(&module_data.signer_cap);

		let token_data_id = token::create_tokendata(
			&resource_signer,
			collection,
			token_name,
			string::utf8(b"Evidence for the warriors who participated in Movewiffrens' first testnet campaign"),
			0,
			string::utf8(b"ipfs://bafybeigbisfm24sinmnk3m5y5bnoh3745655ko5pj35cz2zlhiyj6cb7jm"),
			@movewiffrens,
			1,
			0,
			token::create_token_mutability_config(&vector<bool>[ false, true, false, false, true ]),
			vector::empty<String>(),
			vector::empty<vector<u8>>(),
			vector::empty<String>(),
		);

		let token_id = token::mint_token(&resource_signer, token_data_id, 1);
		token::direct_transfer(&resource_signer, receiver, token_id, 1);

		table::add(&mut list_address.minted_addresses, receiver_addr, true);

		event::emit_event<TokenMintingEvent>(
			&mut module_data.token_minting_events,
			TokenMintingEvent {
				token_receiver_address: receiver_addr,
				token_data_id,
			}
		);

		module_data.counter = module_data.counter + 1;
	}

	public entry fun add_to_whitelist(caller: &signer, address: address) acquires ListAddress {
		let caller_address = signer::address_of(caller);
		assert!(caller_address == @admin_addr, error::permission_denied(E_NOT_AUTHORIZED));
		let whitelist = borrow_global_mut<ListAddress>(@movewiffrens);
		table::add(&mut whitelist.white_list_addresses, address, true);
	}

	#[view]
	public fun is_in_whitelist(address: address) : bool acquires ListAddress {
		let list_address = borrow_global_mut<ListAddress>(@movewiffrens);
		table::contains(&list_address.white_list_addresses, address)
	}

	#[view]
	public fun is_minted(address: address) : bool acquires ListAddress {
		let list_address = borrow_global_mut<ListAddress>(@movewiffrens);
		table::contains(&list_address.minted_addresses, address)
	}

	fun u64_to_string(value: u64): string::String {
		if (value == 0) {
			return string::utf8(b"0")
		};
		let buffer = vector::empty<u8>();
		while (value != 0) {
			vector::push_back(&mut buffer, ((48 + value % 10) as u8));
			value = value / 10;
		};
		vector::reverse(&mut buffer);
		string::utf8(buffer)
	}
}