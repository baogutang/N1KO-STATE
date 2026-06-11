#import "XPCAuditShim.h"
#import <bsm/libbsm.h>

// `auditToken` is a real, KVC-visible property on NSXPCConnection — it is just
// not declared in the public headers. Declaring it in a category lets the
// compiler emit a normal objc_msgSend; we deliberately avoid +valueForKey: so
// the struct return is handled with the correct ABI.
@interface NSXPCConnection (XPCAuditShimPrivate)
@property (nonatomic, readonly) audit_token_t auditToken;
@end

NSData * _Nullable XPCAuditCopyAuditTokenData(NSXPCConnection *connection) {
    if (connection == nil) { return nil; }
    if (![connection respondsToSelector:@selector(auditToken)]) { return nil; }
    audit_token_t token = connection.auditToken;
    return [NSData dataWithBytes:&token length:sizeof(token)];
}
