import { describe, it, expect, beforeAll } from "vitest";
import {
  signInOwner,
  signInReceiver,
  type AuthenticatedUser,
} from "../helpers/auth";
import { callEdgeFunction } from "../helpers/api";
import { getFamiliesForUser, getCheckInRequests } from "../helpers/db";

describe("Owner Flow", () => {
  let owner: AuthenticatedUser;
  let receiver: AuthenticatedUser;
  let familyId: string;
  let receiverId: string;

  beforeAll(async () => {
    owner = await signInOwner();
    receiver = await signInReceiver();

    // Find the shared family
    const ownerFamilies = await getFamiliesForUser(owner);
    const ownerFamily = ownerFamilies.find((m: any) => m.role === "owner");
    expect(ownerFamily).toBeTruthy();
    familyId = ownerFamily.family_id;
    receiverId = receiver.userId;
  });

  describe("On-Demand Check-In", () => {
    it("should send an on-demand check-in request", async () => {
      const res = await callEdgeFunction<{
        success: boolean;
        request_id: string;
      }>("/on-demand-checkin", {
        accessToken: owner.accessToken,
        body: {
          receiver_id: receiverId,
          family_id: familyId,
        },
      });

      expect(res.ok).toBe(true);
      expect(res.data.success).toBe(true);
      expect(res.data.request_id).toBeTruthy();
    });

    it("should create a pending check-in request in the database", async () => {
      const requests = await getCheckInRequests(owner, familyId);
      expect(requests.length).toBeGreaterThan(0);

      const latest = requests[0];
      expect(latest.status).toBe("pending");
      expect(latest.family_id).toBe(familyId);
    });

    it("should reject on-demand check-in from non-owner", async () => {
      const res = await callEdgeFunction("/on-demand-checkin", {
        accessToken: receiver.accessToken,
        body: {
          receiver_id: receiverId,
          family_id: familyId,
        },
      });

      expect(res.status).toBe(403);
    });
  });

  describe("Heartbeat", () => {
    it("should accept heartbeat from owner", async () => {
      const res = await callEdgeFunction<{ success: boolean }>("/heartbeat", {
        accessToken: owner.accessToken,
        body: {
          battery_level: 85,
          app_version: "1.0.0",
        },
      });

      expect(res.ok).toBe(true);
      expect(res.data.success).toBe(true);
    });
  });
});
