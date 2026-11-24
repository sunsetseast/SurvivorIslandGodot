class_name GameStateData
extends RefCounted

static func number(value: Variant, low: float, high: float) -> bool:
    return (value is float or value is int) and is_finite(value) and value >= low and value <= high

static func integer(value: Variant, low: float, high: float) -> bool:
    return number(value, low, high) and floor(float(value)) == float(value)

static func int64_text(value: Variant) -> bool:
    return value is String and value.is_valid_int() and str(int(value)) == value

static func identity(value: Variant) -> bool:
    if value is not String or value.length() != 32:
        return false
    for digit: String in value:
        if not digit in "0123456789abcdef":
            return false
    return true

static func new_id() -> String:
    return Crypto.new().generate_random_bytes(16).hex_encode()

static func pose(value: Variant) -> bool:
    if value is not Dictionary or value.get("location") != "tonsai":
        return false
    var point: Variant = value.get("position")
    return point is Array and point.size() == 3 and number(point[0], -83.3, 135.3) \
        and number(point[1], -25, 80) and number(point[2], -62.3, 124.3) \
        and number(value.get("heading"), -PI, PI) and number(value.get("yaw"), -PI, PI) \
        and number(value.get("pitch"), -PI * .5, PI * .5) and value.get("underwater") is bool
