import { describe, it, expect, beforeAll } from "vitest";
import {
  signInOwner,
  signInReceiver,
  type AuthenticatedUser,
} from "../helpers/auth";
import { callEdgeFunction, healthCheck } from "../helpers/api";
import {
  getFamiliesForUser,
  getCheckInRequests,
  getCheckIns,
} from "../helpers/db";

/**
 * Full end-to-end flow:
 * 1. Both users authenticate
 * 2. Owner sends on-demand check-in
 * 3. Receiver responds to check-in
 * 4. Verify database state from both sides
 */
describe("Full E2E Flow: Owner → Receiver Check-In", () => {
  let owner: AuthenticatedUser;
  let receiver: AuthenticatedUser;
  let familyId: string;
  let receiverId: string;
  let checkInRequestId: string;

  beforeAll(async () => {
    const healthy = await healthCheck();
    expect(healthy).toBe(true);
  });

  it("Step 1: Both users authenticate successfully", async () => {
    [owner, receiver] = await Promise.all([signInOwner(), signInReceiver()]);

    expect(owner.userId).toBeTruthy();
    expect(receiver.userId).toBeTruthy();
    expect(owner.userId).not.toBe(receiver.userId);
  });

  it("Step 2: Find shared family", async () => {
    const ownerFamilies = await getFamiliesForUser(owner);
    const ownerFamily = ownerFamilies.find((m: any) => m.role === "owner");
    expect(ownerFamily).toBeTruthy();
    familyId = ownerFamily.family_id;

    const receiverFamilies = await getFamiliesForUser(receiver);
    const receiverInFamily = receiverFamilies.find(
      (m: any) => m.family_id === familyId && m.role === "receiver"
    );
    expect(receiverInFamily).toBeTruthy();
    receiverId = receiver.userId;
  });

  it("Step 3: Owner sends on-demand check-in", async () => {
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
    checkInRequestId = res.data.request_id;
  });

  it("Step 4: Check-in request exists as pending", async () => {
    const requests = await getCheckInRequests(owner, familyId);
    const pending = requests.find(
      (r: any) => r.id === checkInRequestId && r.status === "pending"
    );
    expect(pending).toBeTruthy();
  });

  it("Step 5: Receiver responds with 'I'm OK'", async () => {
    const res = await callEdgeFunction<{
      success: boolean;
      checkin: { id: string; response_type: string };
    }>("/process-checkin-response", {
      accessToken: receiver.accessToken,
      body: {
        checkin_request_id: checkInRequestId,
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

  it("Step 6: Check-in is recorded in the database", async () => {
    const checkIns = await getCheckIns(owner, familyId, receiverId);
    expect(checkIns.length).toBeGreaterThan(0);

    const latest = checkIns[0];
    expect(latest.receiver_id).toBe(receiverId);
    expect(latest.family_id).toBe(familyId);
  });

  it("Step 7: Owner can verify receiver checked in (via DB)", async () => {
    // Owner queries the same check-in data
    const checkIns = await getCheckIns(owner, familyId, receiverId);
    const todayCheckIn = checkIns.find((c: any) => {
      const checkedInDate = new Date(c.checked_in_at).toDateString();
      return checkedInDate === new Date().toDateString();
    });

    expect(todayCheckIn).toBeTruthy();
  });
});

describe("Full E2E Flow: Receiver Urgent Response", () => {
  let owner: AuthenticatedUser;
  let receiver: AuthenticatedUser;
  let familyId: string;
  let receiverId: string;

  beforeAll(async () => {
    [owner, receiver] = await Promise.all([signInOwner(), signInReceiver()]);

    const ownerFamilies = await getFamiliesForUser(owner);
    const ownerFamily = ownerFamilies.find((m: any) => m.role === "owner");
    familyId = ownerFamily.family_id;
    receiverId = receiver.userId;
  });

  it("Receiver sends 'call me' response", async () => {
    const res = await callEdgeFunction<{
      success: boolean;
      checkin: { response_type: string };
    }>("/process-checkin-response", {
      accessToken: receiver.accessToken,
      body: {
        receiver_id: receiverId,
        family_id: familyId,
        response_type: "call_me",
        source: "app",
      },
    });

    expect(res.ok).toBe(true);
    expect(res.data.checkin.response_type).toBe("call_me");
  });

  it("Receiver sends check-in with mood and location", async () => {
    const res = await callEdgeFunction<{
      success: boolean;
      checkin: {
        response_type: string;
        latitude: number;
        location_label: string;
      };
    }>("/process-checkin-response", {
      accessToken: receiver.accessToken,
      body: {
        receiver_id: receiverId,
        family_id: familyId,
        response_type: "ok",
        source: "app",
        latitude: 40.7128,
        longitude: -74.006,
        location_accuracy_meters: 5,
        location_label: "school",
        battery_level: 80,
      },
    });

    expect(res.ok).toBe(true);
    expect(res.data.success).toBe(true);
  });
});
