let
  admin = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJYb7/Z36wmmKSdZ9RCvMtyb2LB5RATwNJFwftJ56VFz personal-macbook-2026-08";
  potato_server = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB7QqJdfyLezSONjaWNB8meN9U2mmDeR/HZuvWsjAT10";
  home_server = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFu0hmSgRB/X46yemDNfwldqQKWU1fkorCI94qokIpUW";

  publicKeys = [
    admin
    potato_server
    home_server
  ];

  files = [
    "restic-key.age"
    "rclone-config.age"
    "vaultwarden-admin-token.age"
    "tgauth-key.age"
    "tgauth-env.age"
    "nextcloud-admin-password.age"
    "cleanup-script.age"
    "htpasswd-admin.age"
    "grafana-secret-key.age"
    "airvpn-wg.age"
    "backblaze-b2-autorestic-env.age"
    "tailscale-authkey.age"
    "tailscale-browser-authkey.age"
    "cloudflare-dns-token.age"
    "telegram-bot-token.age"
    "claude-grafana-mcp-token.age"
  ];
in
builtins.listToAttrs (
  map (name: {
    inherit name;
    value.publicKeys = publicKeys;
  }) files
)
