function required(name: string): string {
  const val = process.env[name];
  if (!val) throw new Error(`Missing required env var: ${name}`);
  return val;
}

export const env = {
  get supabaseUrl() {
    return required("SUPABASE_URL");
  },
  get supabaseAnonKey() {
    return required("SUPABASE_ANON_KEY");
  },
  get edgeFunctionsUrl() {
    return process.env.EDGE_FUNCTIONS_URL || "https://functions.wellvo.net";
  },
  get ownerEmail() {
    return required("APPLE_OWNER_DEMO_EMAIL");
  },
  get ownerPassword() {
    return required("APPLE_OWNER_DEMO_PASS");
  },
  get receiverEmail() {
    return required("APPLE_RECEIVER_DEMO_EMAIL");
  },
  get receiverPassword() {
    return required("APPLE_RECEIVER_DEMO_PASS");
  },
};
