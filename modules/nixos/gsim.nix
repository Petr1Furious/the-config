{ ... }:
{
  caddy.proxies = [
    {
      host = "gsim.petr1furious.me";
      target = "http://127.0.0.1:27777";
    }
  ];
}
