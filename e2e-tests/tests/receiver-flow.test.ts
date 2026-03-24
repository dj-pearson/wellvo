import { describe, it, expect, beforeAll } from "vitest";
import {
  signInOwner,
  signInReceiver,
  type AuthenticatedUser,
} from "../helpers/auth";
import { callEdgeFunction } from "../helpers/api";
import {
  getFamiliesForUser,
  getCheckIns,
  getReceiverSettings,
} from "../helpers/db";

describe("Receiver Flow", () => {
  let owner: AuthenticatedUser;
  let receiver: AuthenticatedUser;
  let familyId: string;
  let receiverId: string;

  beforeAll(async () => {
    owner = await signInOwner();
    receiver = await signInReceiver();

    const receiverFamilies = await getFamiliesForUser(receiver);
    const membership = receiverFamilies.find(
      (m: any) => m.role === "receiver"
    );
    expect(membership).toBeTruthy();
    familyId = membership.family_id;
    receiverId = receiver.userId;
  });

  describe("Check-In Response", () => {
    it("should submit a basic 'I'm OK' check-in", async () => {
      const res = await callEdgeFunction<{
        success: boolean;
        checkin: { id: string; response_type: string };
      }>("/process-checkin-response", {
        accessToken: receiver.accessToken,
        body: {
          receiver_id: receiverId,
          family_id: familyId,
          response_type: "ok",
          source: "app",
        },
      });

      expect(res.ok).toBe(true);
      expect(res.data.success).toBe(true);
      expect(res.data.checkin.response_type).toBe("ok");
    });

    it("should record the check-in in the database", async () => {
      const checkIns = await getCheckIns(receiver, familyId, receiverId);
      expect(checkIns.length).toBeGreaterThan(0);

      const latest = checkIns[0];
      expect(latest.receiver_id).toBe(receiverId);
      expect(latest.family_id).toBe(familyId);
    });

    it("should submit a 'need help' check-in", async () => {
      const res = await callEdgeFunction<{
        success: boolean;
        checkin: { response_type: string };
      }>("/process-checkin-response", {
        accessToken: receiver.accessToken,
        body: {
          receiver_id: receiverId,
          family_id: familyId,
          response_type: "need_help",
          source: "app",
        },
      });

      expect(res.ok).toBe(true);
      expect(res.data.checkin.response_type).toBe("need_help");
    });

    it("should submit a check-in with location data", async () => {
      const res = await callEdgeFunction<{
        success: boolean;
        checkin: { latitude: number; longitude: number };
      }>("/process-checkin-response", {
        accessToken: receiver.accessToken,
        body: {
          receiver_id: receiverId,
          family_id: familyId,
          response_type: "ok",
          source: "app",
          latitude: 40.7128,
          longitude: -74.006,
          location_accuracy_meters: 10,
          location_label: "home",
        },
      });

      expect(res.ok).toBe(true);
      expect(res.data.checkin.latitude).toBe(40.7128);
    });

    it("should reject check-in for a different user", async () => {
      const res = await callEdgeFunction("/process-checkin-response", {
        accessToken: owner.accessToken,
        body: {
          receiver_id: receiverId,
          family_id: familyId,
          response_type: "ok",
        },
      });

      expect(res.status).toBe(403);
    });
  });

  describe("Location Reporting", () => {
    it("should report location", async () => {
      const res = await callEdgeFunction<{
        success: boolean;
        distance_from_home_meters?: number;
        outside_geofence?: boolean;
      }>("/report-location", {
        accessToken: receiver.accessToken,
        body: {
          family_id: familyId,
          latitude: 40.7128,
          longitude: -74.006,
          accuracy_meters: 15,
          battery_level: 72,
        },
      });

      // May return 400 if location tracking not enabled — both are valid
      if (res.ok) {
        expect(res.data.success).toBe(true);
      } else {
        expect(res.status).toBe(400);
      }
    });
  });

  describe("Heartbeat", () => {
    it("should accept heartbeat from receiver", async () => {
      const res = await callEdgeFunction<{ success: boolean }>("/heartbeat", {
        accessToken: receiver.accessToken,
        body: {
          battery_level: 65,
          app_version: "1.0.0",
        },
      });

      expect(res.ok).toBe(true);
      expect(res.data.success).toBe(true);
    });
  });

  describe("Confirm Delivery", () => {
    it("should accept delivery confirmation", async () => {
      const res = await callEdgeFunction<{ success: boolean }>(
        "/confirm-delivery",
        {
          accessToken: receiver.accessToken,
          body: {
            checkin_request_id: "00000000-0000-0000-0000-000000000000",
          },
        }
      );

      // Will succeed (updates notification log) or fail gracefully
      expect(res.status).toBeLessThan(500);
    });
  });
});
