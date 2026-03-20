import type { IncomingMessage } from "node:http";
import { apiKey } from "@better-auth/api-key";
import * as bcrypt from "bcrypt";
import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";
import { APIError } from "better-auth/api";
import { admin, organization, twoFactor } from "better-auth/plugins";
import { and, desc, eq } from "drizzle-orm";
import { BETTER_AUTH_SECRET } from "../constants";
import { db } from "../db";
import * as schema from "../db/schema";
import {
	getTrustedOrigins,
	getTrustedProviders,
	getUserByToken,
} from "../services/admin";
import {
	getWebServerSettings,
	updateWebServerSettings,
} from "../services/web-server-settings";
import { getHubSpotUTK, submitToHubSpot } from "../utils/tracking/hubspot";
import { sendEmail } from "../verification/send-verification-email";
import { getPublicIpWithFallback } from "../wss/utils";
import { ac, adminRole, memberRole, ownerRole } from "./access-control";

const { handler, api } = betterAuth({
	database: drizzleAdapter(db, {
		provider: "pg",
		schema: schema,
	}),
	disabledPaths: [
		"/sso/register",
		"/organization/create",
		"/organization/update",
		"/organization/delete",
	],
	secret: BETTER_AUTH_SECRET,
	...(!IS_CLOUD
		? {
				advanced: {
					useSecureCookies: false,
					defaultCookieAttributes: {
						sameSite: "lax",
						secure: false,
						httpOnly: true,
						path: "/",
					},
				},
			}
		: {}),

	account: {
		accountLinking: {
			enabled: true,
			async trustedProviders() {
				const fromDb = await getTrustedProviders();
				return ["github", "google", ...fromDb];
			},
			allowDifferentEmails: true,
		},
	},
	appName: "Dokploy",
	socialProviders: {
		github: {
			clientId: process.env.GITHUB_CLIENT_ID as string,
			clientSecret: process.env.GITHUB_CLIENT_SECRET as string,
		},
		google: {
			clientId: process.env.GOOGLE_CLIENT_ID as string,
			clientSecret: process.env.GOOGLE_CLIENT_SECRET as string,
		},
	},
	logger: {
		disabled: process.env.NODE_ENV === "production",
	},
	async trustedOrigins() {
		try {
			const [trustedOrigins, settings] = await Promise.all([
				getTrustedOrigins(),
				getWebServerSettings(),
			]);
			if (!settings) return [];
			const devOrigins =
				process.env.NODE_ENV === "development"
					? [
							"http://localhost:3000",
							"https://absolutely-handy-falcon.ngrok-free.app",
						]
					: [];
			return [
				...(settings?.serverIp ? [`http://${settings?.serverIp}:3000`] : []),
				...(settings?.host ? [`https://${settings?.host}`] : []),
				...devOrigins,
				...trustedOrigins,
			];
		} catch (error) {
			console.error("Failed to resolve trusted origins:", error);
			return [];
		}
	},
	emailVerification: {
		sendOnSignUp: true,
		autoSignInAfterVerification: true,
	},
	emailAndPassword: {
		enabled: true,
		autoSignIn: true,
		requireEmailVerification: false,
		password: {
			async hash(password) {
				return bcrypt.hashSync(password, 10);
			},
			async verify({ hash, password }) {
				return bcrypt.compareSync(password, hash);
			},
		},
		sendResetPassword: async ({ user, url }) => {
			await sendEmail({
				email: user.email,
				subject: "Reset your password",
				text: `
				<p>Click the link to reset your password: <a href="${url}">Reset Password</a></p>
				`,
			});
		},
	},
	databaseHooks: {
		user: {
			create: {
				before: async (_user, context) => {
					const xDokployToken =
						context?.request?.headers?.get("x-dokploy-token");
					if (xDokployToken) {
						const user = await getUserByToken(xDokployToken);
						if (!user) {
							throw new APIError("BAD_REQUEST", {
								message: "User not found",
							});
						}
					} else {
						const isAdminPresent = await db.query.member.findFirst({
							where: eq(schema.member.role, "owner"),
						});
						if (isAdminPresent) {
							throw new APIError("BAD_REQUEST", {
								message: "Admin is already created",
							});
						}
					}
				},
				after: async (user) => {
					const isAdminPresent = await db.query.member.findFirst({
						where: eq(schema.member.role, "owner"),
					});

					if (!isAdminPresent) {
						await updateWebServerSettings({
							serverIp: await getPublicIpWithFallback(),
						});
					}

					await db.transaction(async (tx) => {
						const organization = await tx
							.insert(schema.organization)
							.values({
								name: "My Organization",
								ownerId: user.id,
								createdAt: new Date(),
							})
							.returning()
							.then((res) => res[0]);

						await tx.insert(schema.member).values({
							userId: user.id,
							organizationId: organization?.id || "",
							role: "owner",
							createdAt: new Date(),
							isDefault: true,
						});
					});
				},
			},
		},
		session: {
			create: {
				before: async (session) => {
					// Find the default organization for this user
					// Priority: 1) isDefault=true, 2) most recently created
					const member = await db.query.member.findFirst({
						where: eq(schema.member.userId, session.userId),
						orderBy: [
							desc(schema.member.isDefault),
							desc(schema.member.createdAt),
						],
						with: {
							organization: true,
						},
					});

					return {
						data: {
							...session,
							activeOrganizationId: member?.organization.id,
						},
					};
				},
				after: async (session) => {
					const orgId = (
						session as typeof session & { activeOrganizationId?: string }
					).activeOrganizationId;
					if (!orgId) return;
					const memberRecord = await db.query.member.findFirst({
						where: and(
							eq(schema.member.userId, session.userId),
							eq(schema.member.organizationId, orgId),
						),
						with: { user: true },
					});
					if (!memberRecord) return;
				},
			},
			delete: {
				after: async (session) => {
					const orgId = (
						session as typeof session & { activeOrganizationId?: string }
					).activeOrganizationId;
					if (!orgId) return;
					const memberRecord = await db.query.member.findFirst({
						where: and(
							eq(schema.member.userId, session.userId),
							eq(schema.member.organizationId, orgId),
						),
						with: { user: true },
					});
					if (!memberRecord) return;
				},
			},
		},
	},
	session: {
		expiresIn: 60 * 60 * 24 * 3,
		updateAge: 60 * 60 * 24,
	},
	user: {
		modelName: "user",
		fields: {
			name: "firstName", // Map better-auth's default 'name' field to 'firstName' column
		},
		additionalFields: {
			role: {
				type: "string",
				required: false,
				input: false,
			},
			ownerId: {
				type: "string",
				required: false,
				input: false,
			},
			allowImpersonation: {
				fieldName: "allowImpersonation",
				type: "boolean",
				defaultValue: false,
			},
			lastName: {
				type: "string",
				required: false,
				input: true,
				defaultValue: "",
			},
		},
	},
	plugins: [
		apiKey({
			enableMetadata: true,
			references: "user",
		}),
		twoFactor(),
		organization({
			ac,
			roles: {
				owner: ownerRole,
				admin: adminRole,
				member: memberRole,
			},
			dynamicAccessControl: {
				enabled: true,
				maximumRolesPerOrganization: 10,
			},
			async sendInvitationEmail(data, _request) {
				const host =
					process.env.NODE_ENV === "development"
						? "http://localhost:3000"
						: "https://app.dokploy.com";
				const inviteLink = `${host}/invitation?token=${data.id}`;

				await sendEmail({
					email: data.email,
					subject: "Invitation to join organization",
					text: `
				<p>You are invited to join ${data.organization.name} on Dokploy. Click the link to accept the invitation: <a href="${inviteLink}">Accept Invitation</a></p>
				`,
				});
			},
		}),
		admin({
			adminUserIds: [process.env.USER_ADMIN_ID as string],
		}),
	],
});

