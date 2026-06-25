/**
 * Input validation utilities for edge function endpoints.
 * Provides bounds checking, format validation, and sanitization.
 */

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const TIME_24H_REGEX = /^([01]?[0-9]|2[0-3]):[0-5][0-9]$/;

export function isValidUUID(value: string): boolean {
  return UUID_REGEX.test(value);
}

export function isValidLatitude(lat: number): boolean {
  return typeof lat === "number" && !isNaN(lat) && lat >= -90 && lat <= 90;
}

export function isValidLongitude(lon: number): boolean {
  return typeof lon === "number" && !isNaN(lon) && lon >= -180 && lon <= 180;
}

export function isValidBatteryLevel(level: number): boolean {
  return typeof level === "number" && !isNaN(level) && level >= 0 && level <= 1;
}

export function isValidAccuracyMeters(meters: number): boolean {
  return typeof meters === "number" && !isNaN(meters) && meters >= 0 && meters <= 100000;
}

export function isValidTime24H(time: string): boolean {
  return TIME_24H_REGEX.test(time);
}

/**
 * Truncate a string to maxLength characters.
 * Returns the original string if within bounds.
 */
export function truncateString(value: string, maxLength: number): string {
  if (value.length <= maxLength) return value;
  return value.substring(0, maxLength);
}

/**
 * Sanitize a display name for use in notification bodies.
 * Removes HTML tags, control characters, and truncates to maxLength.
 */
export function sanitizeDisplayName(name: string, maxLength = 100): string {
  return name
    .replace(/<[^>]*>/g, "")           // Strip HTML tags
    .replace(/[^\P{C}\n]/gu, "")       // Remove control characters (keep printable + newline)
    .replace(/[\r\n]+/g, " ")          // Replace newlines with space
    .trim()
    .substring(0, maxLength);
}

/**
 * Validate a timezone string against IANA timezone database.
 * Returns true if the timezone is valid.
 */
let _validTimezones: Set<string> | null = null;
function getValidTimezones(): Set<string> {
  if (!_validTimezones) {
    _validTimezones = new Set(Intl.supportedValuesOf("timeZone"));
  }
  return _validTimezones;
}

export function isValidTimezone(tz: string): boolean {
  return getValidTimezones().has(tz);
}

/**
 * Coerce numeric request fields that an older client may have sent as JSON
 * strings (e.g. {"latitude":"37.77"}) into real numbers, in-place.
 *
 * iOS builds shipped before the US-IOS078 fix sent latitude/longitude/
 * battery_level/accuracy as quoted strings; the validators above require
 * `typeof === "number"`, so without this every location-bearing check-in and
 * report-location from those builds 400s. Current builds send real numbers and
 * pass through untouched. Non-numeric junk is left as-is so validation still
 * rejects it. Defensive secondary per CLAUDE.md §B (server tolerates both shapes).
 */
export function coerceNumericFields(body: Record<string, unknown>, keys: string[]): void {
  for (const key of keys) {
    const v = body[key];
    if (typeof v === "string" && v.trim() !== "") {
      const n = Number(v);
      if (!isNaN(n)) body[key] = n;
    }
  }
}

/**
 * Validate and return an error Response if any of the checks fail.
 * Returns null if all validations pass.
 */
export function validateLocationFields(body: {
  latitude?: number;
  longitude?: number;
  location_accuracy_meters?: number;
  battery_level?: number;
  location_label?: string;
}): string | null {
  if (body.latitude != null && !isValidLatitude(body.latitude)) {
    return "Invalid latitude: must be between -90 and 90";
  }
  if (body.longitude != null && !isValidLongitude(body.longitude)) {
    return "Invalid longitude: must be between -180 and 180";
  }
  if (body.latitude != null && body.longitude == null) {
    return "longitude is required when latitude is provided";
  }
  if (body.longitude != null && body.latitude == null) {
    return "latitude is required when longitude is provided";
  }
  if (body.location_accuracy_meters != null && !isValidAccuracyMeters(body.location_accuracy_meters)) {
    return "Invalid location_accuracy_meters: must be between 0 and 100000";
  }
  if (body.battery_level != null && !isValidBatteryLevel(body.battery_level)) {
    return "Invalid battery_level: must be between 0 and 1";
  }
  if (body.location_label != null && body.location_label.length > 500) {
    return "location_label must not exceed 500 characters";
  }
  return null;
}
