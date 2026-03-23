import type { Id } from "../_generated/dataModel";
import type { QueryCtx } from "../_generated/server";

export type OAuthProviderAccount = { provider: string; id: string };

export function canHealSkillOwnershipByGitHubProviderAccountId(
  ownerProviderAccountId: string | null | undefined,
  callerProviderAccountId: string | null | undefined,
) {
  // Security invariant: missing identity must never grant ownership.
  if (!ownerProviderAccountId || !callerProviderAccountId) return false;
  return ownerProviderAccountId === callerProviderAccountId;
}

/**
 * Provider-aware ownership check. Matches when both owner and caller used the
 * same OAuth provider (e.g. both "github" or both "gitlab") AND have the same
 * numeric provider account ID. Cross-provider matches are never allowed because
 * provider IDs are scoped to their respective namespaces.
 */
export function canHealSkillOwnershipByProviderAccountId(
  owner: OAuthProviderAccount | null,
  caller: OAuthProviderAccount | null,
): boolean {
  // Security invariant: missing identity must never grant ownership.
  if (!owner || !caller) return false;
  return owner.provider === caller.provider && owner.id === caller.id;
}

export async function getGitHubProviderAccountId(
  ctx: Pick<QueryCtx, "db">,
  userId: Id<"users">,
): Promise<string | null> {
  const account = await ctx.db
    .query("authAccounts")
    .withIndex("userIdAndProvider", (q) => q.eq("userId", userId).eq("provider", "github"))
    .unique();
  return account?.providerAccountId ?? null;
}

export async function getGitLabProviderAccountId(
  ctx: Pick<QueryCtx, "db">,
  userId: Id<"users">,
): Promise<string | null> {
  const account = await ctx.db
    .query("authAccounts")
    .withIndex("userIdAndProvider", (q) => q.eq("userId", userId).eq("provider", "gitlab"))
    .unique();
  return account?.providerAccountId ?? null;
}

/**
 * Returns the first OAuth provider account found for the user, trying GitHub
 * first then GitLab. Used for provider-agnostic ownership healing.
 */
export async function getAnyOAuthProviderAccountId(
  ctx: Pick<QueryCtx, "db">,
  userId: Id<"users">,
): Promise<OAuthProviderAccount | null> {
  const githubId = await getGitHubProviderAccountId(ctx, userId);
  if (githubId) return { provider: "github", id: githubId };
  const gitlabId = await getGitLabProviderAccountId(ctx, userId);
  if (gitlabId) return { provider: "gitlab", id: gitlabId };
  return null;
}