const _auth = {
	handler,
	createApiKey: api.createApiKey,
};

export type AuthType = typeof _auth;
export const auth: AuthType = _auth;

export const validateRequest = async (request: IncomingMessage) => {
	const apiKey = request.headers["x-api-key"] as string;
	if (apiKey) {
		try {
			const { valid, key, error } = await api.verifyApiKey({
				body: {
					key: apiKey,
				},
			});

			if (error) {
				throw new Error(error.message?.toString() || "Error verifying API key");
			}
			if (!valid || !key) {
				return {
					session: null,
					user: null,
				};
			}

			const apiKeyRecord = await db.query.apikey.findFirst({
				where: eq(schema.apikey.id, key.id),
				with: {
					user: true,
				},
			});

			if (!apiKeyRecord) {
				return {
					session: null,
					user: null,
				};
			}

			const organizationId = JSON.parse(
				apiKeyRecord.metadata || "{}",
			).organizationId;

			if (!organizationId) {
				return {
					session: null,
					user: null,
				};
			}

			const member = await db.query.member.findFirst({
				where: and(
					eq(schema.member.userId, apiKeyRecord.user.id),
					eq(schema.member.organizationId, organizationId),
				),
				with: {
					organization: true,
				},
			});

			// When accessing from DB, use actual column names
			const userFromDb = apiKeyRecord.user as typeof apiKeyRecord.user & {
				firstName: string;
				lastName: string;
			};

			const mockSession = {
				session: {
					userId: apiKeyRecord.user.id,
					activeOrganizationId: organizationId || "",
				},
				user: {
					id: userFromDb.id,
					name: userFromDb.firstName, // Map firstName back to name for better-auth
					email: userFromDb.email,
					emailVerified: userFromDb.emailVerified,
					image: userFromDb.image,
					createdAt: userFromDb.createdAt,
					updatedAt: userFromDb.updatedAt,
					twoFactorEnabled: userFromDb.twoFactorEnabled,
					role: member?.role || "member",
					ownerId: member?.organization.ownerId || apiKeyRecord.user.id,
				},
			};

			return mockSession;
		} catch (error) {
			console.error("Error verifying API key", error);
			return {
				session: null,
				user: null,
			};
		}
	}

	// If no API key, proceed with normal session validation
	const session = await api.getSession({
		headers: new Headers({
			cookie: request.headers.cookie || "",
		}),
	});

	if (!session?.session || !session.user) {
		return {
			session: null,
			user: null,
		};
	}

	if (session?.user) {
		const member = await db.query.member.findFirst({
			where: and(
				eq(schema.member.userId, session.user.id),
				...(session.session.activeOrganizationId
					? [
							eq(
								schema.member.organizationId,
								session.session.activeOrganizationId || "",
							),
						]
					: []),
			),
			orderBy: [desc(schema.member.isDefault), desc(schema.member.createdAt)],
			with: {
				organization: true,
				user: true,
			},
		});

		session.user.role = member?.role || "member";
		session.session.activeOrganizationId = member?.organization.id || "";
		if (member) {
			session.user.ownerId = member.organization.ownerId;
		} else {
			session.user.ownerId = session.user.id;
		}
	}

	return session;
};
