{ config, secrets, ... }:
{
  age.secrets = {
    claude-grafana-mcp-token = {
      file = secrets + "/claude-grafana-mcp-token.age";
      owner = "petrtsopa";
    };
  };

  home-manager.users.petrtsopa.claude.grafanaTokenFile =
    config.age.secrets.claude-grafana-mcp-token.path;
}
