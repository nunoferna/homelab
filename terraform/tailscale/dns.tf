resource "tailscale_dns_nameservers" "global_dns" {
  nameservers = [
    "192.168.1.2", # Pi-hole DNS LoadBalancer
  ]
}

resource "tailscale_dns_preferences" "params" {
  magic_dns = true
}

resource "tailscale_dns_split_nameservers" "home_lab" {
  domain      = "apps.internal"
  nameservers = ["192.168.1.2"]
}
