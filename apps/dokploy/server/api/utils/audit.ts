// import { createAuditLog } from "@dokploy/server/services/proprietary/audit-log";
// import type { AuditAction, AuditResourceType } from "@dokploy/server/db/schema";
type AuditAction = string;
type AuditResourceType = string;

interface AuditCtx {
	user: { id: string; email: string; role: string };
	session: { activeOrganizationId: string };
}

interface AuditEvent {
	action: AuditAction;
	resourceType: AuditResourceType;
	resourceId?: string;
	resourceName?: string;
	metadata?: Record<string, unknown>;
}

/**
 * Creates an audit log entry from a tRPC context.
 * Extracts userId, userEmail, userRole and organizationId automatically.
 *
 * Usage:
 *   await audit(ctx, { action: "create", resourceType: "project", resourceName: "my-app" });
 */
export const audit = (_ctx: AuditCtx, _event: AuditEvent) => Promise.resolve();
