UPDATE CLAID_TEST.CONFIG
SET CONFIG_JSON = PARSE_JSON('{
  "object_exists": [
    {"name": "V_ORDERS", "type": "view"},
    {"name": "SP_RUN_TESTS", "type": "stored_procedure"}
  ],
  "project": "SAMPLE_PROJECT",
  "snowflake_schema": "CLAID_TEST_DB.CLAID_TEST",
  "tests": [
    {
      "table": "ORDERS",
      "checks": [
        {"type": "row_count", "min": 1, "max": 10000},
        {"type": "no_nulls", "column": "ORDER_ID"},
        {"type": "no_duplicates", "column": "ORDER_ID"},
        {"type": "value_range", "column": "AMOUNT", "min": 100, "max": 5000}
      ]
    }
  ]
}')
WHERE PROJECT_NAME = 'SAMPLE_PROJECT'
AND IS_ACTIVE = TRUE;
