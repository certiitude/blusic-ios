CREATE TABLE IF NOT EXISTS soryn_accounts (
  id uuid PRIMARY KEY,
  username text UNIQUE NOT NULL,
  display_name text NOT NULL,
  password_hash text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS soryn_sessions (
  token_hash text PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES soryn_accounts(id) ON DELETE CASCADE,
  expires_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS soryn_sessions_account ON soryn_sessions(account_id);
CREATE TABLE IF NOT EXISTS soryn_cloud_libraries (
  account_id uuid PRIMARY KEY REFERENCES soryn_accounts(id) ON DELETE CASCADE,
  snapshot jsonb NOT NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS soryn_cloud_devices (
  account_id uuid NOT NULL REFERENCES soryn_accounts(id) ON DELETE CASCADE,
  device_id uuid NOT NULL,
  baseline jsonb,
  pending_request uuid,
  pending_snapshot jsonb,
  PRIMARY KEY(account_id,device_id)
);
ALTER TABLE soryn_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE soryn_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE soryn_cloud_libraries ENABLE ROW LEVEL SECURITY;
ALTER TABLE soryn_cloud_devices ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON soryn_accounts,soryn_sessions,soryn_cloud_libraries,soryn_cloud_devices FROM PUBLIC;
