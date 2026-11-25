// Godot iOS static plugin. Never logs or returns credentials outside AuthService.
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include "core/config/engine.h"
#include "core/object/class_db.h"

class SurvivorKeychain : public Object {
    GDCLASS(SurvivorKeychain, Object);
    static NSMutableDictionary *query() {
        return [@{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: [[NSBundle mainBundle].bundleIdentifier stringByAppendingString:@".session"],
            (__bridge id)kSecAttrAccount: @"foreground-session",
            (__bridge id)kSecAttrSynchronizable: @NO} mutableCopy];
    }
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("read_record"), &SurvivorKeychain::read_record);
        ClassDB::bind_method(D_METHOD("write_record", "value"), &SurvivorKeychain::write_record);
        ClassDB::bind_method(D_METHOD("clear_record"), &SurvivorKeychain::clear_record);
    }
public:
    Dictionary read_record() {
        @autoreleasepool {
            NSMutableDictionary *q = query();
            q[(__bridge id)kSecReturnData] = @YES;
            CFTypeRef result = nullptr;
            OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)q, &result);
            Dictionary record;
            record["status"] = status == errSecSuccess ? "ok" : (status == errSecItemNotFound ? "missing" : "unavailable");
            if (status == errSecSuccess && result) {
                NSData *data = CFBridgingRelease(result);
                NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (text) record["value"] = String::utf8(text.UTF8String);
            } else if (result) CFRelease(result);
            return record;
        }
    }
    int write_record(String value) {
        @autoreleasepool {
            CharString utf8 = value.utf8();
            NSData *data = [NSData dataWithBytes:utf8.get_data() length:utf8.length()];
            NSDictionary *attributes = @{
                (__bridge id)kSecValueData: data,
                (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleWhenUnlockedThisDeviceOnly};
            NSMutableDictionary *q = query();
            OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)q, (__bridge CFDictionaryRef)attributes);
            if (status == errSecItemNotFound) {
                [q addEntriesFromDictionary:attributes];
                status = SecItemAdd((__bridge CFDictionaryRef)q, nullptr);
            }
            return (int)status;
        }
    }
    int clear_record() {
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query());
        return status == errSecItemNotFound ? 0 : (int)status;
    }
};
static SurvivorKeychain *instance = nullptr;
void survivor_keychain_init() {
    instance = memnew(SurvivorKeychain);
    Engine::get_singleton()->add_singleton(Engine::Singleton("SurvivorKeychain", instance));
}
void survivor_keychain_deinit() {
    Engine::get_singleton()->remove_singleton("SurvivorKeychain");
    if (instance) memdelete(instance);
    instance = nullptr;
}
