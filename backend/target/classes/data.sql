-- ─── bike_brand ───────────────────────────────────────────────────────────────
INSERT INTO bike_brand (name) VALUES ('BONNELL');     -- id=1
INSERT INTO bike_brand (name) VALUES ('RISTRETTO');   -- id=2
INSERT INTO bike_brand (name) VALUES ('Talaria');     -- id=3
INSERT INTO bike_brand (name) VALUES ('Sur-Ron');     -- id=4
INSERT INTO bike_brand (name) VALUES ('E Ride');      -- id=5
INSERT INTO bike_brand (name) VALUES ('RERODE');      -- id=6

-- ─── bike_model ───────────────────────────────────────────────────────────────
-- BONNELL (brand_id=1)
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (1, '775 MX', 'CYC X1 Pro Gen4', 6000, 280, 'CYC A65', '65V', 1300);             -- id=1
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (1, '775 AM', 'CYC Photon', 1200, 110, 'CYC A-Series', '52V', 520);              -- id=2
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (1, '805', NULL, 3000, 110, NULL, NULL, 3100);                                     -- id=3
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (1, '902', NULL, 4600, 110, NULL, NULL, 6600);                                     -- id=4

-- RISTRETTO (brand_id=2)
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (2, '512 A20', 'RISTRETTO 512 A20 Motor', 4500, NULL, 'Catalina Battery Pack', '52V', 1550);  -- id=5
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (2, '512 A24', 'RISTRETTO 512 A24 Motor', 4500, NULL, 'Catalina Battery Pack', '52V', 1550);  -- id=6

-- Talaria (brand_id=3)
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (3, 'X3 Pro', 'Talaria X3 Pro', 5500, NULL, 'Talaria Stock XXX', '60V', 2400);   -- id=7
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (3, 'Komodo', 'Talaria Komodo', 3200, 90, 'Talaria Komodo', '96V', 4300);         -- id=8
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (3, 'Sting MX5', 'Talaria MX5', 13400, 90, 'Talaria MX5', '72V', 2880);          -- id=9
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (3, 'Sting LE1/MX', 'Talaria Sting', 6000, 34, 'Talaria Sting', '60V', 2300);   -- id=10
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (3, 'Dragon', 'Talaria Dragon', 28000, 630, 'Talaria Dragon', NULL, 5200);        -- id=11
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (3, 'Sting R MX4 Expert', 'Talaria Sting R', 6000, 34, 'Talaria Sting MX4', '60V', 2280); -- id=12
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (3, 'Sting MX4', 'Talaria Sting MX4', NULL, NULL, 'Talaria Sting MX4', '60V', 2700); -- id=13
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (3, 'Sting MX3', 'Talaria Sting MX4', NULL, NULL, 'Talaria Sting MX4', '60V', 2700); -- id=14
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (3, 'X3 (XXX)', 'Talaria XXX', 6500, NULL, 'Talaria XXX', '60V', 2400);          -- id=15

-- Sur-Ron (brand_id=4)
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (4, 'Hyper Bee 14/12', NULL, 5000, 159, NULL, '50.4V', 1260);                     -- id=16
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (4, 'Hyper Bee 12/10', NULL, 5000, 143, NULL, '50.4V', 1260);                     -- id=17
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (4, 'Light Bee X', NULL, 8000, 266, NULL, '60V', 2400);                            -- id=18
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (4, 'Light Bee L', NULL, 8000, 266, NULL, '60V', 2400);                            -- id=19
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (4, 'Ultra Bee HP', NULL, 21000, 511, NULL, '74V', 4440);                          -- id=20
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (4, 'Ultra Bee R', NULL, 12500, 440, NULL, '74V', 4070);                           -- id=21
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (4, 'Ultra Bee T', NULL, 12500, 440, NULL, '74V', 4070);                           -- id=22
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (4, 'Storm Bee E', NULL, 22500, 440, NULL, '104V', 5720);                          -- id=23
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (4, 'Storm Bee F', NULL, 22500, 520, NULL, '104V', 5720);                          -- id=24

-- E Ride (brand_id=5)
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (5, 'Pro-SR', NULL, 25000, NULL, NULL, '72V', 3600);                               -- id=25
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (5, 'Pro-S', NULL, 8000, NULL, NULL, '72V', 2160);                                 -- id=26
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (5, 'Pro-SS 2.0', NULL, 12000, NULL, NULL, '72V', 2880);                           -- id=27
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (5, 'Pro-SS 3.0', NULL, 15800, NULL, NULL, '72V', 3600);                           -- id=28
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (5, 'Mini', NULL, 6000, 210, NULL, '60V', 1800);                                   -- id=29

-- RERODE (brand_id=6)
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (6, 'R1', NULL, 8000, 330, NULL, '72V', 2520);                                     -- id=30
INSERT INTO bike_model (brand_id, model_name, motor_type, motor_peak_power_w, motor_torque_nm, battery_type, battery_voltage, battery_capacity_wh)
  VALUES (6, 'R1+', NULL, 10000, 390, NULL, '72V', 2520);                                   -- id=31

-- ─── bike_spec ────────────────────────────────────────────────────────────────
-- BONNELL 775 MX (model_id=1)
INSERT INTO bike_spec (model_id, motor, controller) VALUES (1, 'CYC X1 Pro Gen4', 'CYC Controller V4');   -- id=1
INSERT INTO bike_spec (model_id, motor, controller) VALUES (1, 'CYC X1 Pro Gen3', 'CYC Controller V3');   -- id=2  ← TRX-7A2B

-- BONNELL 775 AM (model_id=2)
INSERT INTO bike_spec (model_id, motor, controller) VALUES (2, 'CYC Photon', 'CYC Photon Controller');    -- id=3

-- Sur-Ron Light Bee X (model_id=18) — aftermarket KO builds
INSERT INTO bike_spec (model_id, motor, controller) VALUES (18, 'KO F-SPEC', 'KO RUSH (F-SPEC)');        -- id=4  ← TRX-3F9C
INSERT INTO bike_spec (model_id, motor, controller) VALUES (18, 'KO RS', 'KO PRO');                       -- id=5

-- Sur-Ron Ultra Bee R (model_id=21)
INSERT INTO bike_spec (model_id, motor, controller) VALUES (21, 'KO Big Block', 'KO PRO');                -- id=6

-- ─── trax_module ──────────────────────────────────────────────────────────────
-- TRX-7A2B: CYC official module, unbound, certified spec for BONNELL 775 MX Gen3
INSERT INTO trax_module (serial_no, name, bound, bike_spec_id) VALUES ('TRX-7A2B', 'CYC TRAX Module', false, 2);

-- TRX-3F9C: already bound to a Sur-Ron KO F-SPEC build
INSERT INTO trax_module (serial_no, name, bound, bike_spec_id) VALUES ('TRX-3F9C', 'Sur-Ron Custom Build', true, 4);

-- TRX-12DE: generic module, no certified spec
INSERT INTO trax_module (serial_no, name, bound, bike_spec_id) VALUES ('TRX-12DE', 'Generic TRAX Module', false, NULL);

-- TRX-4B1A: another CYC module with Gen4 spec
INSERT INTO trax_module (serial_no, name, bound, bike_spec_id) VALUES ('TRX-4B1A', 'CYC TRAX Module', false, 1);
