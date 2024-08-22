module movewiffrens::frens_point {
  use std::error;
  use std::signer;
  use aptos_framework::managed_coin;
  struct FPoint {}

  const E_NOT_AUTHORIZED: u64 = 1;

  fun init_module(sender: &signer) {
    managed_coin::initialize<FPoint>(
      sender,
      b"Frens Point",
      b"FPoint",
      8,
      true,
    );
  }

  public entry fun mint(
    sender: &signer,
    receiver: address,
    amount: u64,
  ) {
    managed_coin::register<FPoint>(sender);
    managed_coin::mint<FPoint>(sender, receiver, amount);
  }

  public entry fun register(account: &signer) {
    managed_coin::register<FPoint>(account);
  }
}