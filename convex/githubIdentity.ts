import { v } from "convex/values";
import { internalQuery } from "./functions";
import { getGitHubProviderAccountId, getGitLabProviderAccountId } from "./lib/githubIdentity";

export const getGitHubProviderAccountIdInternal = internalQuery({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => getGitHubProviderAccountId(ctx, args.userId),
});

export const getGitLabProviderAccountIdInternal = internalQuery({
  args: { userId: v.id("users") },
  handler: async (ctx, args) => getGitLabProviderAccountId(ctx, args.userId),
});
