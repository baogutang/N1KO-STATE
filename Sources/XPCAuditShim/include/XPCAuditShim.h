#ifndef XPC_AUDIT_SHIM_H
#define XPC_AUDIT_SHIM_H

#import <Foundation/Foundation.h>

// ----------------------------------------------------------------------------
// NSXPCConnection.auditToken bridge.
//
// `NSXPCConnection` exposes an `auditToken` property at runtime, but it is SPI
// and absent from the public SDK headers. The privileged helper needs the
// caller's `audit_token_t` to validate its code signature (via
// SecCodeCopyGuestWithAttributes + kSecGuestAttributeAudit) — the only
// race-free way to authenticate an XPC peer (PID-based checks are vulnerable to
// PID reuse).
//
// We read the property reflectively here and hand Swift back the raw token
// bytes as NSData (exactly sizeof(audit_token_t)), so no private symbol is
// referenced at link time and pure-Swift callers stay clean.
// ----------------------------------------------------------------------------

NS_ASSUME_NONNULL_BEGIN

/// Copy the connection's `audit_token_t` as raw NSData (sizeof(audit_token_t)
/// bytes). Returns nil if the property is unavailable on this OS.
NSData * _Nullable XPCAuditCopyAuditTokenData(NSXPCConnection *connection);

NS_ASSUME_NONNULL_END

#endif /* XPC_AUDIT_SHIM_H */
