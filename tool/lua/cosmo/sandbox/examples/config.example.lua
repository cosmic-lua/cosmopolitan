-- Example config for netns-proxy.lua.
--
-- Each key in `allowed_hosts` is a host:port (or just host for any
-- port, or host:* for explicit any-port). The associated rule may be:
--
--   {}                                              -- pass-through
--   {type="bearer", token="..."}                    -- HTTP only
--   {type="basic",  username="...", password="..."} -- HTTP only
--   {type="header", header_name="x-api-key", header_value="..."}
--
-- HTTPS (CONNECT tunnels) auth is intentionally not injected — the
-- bytes are encrypted end-to-end. The rule is still consulted as an
-- allowlist gate, and serves as documentation of which credentials
-- the child process is expected to use.

return {
  proxy_addr = "127.0.0.1:3128",

  allowed_hosts = {
    -- Anthropic Claude API
    ["api.anthropic.com:443"] = {},

    -- GitHub
    ["api.github.com:443"]            = {},
    ["github.com:443"]                = {},
    ["objects.githubusercontent.com:443"] = {},
    ["codeload.github.com:443"]       = {},

    -- Package registries
    ["registry.npmjs.org:443"] = {},
    ["pypi.org:443"]           = {},
    ["files.pythonhosted.org:443"] = {},

    -- Plain-HTTP example with header injection
    -- ["api.internal.example.com:80"] = {
    --   type = "header",
    --   header_name = "x-api-key",
    --   header_value = os.getenv("INTERNAL_API_KEY") or "",
    -- },
  },

  -- If you don't pass `--` on the command line, this command runs.
  command = {"bash"},

  log_level = "info",
  log_format = "text",
}
