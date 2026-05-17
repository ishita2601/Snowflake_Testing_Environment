import streamlit as st
import json
import re

from utils.helpers import (
    run_query,
    exec_query,
    safe_str
)
# ============================================================
# CONFIGURATION
# ============================================================
elif page == "Configuration":

    st.header("Configuration Manager")

    configs = run_query("""
        SELECT CONFIG_ID, PROJECT_NAME, IS_ACTIVE, CREATED_AT, UPDATED_AT
        FROM CLAID_TEST.CONFIG
        ORDER BY UPDATED_AT DESC
    """)

    st.subheader("Existing Configurations")
    st.dataframe(configs, use_container_width=True)

    st.divider()
    st.subheader("Create / Update a Config")

    project_name = st.text_input("Project Name", placeholder="e.g. CLIENT_ABC")

    # --- Schema guide shown to users and used in the Cortex prompt ---
    schema_example = """{
  "project": "MY_PROJECT",
  "snowflake_schema": "MY_DB.MY_SCHEMA",
  "tests": [
    {
      "table": "MY_TABLE",
      "checks": [
        {"type": "row_count",             "min": 1000, "max": 999999},
        {"type": "no_nulls",              "column": "MY_COLUMN"},
        {"type": "no_duplicates",         "column": "MY_COLUMN"},
        {"type": "value_range",           "column": "AMOUNT", "min": 0, "max": 99999},
        {"type": "freshness",             "column": "UPDATED_AT", "max_age_hours": 24},
        {"type": "referential_integrity", "fk_column": "FK_COL",
                                          "ref_table": "REF_TABLE", "ref_column": "PK_COL"},
        {"type": "schema_match",          "expected_columns": ["COL_A","COL_B"]},
        {"type": "custom_sql",            "query": "SELECT COUNT(*) FROM MY_SCHEMA.MY_TABLE WHERE AMOUNT < 0"}
      ]
    }
  ],
  "object_exists": [
    {"type": "view",             "name": "MY_VIEW"},
    {"type": "stored_procedure", "name": "MY_PROC"},
    {"type": "task",             "name": "MY_TASK"}
  ]
}"""

    with st.expander("JSON Schema Reference"):
        st.code(schema_example, language="json")

    user_prompt = st.text_area(
        "Describe your tests in plain English (Cortex will generate the JSON)",
        height=120,
        placeholder="e.g. Check ORDERS table has no nulls in ORDER_ID, no duplicates, "
                    "row count between 100 and 50000, and was updated in the last 6 hours."
    )

    if st.button("Generate Config with Cortex"):
        if not user_prompt.strip():
            st.warning("Enter a description first.")
        else:
            escaped_prompt = safe_str(user_prompt)
            escaped_schema = safe_str(schema_example)

            result_df = run_query(f"""
                SELECT SNOWFLAKE.CORTEX.COMPLETE(
                    'mistral-large',
                    $$
You are a Snowflake data quality configuration assistant.
Convert the user's plain-English test description into a valid JSON config
that EXACTLY matches this schema:

{schema_example}

Rules:
- Output ONLY the raw JSON object. No explanation, no markdown, no backticks.
- Use only test types from the schema above.
- Fill in "snowflake_schema" as "DATABASE.SCHEMA" based on context clues.
- If min/max are not mentioned, use sensible defaults.

User request:
{escaped_prompt}
                    $$
                ) AS CONFIG_JSON
            """)

            if not result_df.empty:
                generated = result_df.iloc[0]["CONFIG_JSON"]
                # Strip markdown fences if model added them
                generated = re.sub(r"```json|```", "", generated).strip()
                st.session_state["generated_cfg"] = generated
                st.code(generated, language="json")

    if "generated_cfg" in st.session_state:
        st.divider()
        edited_cfg = st.text_area(
            "Edit the generated config before saving (optional)",
            value=st.session_state["generated_cfg"],
            height=300
        )

        if st.button("Save Config"):
            if not project_name.strip():
                st.warning("Enter a Project Name before saving.")
            else:
                # Validate JSON before saving
                try:
                    json.loads(edited_cfg)
                except json.JSONDecodeError as e:
                    st.error(f"Invalid JSON — fix it before saving: {e}")
                    st.stop()

                sp_proj    = safe_str(project_name)
                sp_cfg     = safe_str(edited_cfg)

                # Soft-deactivate previous version
                exec_query(f"""
                    UPDATE CLAID_TEST.CONFIG
                    SET IS_ACTIVE = FALSE
                    WHERE PROJECT_NAME = '{sp_proj}'
                """)

                ok = exec_query(f"""
                    INSERT INTO CLAID_TEST.CONFIG (PROJECT_NAME, CONFIG_JSON, IS_ACTIVE, UPDATED_AT)
                    SELECT
                        '{sp_proj}',
                        PARSE_JSON($$ {sp_cfg} $$),
                        TRUE,
                        CURRENT_TIMESTAMP()
                """)

                if ok:
                    st.success(f"Config saved for project '{project_name}' ✔")
                    del st.session_state["generated_cfg"]

