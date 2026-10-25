/* =============================================================================
   00_load_postgres.sql  (only needed if you want to run the analysis in PostgreSQL)

   1. Run  python run_analysis.py  once. It downloads the data and writes the
      CSVs into the data/ folder.
   2. Open psql in the project folder and run:   \i 00_load_postgres.sql
   3. Then run the analysis files 01, 02 and 03 the same way.
   ============================================================================= */

DROP TABLE IF EXISTS transactions, products, campaigns, campaign_descriptions;

CREATE TABLE transactions (
    household_id          BIGINT,
    store_id              BIGINT,
    basket_id             BIGINT,
    product_id            BIGINT,
    quantity              NUMERIC,
    sales_value           NUMERIC,
    retail_disc           NUMERIC,
    coupon_disc           NUMERIC,
    coupon_match_disc     NUMERIC,
    week                  INT,
    transaction_timestamp TIMESTAMP
);

CREATE TABLE products (
    product_id       BIGINT PRIMARY KEY,
    manufacturer_id  BIGINT,
    department       TEXT,
    brand            TEXT,
    product_category TEXT,
    product_type     TEXT,
    package_size     TEXT
);

CREATE TABLE campaigns (
    campaign_id  INT,
    household_id BIGINT
);

CREATE TABLE campaign_descriptions (
    campaign_id   INT PRIMARY KEY,
    campaign_type TEXT,
    start_date    DATE,
    end_date      DATE
);

\copy transactions          FROM 'data/transactions.csv'          CSV HEADER
\copy products              FROM 'data/products.csv'              CSV HEADER
\copy campaigns             FROM 'data/campaigns.csv'             CSV HEADER
\copy campaign_descriptions FROM 'data/campaign_descriptions.csv' CSV HEADER

CREATE INDEX ON transactions (household_id, transaction_timestamp);
CREATE INDEX ON transactions (product_id);
ANALYZE;
