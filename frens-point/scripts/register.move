script {
  fun register(account: &signer) {
    aptos_framework::managed_coin::register<movewiffrens::frens_point::FPoint>(account)
  }
}