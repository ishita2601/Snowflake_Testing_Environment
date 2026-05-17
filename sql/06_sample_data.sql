CREATE OR REPLACE TABLE ORDERS (
    ORDER_ID NUMBER,
    CUSTOMER_ID NUMBER,
    AMOUNT NUMBER,
    CREATED_AT TIMESTAMP,
    UPDATED_AT TIMESTAMP
);

CREATE OR REPLACE TABLE CUSTOMERS (
    CUSTOMER_ID NUMBER
);

INSERT INTO CUSTOMERS VALUES (1),(2),(3);

INSERT INTO ORDERS VALUES
(101,1,500,CURRENT_TIMESTAMP(),CURRENT_TIMESTAMP()),
(102,2,1500,CURRENT_TIMESTAMP(),CURRENT_TIMESTAMP()),
(103,3,2000,CURRENT_TIMESTAMP(),CURRENT_TIMESTAMP());

CREATE OR REPLACE VIEW V_ORDERS AS
SELECT * FROM ORDERS;
INSERT INTO CONFIG (PROJECT_NAME, CONFIG_JSON, IS_ACTIVE)
SELECT
'SAMPLE_PROJECT',
PARSE_JSON('{
  "project": "SAMPLE_PROJECT",
  "snowflake_schema": "CLAID_TEST_DB.CLAID_TEST",
  "tests": [
    {
      "table": "ORDERS",
      "checks": [
        {"type": "row_count", "min": 1, "max": 10000},
        {"type": "no_nulls", "column": "ORDER_ID"},
        {"type": "no_duplicates", "column": "ORDER_ID"},
        {"type": "value_range", "column": "AMOUNT", "min": 100, "max": 5000},
        {"type": "referential_integrity", "fk_column": "CUSTOMER_ID", "ref_table": "CUSTOMERS", "ref_column": "CUSTOMER_ID"},
        {"type": "freshness", "column": "CREATED_AT", "max_age_hours": 24},
        {"type": "schema_match", "expected_columns": ["ORDER_ID","CUSTOMER_ID","AMOUNT","CREATED_AT","UPDATED_AT"]},
        {"type": "custom_sql", "query": "SELECT COUNT(*) FROM CLAID_TEST_DB.CLAID_TEST.ORDERS WHERE AMOUNT < 0"}
      ]
    }
  ],
  "object_exists": [
    {"type": "view", "name": "V_ORDERS"},
    {"type": "stored_procedure", "name": "SP_RUN_TESTS"}
  ]
}'),
TRUE;
