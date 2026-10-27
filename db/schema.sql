-- Underworld Admissions Registry — PostgreSQL schema + seed data
-- ISOLATED CYBERSECURITY LAB ONLY. Intentionally insecure for SQL-injection training.
-- Loaded by db/setup_db.sh on the Ubuntu VM.

DROP TABLE IF EXISTS souls;
DROP TABLE IF EXISTS wardens;

-- Public admissions records (the data the SQLi search exposes)
CREATE TABLE souls (
  id              SERIAL PRIMARY KEY,
  full_name       TEXT NOT NULL,
  realm_of_origin TEXT,
  crime           TEXT
);

-- Staff credentials (the juicy table reachable via UNION-based injection)
CREATE TABLE wardens (
  id            SERIAL PRIMARY KEY,
  username      TEXT UNIQUE NOT NULL,
  email         TEXT,
  password_hash TEXT,   -- md5 of weak words, crackable on purpose
  role          TEXT
);

INSERT INTO souls (full_name, realm_of_origin, crime) VALUES
 ('Tantalus',       'Lydia',     'Served the flesh of his son to the gods'),
 ('Ixion',          'Thessaly',  'Betrayed the hospitality of Zeus'),
 ('Sisyphus',       'Ephyra',    'Cheated death twice'),
 ('The Danaids',    'Argos',     'Murdered their husbands on their wedding night'),
 ('Ocnus',          'Boeotia',   'Condemned to endless futility'),
 ('Phlegyas',       'Thessaly',  'Burned the temple of Apollo'),
 ('Salmoneus',      'Elis',      'Impersonated Zeus');

INSERT INTO wardens (username, email, password_hash, role) VALUES
 ('charon',   'charon@hades.underworld',   md5('ferryman'),   'ferryman'),
 ('cerberus', 'warden@hades.underworld',   md5('threeheads'), 'gatekeeper'),
 ('minos',    'minos@hades.underworld',    md5('judgement'),  'judge'),
 ('hades',    'lord@hades.underworld',     md5('persephone'), 'admin');
