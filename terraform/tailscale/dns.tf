resource "tailscale_dns_configuration" "tailnet" {
  magic_dns          = true
  override_local_dns = true

  nameservers {
    address            = "192.168.1.2"
    use_with_exit_node = true
  }

  split_dns {
    domain = "apps.internal"

    nameservers {
      address            = "192.168.1.2"
      use_with_exit_node = true
    }
  }
}
