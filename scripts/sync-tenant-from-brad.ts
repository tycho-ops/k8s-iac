import { spawnSync } from "node:child_process";

const SRC_CTX = "admin@brad-fr-k8s";
const DST_CTX = "admin@eu1-paris-qtrn-io";
const SRC_TENANT = "120f7329-72ff-4e11-9f44-7c19c8f8c29e"; // Brad Technology on brad-fr-k8s
const DST_TENANT = "4e93df10-fcfb-44b8-8e06-d08ce21413db"; // Brad Technology on eu1-paris-qtrn-io

function migrateTable(name: string, exportQuery: string, importQuery: string) {
  console.log(`\n📦 Syncing ${name}...`);
  const copyOut = spawnSync("kubectl", ["--context", SRC_CTX, "-n", "lorawan", "exec", "deployment/postgres", "--", "psql", "-U", "chirpstack", "-d", "chirpstack", "-c", exportQuery]);
  if (copyOut.status !== 0) {
    console.error(`Export error on ${name}:`, copyOut.stderr.toString());
    process.exit(1);
  }
  
  const copyIn = spawnSync("kubectl", ["--context", DST_CTX, "-n", "lorawan", "exec", "-i", "deployment/postgres", "--", "psql", "-U", "chirpstack", "-d", "chirpstack", "-c", importQuery], {
    input: copyOut.stdout
  });
  if (copyIn.status !== 0) {
    console.error(`Import error on ${name}:`, copyIn.stderr.toString());
    process.exit(1);
  }
  console.log(`✅ ${name}: ${copyIn.stdout.toString().trim()}`);
}

console.log("🚀 Syncing ChirpStack Tenant Configuration from brad-fr-k8s to eu1-paris-qtrn-io...");

// Clean target tenant state
spawnSync("kubectl", ["--context", DST_CTX, "-n", "lorawan", "exec", "deployment/postgres", "--", "psql", "-U", "chirpstack", "-d", "chirpstack", "-c", `
  DELETE FROM device WHERE application_id IN (SELECT id FROM application WHERE tenant_id = '${DST_TENANT}');
  DELETE FROM application WHERE tenant_id = '${DST_TENANT}';
  DELETE FROM gateway WHERE tenant_id = '${DST_TENANT}';
  DELETE FROM device_profile WHERE tenant_id = '${DST_TENANT}';
`]);

// 1. Device Profile
migrateTable(
  "device_profile",
  `COPY (
    SELECT id, '${DST_TENANT}'::uuid, created_at, updated_at, name, region, mac_version, reg_params_revision, 
           adr_algorithm_id, payload_codec_runtime, uplink_interval, device_status_req_interval, 
           supports_otaa, supports_class_b, supports_class_c, class_b_timeout, class_b_ping_slot_nb_k, 
           class_b_ping_slot_dr, class_b_ping_slot_freq, class_c_timeout, abp_rx1_delay, abp_rx1_dr_offset, 
           abp_rx2_dr, abp_rx2_freq, tags, payload_codec_script, flush_queue_on_activate, description, 
           measurements, auto_detect_measurements, region_config_id, is_relay, is_relay_ed, relay_ed_relay_only, 
           relay_enabled, relay_cad_periodicity, relay_default_channel_index, relay_second_channel_freq, 
           relay_second_channel_dr, relay_second_channel_ack_offset, relay_ed_activation_mode, 
           relay_ed_smart_enable_level, relay_ed_back_off, relay_ed_uplink_limit_bucket_size, 
           relay_ed_uplink_limit_reload_rate, relay_join_req_limit_reload_rate, relay_notify_limit_reload_rate, 
           relay_global_uplink_limit_reload_rate, relay_overall_limit_reload_rate, relay_join_req_limit_bucket_size, 
           relay_notify_limit_bucket_size, relay_global_uplink_limit_bucket_size, relay_overall_limit_bucket_size, 
           allow_roaming, rx1_delay
    FROM device_profile 
    WHERE tenant_id = '${SRC_TENANT}'
  ) TO STDOUT WITH (FORMAT binary);`,
  `COPY device_profile FROM STDIN WITH (FORMAT binary);`
);

// 2. Gateway
migrateTable(
  "gateway",
  `COPY (
    SELECT gateway_id, '${DST_TENANT}'::uuid, created_at, updated_at, last_seen_at, name, description, 
           latitude, longitude, altitude, stats_interval_secs, tls_certificate, tags, properties
    FROM gateway
    WHERE tenant_id = '${SRC_TENANT}'
  ) TO STDOUT WITH (FORMAT binary);`,
  `COPY gateway FROM STDIN WITH (FORMAT binary);`
);

// 3. Application
migrateTable(
  "application",
  `COPY (
    SELECT id, '${DST_TENANT}'::uuid, created_at, updated_at, name, description, mqtt_tls_cert, tags
    FROM application
    WHERE tenant_id = '${SRC_TENANT}'
  ) TO STDOUT WITH (FORMAT binary);`,
  `COPY application FROM STDIN WITH (FORMAT binary);`
);

// 4. Application Integration
migrateTable(
  "application_integration",
  `COPY (
    SELECT ai.application_id, ai.kind, ai.created_at, ai.updated_at, ai.configuration
    FROM application_integration ai
    JOIN application a ON ai.application_id = a.id
    WHERE a.tenant_id = '${SRC_TENANT}'
  ) TO STDOUT WITH (FORMAT binary);`,
  `COPY application_integration FROM STDIN WITH (FORMAT binary);`
);

// 5. Device
migrateTable(
  "device",
  `COPY (
    SELECT d.dev_eui, d.application_id, d.device_profile_id, d.created_at, d.updated_at, d.last_seen_at, 
           d.scheduler_run_after, d.name, d.description, d.external_power_source, d.battery_level, d.margin, 
           d.dr, d.latitude, d.longitude, d.altitude, d.dev_addr, d.enabled_class, d.skip_fcnt_check, 
           d.is_disabled, d.tags, d.variables, d.join_eui, d.secondary_dev_addr, d.device_session
    FROM device d
    JOIN application a ON d.application_id = a.id
    WHERE a.tenant_id = '${SRC_TENANT}'
  ) TO STDOUT WITH (FORMAT binary);`,
  `COPY device FROM STDIN WITH (FORMAT binary);`
);

// 6. Device Keys
migrateTable(
  "device_keys",
  `COPY (
    SELECT dk.dev_eui, dk.created_at, dk.updated_at, dk.nwk_key, dk.app_key, dk.dev_nonces, dk.join_nonce
    FROM device_keys dk
    JOIN device d ON dk.dev_eui = d.dev_eui
    JOIN application a ON d.application_id = a.id
    WHERE a.tenant_id = '${SRC_TENANT}'
  ) TO STDOUT WITH (FORMAT binary);`,
  `COPY device_keys FROM STDIN WITH (FORMAT binary);`
);

console.log("\n🎉 Synchronization complete!");
