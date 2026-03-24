import { describe, it, expect, beforeAll } from "vitest";
import { signInOwner, signInReceiver, type AuthenticatedUser } from "../helpers/auth";
import { healthCheck } from "../helpers/api";
import { getUserProfile, getFamiliesForUser } from "../helpers/db";

describe("Authentication", () => {
  beforeAll(async () => {
    const healthy = await healthCheck();
    expect(healthy).toBe(true);
  });

  describe("Owner", () => {
    let owner: AuthenticatedUser;

    it("should sign in with email/password", async () => {
      owner = await signInOwner();
      expect(owner.userId).toBeTruthy();
      expect(owner.accessToken).toBeTruthy();
    });

    it("should have a user profile in the database", async () => {
      const profile = await getUserProfile(owner);
      expect(profile).toBeTruthy();
      expect(profile.email).toBe(owner.email);
    });

    it("should belong to at least one family as owner", async () => {
      const memberships = await getFamiliesForUser(owner);
      expect(memberships.length).toBeGreaterThan(0);

      const ownerMembership = memberships.find(
        (m: any) => m.role === "owner"
      );
      expect(ownerMembership).toBeTruthy();
    });
  });

  describe("Receiver", () => {
    let receiver: AuthenticatedUser;

    it("should sign in with email/password", async () => {
      receiver = await signInReceiver();
      expect(receiver.userId).toBeTruthy();
      expect(receiver.accessToken).toBeTruthy();
    });

    it("should have a user profile in the database", async () => {
      const profile = await getUserProfile(receiver);
      expect(profile).toBeTruthy();
      expect(profile.email).toBe(receiver.email);
    });

    it("should belong to at least one family as receiver", async () => {
      const memberships = await getFamiliesForUser(receiver);
      expect(memberships.length).toBeGreaterThan(0);

      const receiverMembership = memberships.find(
        (m: any) => m.role === "receiver"
      );
      expect(receiverMembership).toBeTruthy();
    });
  });
});
