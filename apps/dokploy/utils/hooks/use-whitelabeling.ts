/**
 * Stub hooks for whitelabeling config.
 * The whitelabeling router has been removed from this OSS build.
 * These hooks return null so all consumers continue to work with default values.
 */

/**
 * Hook to access whitelabeling config for authenticated pages (dashboard, services, etc.).
 * Returns null since whitelabeling is not available in this build.
 */
export function useWhitelabeling() {
	return {
		config: null as null | {
			docsUrl?: string | null;
			supportUrl?: string | null;
			logoUrl?: string | null;
			loginLogoUrl?: string | null;
			appName?: string | null;
			appDescription?: string | null;
		},
		isLoading: false,
		isError: false,
		error: null,
	};
}

/**
 * Hook to access the public whitelabeling config.
 * Returns null since whitelabeling is not available in this build.
 */
export function useWhitelabelingPublic() {
	return {
		config: null as null | {
			docsUrl?: string | null;
			supportUrl?: string | null;
			logoUrl?: string | null;
			loginLogoUrl?: string | null;
			appName?: string | null;
			appDescription?: string | null;
		},
		isLoading: false,
		isError: false,
		error: null,
	};
}
