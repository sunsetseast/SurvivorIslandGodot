extends RefCounted

var transport: SurvivorSupabaseTransport

func _init(adapter: SurvivorSupabaseTransport) -> void:
    transport = adapter

func verify(token: String) -> Dictionary:
    var user_response := await transport.send("/auth/v1/user", HTTPClient.METHOD_GET, {}, token)
    if not user_response.ok or user_response.data is not Dictionary:
        return {}
    var user: Dictionary = user_response.data
    var account: Variant = user.get("id")
    if account is not String or account.length() != 36 or user.get("email_confirmed_at") == null \
            or user.get("is_anonymous", false):
        return {}
    # Reuse the live session gate. This rejects a signed JWT whose Auth session was revoked.
    var live := await transport.send("/rest/v1/rpc/player_data", HTTPClient.METHOD_POST,
        {"action": "profile", "args": {}}, token)
    if not live.ok or live.data is not Dictionary:
        return {}
    # Only inspect claims after both trusted project endpoints have authorized the token.
    var encoded := token.get_slice(".", 1).replace("-", "+").replace("_", "/")
    encoded += "=".repeat(posmod(-encoded.length(), 4))
    var claims: Variant = JSON.parse_string(Marshalls.base64_to_utf8(encoded))
    if claims is not Dictionary or claims.get("sub") != account or claims.get("aud") != "authenticated" \
            or claims.get("role") != "authenticated" or String(claims.get("session_id", "")).length() != 36 \
            or not GameStateData.integer(claims.get("exp"), int(Time.get_unix_time_from_system()) + 1, 4_000_000_000):
        return {}
    # Local GoTrue signs with its internal Kong issuer. Hosted is pinned to the exact project.
    if transport.endpoint == SurvivorSupabaseTransport.PROJECT and claims.get("iss") != transport.endpoint + "/auth/v1":
        return {}
    return {"account": account, "expires": int(claims.exp), "session": claims.session_id}
