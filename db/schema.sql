-- Underworld Admissions Registry — PostgreSQL schema + seed data
-- ISOLATED CYBERSECURITY LAB ONLY. Intentionally insecure for SQL-injection training.
-- Authentication is handled by Active Directory, so this DB holds NO passwords —
-- only application data and the staff directory (the loot that targets phishing).

DROP TABLE IF EXISTS souls;
DROP TABLE IF EXISTS wardens;

-- Public admissions records (what the SQLi search exposes)
CREATE TABLE souls (
  id              SERIAL PRIMARY KEY,
  full_name       TEXT NOT NULL,
  realm_of_origin TEXT,
  crime           TEXT
);

-- Staff directory — profile data only (NO passwords; auth is via AD).
-- This is the juicy table: usernames + emails = the phishing targeting list.
CREATE TABLE wardens (
  id          SERIAL PRIMARY KEY,
  username    TEXT UNIQUE NOT NULL,
  full_name   TEXT,
  email       TEXT,
  role        TEXT,
  department  TEXT
);

INSERT INTO souls (full_name, realm_of_origin, crime) VALUES
 ('Tantalus',    'Lydia',     'Served the flesh of his son to the gods'),
 ('Ixion',       'Thessaly',  'Betrayed the hospitality of Zeus'),
 ('Sisyphus',    'Ephyra',    'Cheated death twice'),
 ('The Danaids', 'Argos',     'Murdered their husbands on their wedding night'),
 ('Ocnus',       'Boeotia',   'Condemned to endless futility'),
 ('Phlegyas',    'Thessaly',  'Burned the temple of Apollo'),
 ('Salmoneus',   'Elis',      'Impersonated Zeus');

INSERT INTO wardens (username, full_name, email, role, department) VALUES
 ('charon',   'Charon',   'charon@hades.underworld', 'Ferryman',      'Transit'),
 ('cerberus', 'Cerberus', 'warden@hades.underworld', 'Gatekeeper',    'Security'),
 ('minos',    'Minos',    'minos@hades.underworld',  'Judge',         'Judgement'),
 ('persephone',    'Persephone',    'queen@hades.underworld',  'Queen',         'Garden'),
 ('hades',    'Hades',    'lord@hades.underworld',   'Administrator', 'Executive');
