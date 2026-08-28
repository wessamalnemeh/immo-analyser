-- Runs automatically the first time the postgres container starts
-- (docker-entrypoint-initdb.d convention). If you change this file after
-- the volume already exists, it will NOT re-run -- drop the volume or
-- apply changes manually via psql.

CREATE TABLE IF NOT EXISTS immo_offers (
    expose_id        text        PRIMARY KEY,          -- eindeutige ID aus dem Link
    titel            text,
    link             text,
    addresse         text,
    kaufpreis        text,                             -- Originaltext, z.B. "82.000 €"
    wohnflaeche      text,                             -- "82 m²"
    zimmer           numeric(4,1),
 
    -- Herkunft
    mail_id          text,
    mail_subject     text,
    mail_date        timestamptz,
 
    -- Bearbeitungsstatus
    processed        boolean     NOT NULL DEFAULT false,
    processed_at     timestamptz,
    note             text,
 
    -- Duplikat-Tracking
    first_seen_at    timestamptz NOT NULL DEFAULT now(),
    last_seen_at     timestamptz NOT NULL DEFAULT now(),
    seen_count       integer     NOT NULL DEFAULT 1
);

CREATE INDEX IF NOT EXISTS immo_offers_open_idx
    ON immo_offers (first_seen_at DESC)
    WHERE processed = false;


CREATE TABLE immo_offers_details (
  -- Primary
  id                        SERIAL PRIMARY KEY,
  listing_id                VARCHAR(50) UNIQUE,
  url                       TEXT,
  title                     TEXT,
  property_type             VARCHAR(100),

  -- Location
  street                    VARCHAR(255),
  city                      VARCHAR(100),
  zip_code                  VARCHAR(10),
  district                  VARCHAR(100),
  state                     VARCHAR(100),
  country                   CHAR(2) DEFAULT 'DE',

  -- Property
  living_area_m2            NUMERIC(8,2),
  total_area_m2             NUMERIC(8,2),
  land_area_m2              NUMERIC(8,2),
  rooms                     NUMERIC(4,1),
  bedrooms                  INTEGER,
  bathrooms                 INTEGER,
  floor                     INTEGER,
  total_floors              INTEGER,
  year_built                INTEGER,
  last_renovation_year      INTEGER,
  condition                 VARCHAR(100),
  has_balcony               BOOLEAN,
  has_terrace               BOOLEAN,
  has_garden                BOOLEAN,
  has_cellar                BOOLEAN,
  has_elevator              BOOLEAN,
  parking_spots             INTEGER,
  parking_type              VARCHAR(100),
  monument_protected        BOOLEAN,

  -- Financials
  purchase_price_eur        NUMERIC(12,2),
  price_per_m2_eur          NUMERIC(8,2),
  monthly_cold_rent_eur     NUMERIC(8,2),
  monthly_warm_rent_eur     NUMERIC(8,2),
  monthly_service_charges_eur NUMERIC(8,2),
  monthly_hoa_fee_eur       NUMERIC(8,2),
  annual_gross_rent_eur     NUMERIC(10,2),
  gross_yield_percent       NUMERIC(5,2),
  ground_rent_eur           NUMERIC(8,2),
  is_currently_rented       BOOLEAN,
  rent_indexed              BOOLEAN,

  -- Transaction
  commission_buyer_percent  NUMERIC(5,2),
  commission_buyer_eur      NUMERIC(10,2),
  available_from            VARCHAR(100),
  listing_date              DATE,

  -- Energy
  energy_class              VARCHAR(5),
  energy_consumption_kwh_m2 NUMERIC(7,2),
  heating_type              VARCHAR(100),
  energy_certificate_type   VARCHAR(100),

  -- Metadata
  created_at                TIMESTAMPTZ DEFAULT NOW(),
  updated_at                TIMESTAMPTZ DEFAULT NOW()
);

-- Auto-update updated_at on row change
CREATE OR REPLACE FUNCTION update_immo_offers_details_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER immo_offers_details_updated_at
  BEFORE UPDATE ON immo_offers_details
  FOR EACH ROW
  EXECUTE FUNCTION update_immo_offers_details_updated_at();

-- Useful indexes
CREATE INDEX idx_offers_city          ON immo_offers_details(city);
CREATE INDEX idx_offers_zip_code      ON immo_offers_details(zip_code);
CREATE INDEX idx_offers_purchase_price ON immo_offers_details(purchase_price_eur);
CREATE INDEX idx_offers_gross_yield   ON immo_offers_details(gross_yield_percent);
CREATE INDEX idx_offers_created_at    ON immo_offers_details(created_at);