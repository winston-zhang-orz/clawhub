import { describe, expect, it } from "vitest";
import {
  canHealSkillOwnershipByGitHubProviderAccountId,
  canHealSkillOwnershipByProviderAccountId,
} from "./githubIdentity";

describe("canHealSkillOwnershipByGitHubProviderAccountId", () => {
  it("denies when either providerAccountId is missing", () => {
    expect(canHealSkillOwnershipByGitHubProviderAccountId(undefined, undefined)).toBe(false);
    expect(canHealSkillOwnershipByGitHubProviderAccountId("123", undefined)).toBe(false);
    expect(canHealSkillOwnershipByGitHubProviderAccountId(undefined, "123")).toBe(false);
    expect(canHealSkillOwnershipByGitHubProviderAccountId(null, "123")).toBe(false);
  });

  it("denies when providerAccountId differs", () => {
    expect(canHealSkillOwnershipByGitHubProviderAccountId("123", "456")).toBe(false);
  });

  it("allows when providerAccountId matches", () => {
    expect(canHealSkillOwnershipByGitHubProviderAccountId("123", "123")).toBe(true);
  });
});

describe("canHealSkillOwnershipByProviderAccountId", () => {
  it("denies when either account is null", () => {
    expect(canHealSkillOwnershipByProviderAccountId(null, null)).toBe(false);
    expect(canHealSkillOwnershipByProviderAccountId({ provider: "github", id: "1" }, null)).toBe(
      false,
    );
    expect(canHealSkillOwnershipByProviderAccountId(null, { provider: "github", id: "1" })).toBe(
      false,
    );
  });

  it("denies cross-provider matches even when IDs are the same", () => {
    // GitHub numeric IDs and GitLab numeric IDs are in separate namespaces.
    expect(
      canHealSkillOwnershipByProviderAccountId(
        { provider: "github", id: "42" },
        { provider: "gitlab", id: "42" },
      ),
    ).toBe(false);
  });

  it("denies same-provider different IDs", () => {
    expect(
      canHealSkillOwnershipByProviderAccountId(
        { provider: "github", id: "1" },
        { provider: "github", id: "2" },
      ),
    ).toBe(false);
    expect(
      canHealSkillOwnershipByProviderAccountId(
        { provider: "gitlab", id: "10" },
        { provider: "gitlab", id: "20" },
      ),
    ).toBe(false);
  });

  it("allows same-provider same ID for GitHub", () => {
    expect(
      canHealSkillOwnershipByProviderAccountId(
        { provider: "github", id: "123" },
        { provider: "github", id: "123" },
      ),
    ).toBe(true);
  });

  it("allows same-provider same ID for GitLab", () => {
    expect(
      canHealSkillOwnershipByProviderAccountId(
        { provider: "gitlab", id: "456" },
        { provider: "gitlab", id: "456" },
      ),
    ).toBe(true);
  });
});
